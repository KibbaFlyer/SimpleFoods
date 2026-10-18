"""Deterministic packaging helpers; input contract defined alongside A01 fixtures."""
import hashlib
import json
import re
from decimal import Decimal, InvalidOperation
from pathlib import Path

class ValidationError(ValueError):
    pass

def require(condition, message):
    if not condition:
        raise ValidationError(message)

def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def file_digest(path):
    with Path(path).open('rb') as stream:
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(65536), b''):
            result.update(block)
        return result.hexdigest()

def decimal(value, positive=False):
    require(isinstance(value, str) and re.fullmatch(r'(0|[1-9][0-9]*)(\.[0-9]+)?', value) is not None,
            'decimal must be an unsigned plain decimal string')
    require(len(value.partition('.')[0]) <= 12 and len(value.partition('.')[2]) <= 9,
            'decimal exceeds scaffold precision limits (12 integer digits / 9 decimal places)')
    try:
        result = Decimal(value)
    except InvalidOperation as error:
        raise ValidationError('invalid decimal') from error
    require(result.is_finite() and result >= 0 and (not positive or result > 0), 'invalid decimal range')
    return result

def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    with Path(path).open(encoding='utf-8') as stream:
        try:
            return json.load(stream, object_pairs_hook=unique, parse_constant=lambda v: (_ for _ in ()).throw(ValidationError('nonfinite JSON')))
        except json.JSONDecodeError as error:
            raise ValidationError('malformed JSON input') from error

def allowed_input(path, allowlisted_inputs):
    """Exact resolved files, never directory discovery; reject symlink entry points."""
    require(isinstance(path, (str, Path)), 'input path must be text or Path')
    require(isinstance(allowlisted_inputs, (list, tuple, set)), 'allowlist must be a collection of exact paths')
    require(all(isinstance(item,(str,Path)) for item in allowlisted_inputs), 'allowlist paths must be text or Path')
    path = Path(path)
    require(not path.is_symlink(), 'symlink input forbidden')
    resolved = path.resolve(strict=True)
    allowed = {Path(item).resolve(strict=True) for item in allowlisted_inputs}
    require(resolved in allowed, 'input file is not explicitly allowlisted')
    require(resolved.is_file(), 'input must be regular file')
    require(resolved.stat().st_size <= 16 * 1024 * 1024, 'input exceeds fixture scaffold limit')
    return resolved
