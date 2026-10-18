# Simple Foods Open Food Facts search index

`OFFNameIndex.jsonl` is a derived database built from the official Open Food
Facts bulk CSV export.

Each retained record contains its barcode, available Swedish/English/German
product names, sales markets, energy per 100 g, and the brand when provided by
Open Food Facts.

## Attribution and license

Database source: **Open Food Facts contributors**

This derived database is made available under the Open Database License
(ODbL) 1.0:

https://opendatacommons.org/licenses/odbl/1-0/

Rights in individual database contents are licensed under the Database
Contents License (DbCL) 1.0:

https://opendatacommons.org/licenses/dbcl/1-0/

This dataset is licensed separately from the Simple Foods application source
code. The application source is MIT licensed; this dataset is ODbL licensed.
The unencrypted source form of the derived database is this JSON Lines file in
the public source repository.

## Generation record

- Upstream export: `https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz`
- Generator: `Tools/build_off_name_index.py`
- Markets retained: Sweden and Germany
- Records retained only when the barcode is a valid GTIN-8, UPC-A, or EAN-13;
  the product has a name; and energy, protein, carbohydrate, and fat values are
  present and nonnegative.
- Output ordering and JSON encoding are deterministic.
- Current generation time: 2026-10-15T05:47:11.506557+00:00
- Current record count: 239,025
- Current SHA-256: `32f226e514679a9f29fd4302e42a196858fee7fa413ae9f71d15273331eefa13`

Future runs of the generator write `OFFNameIndex.metadata.json` with the exact
UTC generation time, source URL, record count, and SHA-256 digest.

## Data disclaimer

Open Food Facts is a community-maintained database. Open Food Facts provides
no assurance that the data is accurate, complete, or reliable. Use of the data
is at the user's own risk. Open Food Facts does not endorse Simple Foods.
