#!/usr/bin/env python3
"""Build the compact OFF name index bundled by Simple Foods.

Streams the official full JSONL export, retains products sold in supported
markets with safely interpretable nutrition, and writes deterministic JSON
Lines. JSONL is required because the smaller CSV export omits nutrient
modifiers and prepared nutrition details.
"""
import gzip
import hashlib
import io
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path

EXPORT = os.environ.get(
    "OFF_EXPORT",
    "https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz",
)
MARKETS = {"en:sweden": "SE", "en:germany": "DE"}
NUTRIENTS = (
    ("energy-kcal", "kcal"),
    ("proteins", "g"),
    ("carbohydrates", "g"),
    ("fat", "g"),
    ("saturated-fat", "g"),
    ("sugars", "g"),
    ("fiber", "g"),
    ("salt", "g"),
)
REQUIRED_NUTRIENTS = {"energy-kcal", "proteins", "carbohydrates", "fat"}


def valid_barcode(code: str) -> bool:
    if not code.isdigit() or len(code) not in (8, 12, 13):
        return False
    digits = [int(value) for value in code]
    total = sum(value * (3 if offset % 2 == 0 else 1) for offset, value in enumerate(reversed(digits[:-1])))
    return (10 - total % 10) % 10 == digits[-1]


def decimal_value(raw: object) -> Decimal | None:
    if isinstance(raw, bool) or raw is None:
        return None
    try:
        value = Decimal(str(raw))
    except InvalidOperation:
        return None
    return value if value.is_finite() and value >= 0 else None


def supported_modifier(modifier: object) -> bool:
    return modifier is None or modifier == "~"


def structured_nutrition(product: dict) -> tuple[Decimal, bool] | None:
    aggregated = product.get("nutrition", {}).get("aggregated_set")
    if not isinstance(aggregated, dict):
        return None
    preparation = aggregated.get("preparation")
    basis = aggregated.get("per")
    values = aggregated.get("nutrients")
    if preparation not in ("as_sold", "prepared") or basis not in ("100g", "100ml") or not isinstance(values, dict):
        return None
    accepted: dict[str, Decimal] = {}
    approximate = False
    for key, unit in NUTRIENTS:
        nutrient = values.get(key)
        if not isinstance(nutrient, dict):
            continue
        modifier = nutrient.get("modifier")
        value = decimal_value(nutrient.get("value"))
        if (
            not supported_modifier(modifier)
            or nutrient.get("source_per") != basis
            or nutrient.get("source") != "packaging"
            or nutrient.get("unit") != unit
            or value is None
        ):
            continue
        accepted[key] = value
        approximate = approximate or modifier == "~"
    if not REQUIRED_NUTRIENTS.issubset(accepted):
        return None
    return accepted["energy-kcal"], approximate


def legacy_candidate(product: dict, preparation: str) -> tuple[Decimal, bool] | None:
    prepared = preparation == "prepared"
    basis_key = "nutrition_data_prepared_per" if prepared else "nutrition_data_per"
    basis = product.get(basis_key)
    if basis not in ("100g", "100ml"):
        return None
    if basis == "100g" and product.get("product_quantity_unit") in ("ml", "cl", "l"):
        return None
    nutriments = product.get("nutriments")
    if not isinstance(nutriments, dict):
        return None
    accepted: dict[str, Decimal] = {}
    approximate = False
    infix = "_prepared" if prepared else ""
    for key, unit in NUTRIENTS:
        modifier = nutriments.get(f"{key}{infix}_modifier")
        value = decimal_value(nutriments.get(f"{key}{infix}_100g"))
        if not supported_modifier(modifier) or nutriments.get(f"{key}{infix}_unit") != unit or value is None:
            continue
        accepted[key] = value
        approximate = approximate or modifier == "~"
    if not REQUIRED_NUTRIENTS.issubset(accepted):
        return None
    return accepted["energy-kcal"], approximate


def accepted_nutrition(product: dict) -> tuple[Decimal, bool] | None:
    structured = structured_nutrition(product)
    if structured is not None:
        return structured
    return legacy_candidate(product, "as_sold") or legacy_candidate(product, "prepared")


def string_tags(raw: object) -> set[str]:
    if isinstance(raw, list):
        return {value for value in raw if isinstance(value, str)}
    if isinstance(raw, str):
        return set(filter(None, raw.split(",")))
    return set()


def main(output: str) -> None:
    records = {}
    process = subprocess.Popen(
        ["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "4", "--user-agent", "SimpleFoods-build/1.0", EXPORT],
        stdout=subprocess.PIPE,
    )
    try:
        stream = io.TextIOWrapper(gzip.GzipFile(fileobj=process.stdout), encoding="utf-8", errors="replace")
        for line in stream:
            try:
                product = json.loads(line)
            except json.JSONDecodeError:
                continue
            code = str(product.get("code", "")).strip()
            if not valid_barcode(code):
                continue
            nutrition = accepted_nutrition(product)
            if nutrition is None:
                continue
            tags = string_tags(product.get("countries_tags"))
            markets = sorted(value for key, value in MARKETS.items() if key in tags)
            if not markets:
                continue
            names = {
                language: str(product.get(f"product_name_{language}", "")).strip()
                for language in ("sv", "en", "de")
            }
            names = {key: value for key, value in names.items() if value}
            fallback = str(product.get("product_name", "")).strip()
            if not names and fallback:
                names["und"] = fallback
            if not names:
                continue
            energy, approximate = nutrition
            record = {
                "barcode": code,
                "energyKcal100g": float(energy),
                "markets": markets,
                "names": names,
            }
            brand = str(product.get("brands", "")).strip()
            if brand:
                record["brand"] = brand
            if approximate:
                record["isApproximate"] = True
            records[code] = record
    finally:
        if process.stdout:
            process.stdout.close()
        if process.wait() != 0:
            raise SystemExit("Open Food Facts export download failed")
    with open(output, "w", encoding="utf-8", newline="\n") as destination:
        for code in sorted(records):
            destination.write(json.dumps(records[code], ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n")
    output_path = Path(output)
    metadata_path = output_path.with_name(f"{output_path.stem}.metadata.json")
    metadata = {
        "attribution": "Open Food Facts contributors",
        "databaseLicense": "ODbL-1.0",
        "contentsLicense": "DbCL-1.0",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "generator": "Tools/build_off_name_index.py",
        "recordCount": len(records),
        "sha256": hashlib.sha256(output_path.read_bytes()).hexdigest(),
        "source": EXPORT,
    }
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: build_off_name_index.py OUTPUT.jsonl")
    main(sys.argv[1])
