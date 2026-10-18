# D02 offline catalogue scaffold

Python 3 standard library only. No network, dependency installation, live adapter, real nutrient acquisition, or application-private store access. Implements the agreed A01 leaf-food JSON v1 wire format and D01 fail-closed registry gates. This is a developer tool; app integration and real-source adapters remain separate packages.

Run from repository/staging root:

```sh
python3 -m unittest discover -s tests/catalogue -v
python3 -m tools.catalogue --input data/fixtures/fixture-v1.json --registry data/source-registry.json --allow-input data/fixtures/fixture-v1.json --allow-input data/source-registry.json --output /private/tmp/mealtracker-pack-v1
python3 -m tools.catalogue --input data/fixtures/fixture-v2.json --previous data/fixtures/fixture-v1.json --registry data/source-registry.json --allow-input data/fixtures/fixture-v1.json --allow-input data/fixtures/fixture-v2.json --allow-input data/source-registry.json --output /private/tmp/mealtracker-pack-v2
```

Choose unused output directories. Inputs must be explicitly allowlisted exact files; the tool never scans directories or reads app stores. Source/registry files are capped at 16 MiB for this scaffold. Invalid input fails before public output publication; staging is removed after failure. Existing output directories are never overwritten.

The allowlist is an operator-controlled trust boundary, not automatic proof a file contains no personal data. Strict public field schemas prevent arbitrary notes, logs, overlays, Health payloads or unknown nested fields being carried through. An operator could still mislabel private text as a public food name: review inputs before allowlisting. No privacy or legal guarantee is inferred from field names, booleans, or file separation.

## Input contract and validation

`data/fixtures/fixture-v{1,2}.json` are exact A01 fixtures (with agreed `evidence` dictionary), fictional quantities and invented equivalences, `fixtureOnly=true`. Their barcodes are synthetic test identifiers, not verified real GTINs. Never distribute them as real products or export demo intake to real Health.

Supported: ingredient/product leaf records; catalogue identity namespace/provider matching; opaque immutable revisions; active/retired lifecycle; sv/en/de names; separate ISO alpha-2 sales/manufacturing/ingredient-origin arrays; profiles, portion/density evidence; finite unsigned decimal strings with at most 12 integer and 9 fractional digits; canonical nutrient definitions/units; strictly tagged known/knownZero/unknown/trace/derived values. Omitted nutrient keys remain unknown by A01 domain projection policy; they are not materialized as zero in storage. Decimal spellings normalize trailing zeros; arithmetic for equivalence checking uses 50-digit precision. No nutrient calculations or approximations are performed.

Unknown fields are rejected at every public v1 object layer. This intentionally tightens A01's general forward-key policy for the public ingestion boundary, as requested in review; a schema revision is required to add optional fields. Recipes, saved meals, aliases, brand/category metadata and source-specific raw records are not silently accepted: their adapter/shared schemas must be reviewed first. Evidence v1 has `kind`, `provenanceRef`, `description`; only `kind=synthetic` is supported now. Density/portion refs and derived input refs must resolve to defined same-provider evidence. Food and profile must use the identical provenance reference; cross-source composition is unsupported.

`data/source-registry.json` is the accepted D01 research baseline. Synthetic development packs are permitted; production synthetic packs are always rejected. Real-source records require acquired/schema/rights/release gates plus actual raw/terms file hashes, explicit evidence-file allowlist, attribution/version/transformation metadata, a named dated scoped release review and matching reviewer decision. OFF additionally requires the distribution offer and ODbL distribution review. The registry is trusted human review input; this tool cannot establish legal permission or authenticate a reviewer signature. All real-source release gates currently remain closed; real-source acquisition/normalization adapters and real-source evidence schemas are unsupported in this package.

## Output and immutable updates

Each output directory contains:

- `catalogue.sqlite`: schema/user_version 1, metadata, immutable `food_revision` JSON rows and hashes, provenance/evidence dictionaries, current-identity uniqueness, active-only names/market/barcode indexes.
- `catalogue.normalized.json`: portable normalized envelope; source fields preserved, set ordering and decimal spellings canonicalized.
- `manifest.json`: schema/minimum-reader/tool versions, generation/pack/calculation identities, source versions, input/registry SHA-256, logical catalogue SHA-256, counts, attribution/diff/catalogue file hashes. Manifest does not hash itself.
- `attribution.json` and `diff.json`: source notices and added/changed/retired tagged IDs.

An item sold in SE and DE is one immutable food revision with two market rows. Retained revisions remain queryable but do not become active search hits. V1→V2 marks potato retired, retains potato r1 and sausage r1, changes sausage, and removes potato from active indexes. Missing previous IDs fail rather than silently disappearing. Every prior immutable revision must remain present, including replaced current revisions and already-retained revisions. Safe garbage collection is unavailable until a reviewed pin/materialization protocol exists. Same immutable revision cannot change its content, referenced provenance, or referenced evidence. Changed envelope content requires a new generation UUID and packVersion; identical repeat inputs remain allowed. No inferred barcode/name identity merging occurs.

SQLite is built from sorted inserts into a fresh database with fixed settings; same-runtime byte reproducibility is tested. Different SQLite versions may produce different physical bytes: use `logicalSHA256`/canonical JSON for cross-runtime logical comparison and the actual per-file hash for integrity. Generation IDs and dates come only from input; there is no random/current-time field in output. Temporary staging directory names do not enter artifacts. Logical determinism does not erase source input hash differences.

Integration layout already matches requested repository destinations: `tools/catalogue/`, `tests/catalogue/`, `data/fixtures/`, `data/source-registry.json`. Samples under `examples/` are review artifacts; regenerate rather than treat as production resources. A06 must implement the reader/schema checks before using this pack in the app.
