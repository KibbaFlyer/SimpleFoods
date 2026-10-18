"""Fail-closed packaging gates. Evidence references are assertions for human review,
not automated legal clearance. Registry is build-owner-controlled input.
"""
from datetime import datetime
from urllib.parse import urlparse
from .core import require, file_digest, allowed_input

PUBLIC_PROVIDERS = {'slv', 'bls', 'off', 'mealtracker.synthetic', 'mealtracker.authored'}

def iso_instant(value):
    require(isinstance(value, str), 'timestamp must be a string')
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError:
        require(False, 'invalid timestamp')
    require(parsed.tzinfo is not None, 'timestamp needs UTC offset')
    return parsed

def url(value):
    require(isinstance(value, str), 'URL must be string')
    parsed = urlparse(value)
    require(parsed.scheme == 'https' and parsed.netloc and not parsed.username and not parsed.password,
            'source URL must be HTTPS without credentials')

def registry_sources(registry):
    require(isinstance(registry, dict), 'registry must be object')
    require(type(registry.get('schema_version')) is int and registry['schema_version'] == 1, 'unsupported source registry version')
    rows = registry.get('sources')
    require(isinstance(rows, list), 'source registry requires sources')
    result = {}
    for row in rows:
        require(isinstance(row, dict), 'registry source must be object')
        sid = row.get('source_id')
        require(isinstance(sid, str) and sid not in result, 'duplicate/invalid source registry identity')
        require(sid in PUBLIC_PROVIDERS or sid.startswith('manufacturer:'), 'unregistered provider namespace')
        result[sid] = row
    return result

def gate(source, mode, evidence_allowlist=()):
    sid = source['source_id']
    require(isinstance(mode,str) and mode in {'development', 'production'}, 'unsupported build mode')
    if sid == 'mealtracker.synthetic':
        require(mode == 'development', 'synthetic records forbidden in production')
        require(source.get('development_fixture_allowed') is True, 'synthetic development not approved')
        return
    # Development also requires real-source approval; use synthetic records until review.
    for key in ('raw_acquired', 'schema_verified', 'rights_reviewed', 'production_release_allowed'):
        require(source.get(key) is True, 'source gate not passed: ' + key)
    for key in ('upstream_version', 'licence_id', 'attribution_text', 'transformation_version',
                'reviewer_decision_reference', 'retrieved_at', 'sha256', 'terms_snapshot_sha256'):
        require(isinstance(source.get(key), str) and source[key].strip(), 'source evidence missing: ' + key)
    url(source.get('access_url'))
    iso_instant(source['retrieved_at'])
    evidence = source.get('evidence')
    require(isinstance(evidence, dict), 'source evidence files required')
    for key, sha_field in (('raw', 'sha256'), ('terms', 'terms_snapshot_sha256')):
        evidence_path = allowed_input(evidence.get(key, ''), evidence_allowlist)
        require(file_digest(evidence_path) == source[sha_field], 'source evidence checksum mismatch')
    review = source.get('release_review')
    require(isinstance(review, dict), 'signed-off release review required')
    for key in ('reviewer', 'decision_id', 'reviewed_at', 'scope', 'reason'):
        require(isinstance(review.get(key), str) and review[key].strip(), 'release review missing: ' + key)
    require(review['decision_id'] == source['reviewer_decision_reference'], 'review reference mismatch')
    require(review['scope'] == 'offline-normalized-public-pack', 'review scope mismatch')
    iso_instant(review['reviewed_at'])
    require(review.get('approved') is True, 'release review not approved')
    if sid == 'off':
        url(source.get('distribution_offer_url'))
        require(review.get('odbl_distribution_reviewed') is True, 'ODbL distribution review missing')
    require(source.get('images_included', False) is False, 'images unsupported by initial scaffold')
