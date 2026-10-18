# Third-party data and software notices

The MIT license in `LICENSE` applies to the Simple Foods application source
code. It does not replace the licenses that apply to third-party data or
dependencies.

## Open Food Facts

The bundled `OFFNameIndex.jsonl` dataset is derived from the Open Food Facts
database and is attributed to **Open Food Facts contributors**.

The database is made available under the Open Database License (ODbL) 1.0.
Rights in individual database contents are made available under the Database
Contents License (DbCL) 1.0.

- ODbL 1.0: https://opendatacommons.org/licenses/odbl/1-0/
- DbCL 1.0: https://opendatacommons.org/licenses/dbcl/1-0/
- Upstream database: https://world.openfoodfacts.org/
- Local dataset notice: `Sources/MealTrackerOpenFoodFacts/Resources/OFF_DATASET_NOTICE.md`

The bundled derived index is offered separately under ODbL 1.0 at its source
path in this repository. The app code remains MIT licensed. Open Food Facts is
a community database and provides no assurance that its data is accurate,
complete, or reliable. Use of that data is at the user's own risk. Open Food
Facts does not endorse Simple Foods.

## Livsmedelsverket

Simple Foods retrieves food and nutrition data from Livsmedelsverket's
Livsmedelsdatabasen, which is provided under Creative Commons Attribution 4.0
International (CC BY 4.0).

- Source: https://dataportal.livsmedelsverket.se/livsmedel/swagger/index.html
- License: https://creativecommons.org/licenses/by/4.0/

Simple Foods selects supported nutrient values and transforms them into its
internal nutrient format. Livsmedelsverket does not endorse Simple Foods.

## GRDB.swift

This project depends on GRDB.swift. Its license and notices are available in
the upstream project: https://github.com/groue/GRDB.swift
