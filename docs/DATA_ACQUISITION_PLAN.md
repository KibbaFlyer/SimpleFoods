# Swedish and German food database plan

Prepared 10 October 2026. This plan describes future acquisition and preparation work; no food datasets have been downloaded or imported as part of this planning task.

Read alongside the [product and architecture plan](PRODUCT_AND_ARCHITECTURE_PLAN.md). Implementation ownership is assigned in [agent work packages D01–D07](AGENT_WORK_PACKAGES.md).

## 1. Build a useful catalogue before a huge catalogue

Maintain three content classes: generic foods, identifiable branded products, and authored recipes/saved meals. A generic sausage is useful when the exact brand is unknown, but must never impersonate the nutrition of a particular manufacturer's product.

Ship both Swedish and German core content in the app bundle. No first-run download, API account, or server availability should be required. Developers can fetch sources while producing a release, then ship compact validated SQLite packs and local search indexes.

Proposed coverage targets are planning goals, not claims about current source availability:

| Stage | Generic/reference foods | Branded products | Recipes and saved meals |
| --- | --- | --- | --- |
| Development fixtures | About 40 synthetic or clearly permitted records covering edge cases | About 20 labelled fixtures | 8 test combinations |
| Internal alpha | 300 useful foods across both markets | 500 Sweden-listed + 500 Germany-listed | 20 original templates |
| First release | About 1,500 curated foods with shared staples and country-specific variants | 3,000–5,000 Sweden-listed + 3,000–5,000 Germany-listed | 40 Swedish + 20 German templates |

Count unique product variants separately from market membership; a product listed in both countries must not inflate the unique-product total twice. Translate curated generic names in all three languages. Branded names remain official names with translated category descriptors.

Prioritize category coverage, verified common products, relevant search results, and traceable nutrition over record count. Release scope may reduce if licensing or quality prevents meeting the target. Document any gap rather than inventing products, origins, translations, or nutrient values.

## 2. Sources and reuse decisions

| Source | Intended use | Verified finding and required decision |
| --- | --- | --- |
| Livsmedelsverket Livsmedelsdatabas | Swedish generic ingredients and reference prepared foods | Public download and API are described. Reuse guidance requires attribution with version date and says data must not be changed. Archive the applicable terms and clarify derived calculations, translated display names, redistribution, and clearly separated personal modifications before shipping. [Official guidance](https://www.livsmedelsverket.se/livsmedel-och-innehall/naringsamne/livsmedelsdatabasen/sok-naringsinnehall/) |
| Max Rubner-Institut, BLS 4.0 | German generic foods and reference dishes | The institute identifies version 4.0 as open data under CC BY 4.0. Use its current release, documentation, and errata, not older paid-licence assumptions. [Institute source](https://www.mri.bund.de/de/institute/ernaehrungsverhalten/forschungsbereiche/bundeslebensmittelschluessel-bls/) |
| Open Food Facts | Branded packaged products sold in Sweden and Germany | Database is ODbL; individual contents and images have distinct licences. Review attribution and derivative-database obligations for the actual distribution. [Official licensing guide](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/license-be-on-the-legal-side/) |
| Manufacturers or permitted product feeds | Fill high-value gaps and verify exact branded items | Availability and reuse rights vary. Obtain documented permitted reuse; do not assume a public webpage permits bulk copying or redistribution. |
| Independently authored recipes | Editable starter dishes and meal combinations | Create original ingredient lists and descriptions with documented calculation inputs; do not copy recipe-site prose or photographs. |

Livsmedelsverket's restrictions and Open Food Facts' share-alike requirements may affect a combined database. Separate physical files help provenance and maintenance but do not, by themselves, settle licence compatibility. D01 must record whether the planned distribution is permitted, what public database artifacts must be offered, and what notices must accompany them. If unresolved, keep that source out of the release pack while continuing with permitted sources and synthetic fixtures.

Do not include product images initially. They increase app size and introduce separate image rights and attribution work without being necessary for the requested interface.

Keep private diaries and customizations entirely outside the public data pipeline. A public catalogue release must never contain user logs. A licence interpretation must not silently trigger publication of personal data.

## 3. Coverage and acquisition priorities

### Generic staples

Create a reviewed category checklist for grains/flour, bread, pasta/rice, potatoes, vegetables, fruit/berries, legumes, nuts/seeds, eggs, dairy, plant alternatives, fish, meat, sausages, oils/fats, sauces, beverages, snacks, and baking ingredients.

Swedish priorities include vetemjöl, rågmjöl, havregryn, knäckebröd, filmjölk, kvarg, cottage cheese/keso as appropriate to generic versus branded naming, potatoes, root vegetables, cabbage, lingonberries, salmon, herring, meatballs, and generic falukorv. German priorities include flour types such as 405 and 550 when supported, rye breads, Brötchen, Quark fat variants, Kartoffeln, Sauerkraut, Bratwurst, and Spätzle.

The examples are acquisition targets, not claims that every named item is present in each source. Do not equate Swedish flour categories with German flour types without evidence. Maintain separate raw/cooked, fat-percentage, salted/unsalted, drained/undrained, and edible-portion variants where relevant.

### Branded products

Start with products users frequently distinguish by brand: falukorv and other sausages, frozen fries, meatballs, breads, dairy, ready meals, sauces, and plant alternatives. Build a small representative basket across major retailers and manufacturers in each market. Specific brands and variants must be verified during acquisition.

Use Open Food Facts bulk exports for catalogue preparation. Its documentation recommends a download when fetching more than a few hundred products; do not build a bulk importer around search-as-you-type API queries. Record the export date, digest, selected fields, and source revision. See the [official API guidance](https://github.com/openfoodfacts/openfoodfacts-server/blob/main/docs/api/index.md).

Filter by actual sales-country tags for Sweden and Germany. Do not use language, barcode prefix, brand name, or the country-specific website hostname as proof of origin or market. Keep multi-market products in both market indexes without duplicating their nutrition record.

Retain GTIN/barcodes, name, brand, variant descriptors, package quantity, nutrition basis, nutrient values, countries, preparation state, source last-modified date, and quality indicators. Retain source revision history for known reformulations. Conflicting entries with the same barcode require review, not automatic averaging.

### Starter recipes and meal combinations

Potential Swedish templates: porridge with milk and berries, knäckebröd with cheese, meatballs with potatoes, falukorv with mashed potatoes, salmon with potatoes, pea soup, and pancakes. Potential German templates: bread with cheese, Quark with fruit, potato salad, lentil soup, Bratwurst with potatoes, and vegetable Spätzle.

For each template record weighed ingredients, preparation assumptions, servings, optional measured cooked yield, component source revisions, and original text in Swedish/English/German. Present it as a particular editable recipe, not the definitive nutrition for a traditional dish. Distinguish a generic prepared-dish reference record from an authored recipe even when their names are similar.

Do not estimate branded ingredients from a generic food unless the record explicitly identifies the substitution as an estimate. Do not add an unreviewed micronutrient profile to a branded product merely because its generic category has more complete data.

## 4. Reproducible preparation pipeline

Every build should be repeatable from archived source inputs and a recorded tool/configuration version.

| Step | Deliverable | Failure behavior |
| --- | --- | --- |
| 1. Register source | Source ID, licence text/version, redistribution decision, attribution, allowed transformations | Source stays excluded if rights are unresolved |
| 2. Acquire snapshot | Raw files, retrieved-at time, upstream version, checksum, access notes | Keep the previous usable snapshot if retrieval fails |
| 3. Parse source | Source-specific records with original field names and identifiers | Quarantine malformed records; do not silently drop columns |
| 4. Normalize | Shared schema, units, nutrient-definition mapping, basis, and provenance | Reject ambiguous unit/basis transformations |
| 5. Match identities | Stable ID registry, reviewed equivalences, barcode aliases, variant handling | Preserve separate records when unsure |
| 6. Enrich | Curated translations, aliases, market metadata, portion definitions | Record each addition as authored or derived, distinct from source facts |
| 7. Validate | Machine-readable errors/warnings and human review queue | Critical errors block the affected record or entire release |
| 8. Curate | Coverage selection, search relevance corpus, verification status | Prefer a smaller accurate catalogue to unsupported filler |
| 9. Package | Source packs, manifests, licences, prebuilt index, revision map, checksums | No package without a complete manifest |
| 10. Compare and release | Added/changed/retired report, regression results, release notes | Require investigation for surprising shifts or mass removals |

Use a developer-side Python command-line pipeline with pinned dependencies as the proposed baseline. Source adapters remain separate. The packaging format and normalization contract belong to A01/D02; adapters must not invent independent schemas.

### Provenance fields

Keep the source provider, source record ID, source URL, upstream version, retrieval date, source language, licence identifier, transformation version, and reviewer status. For derived nutrient values retain the derivation, input identifiers, and units. A manual correction needs evidence and must not rewrite the archived source file.

Use coarse, honest labels such as **reference data**, **label data**, **calculated recipe**, and **user entered**. “Verified” requires a defined review process. Do not treat an Open Food Facts completeness score as proof that the label is current or correct.

### Nutrient normalization

Define an explicit nutrient crosswalk for each source, including energy, protein, fat, available/total carbohydrate, sugars, fibre, salt, and sodium. Preserve unknown, trace, and measured-zero distinctions. Normalize mass units and reference bases only when supported.

Keep declared energy rather than overwriting it with an approximate macro-derived energy sum. A mismatch can be a review signal, not automatic proof of invalidity. Store 100 ml values as volume-based; do not normalize to 100 g without a documented density.

Where available, preserve raw-versus-prepared qualifiers and any source method distinctions. Salt and sodium are related representations, not independent additive contributions. The app and the pipeline must use the same crosswalk and golden calculation cases.

## 5. Search, translation, and identity preparation

Build names and aliases in Swedish, English, and German. Include useful variants such as flour/vetemjöl/Mehl, potato/potatis/Kartoffel, fries/pommes frites/Pommes, and sausage/korv/Wurst while preserving distinctions among sausage types.

Search normalization handles case, whitespace, punctuation, accents, and common German transliterations such as ä/ae and ß/ss. Preserve original spelling for display and country-appropriate sorting. Use semantic aliases rather than treating every translation as a claim of exact food equivalence.

Maintain a human-reviewed query set, initially at least 100 Swedish, 100 German, and 50 English queries. Include brand+food combinations, misspellings, short queries, special characters, foods present in both countries, and empty-result queries.

Rank exact product/brand matches before broad category matches, then use market preference, reviewed data quality, and local recency/favorites as bounded boosts. User overlays must be indexed locally; a renamed food must be findable by its personal name. Search returns both the effective record and its provenance, not an unlabelled mix of original and edited values.

## 6. Validation and acceptance

### Automated checks

- No duplicate stable IDs, broken component references, invalid basis units, negative consumed quantities, or non-finite nutrient values.
- Plausibility checks account for rounding and nutrient overlap; do not sum all nutrients as if they were disjoint.
- Sugar versus carbohydrate and saturated versus total fat are checked according to the source definition and tolerance.
- Every conversion preserves an audit trail. Unknown values are never silently converted to zero.
- Country codes, locale codes, preparation states, and portion conversions are valid.
- All bundled UI categories and curated generic names have the agreed language coverage.
- Package checksums, source notices, schema version, and minimum reader version are present.
- Compare record counts, changed nutrition, large deviations, identifier churn, and retirements with the previous release.

### Human checks

Review the representative product basket against permitted evidence, emphasizing sausages, fries, dairy, common breads, and ready meals. Verify per-100-g versus per-serving interpretation and exact variants. Review all starter recipe quantities and all untypical conversions. Sample each generic category and review the search query set with speakers of Swedish and German.

The release report must state actual usable counts by class and market; missing nutrient rates; origin-known versus market-known rates; age of evidence; unresolved warnings; total bundle size; and expected search coverage. Do not promise coverage for all supermarket products.

Acceptance examples:

- “Falukorv” finds generic and actual branded Swedish listings with accurate Swedish listing badges.
- “Bratwurst” finds German listings, displays brand and preparation state, and does not infer German manufacture from the name.
- “French fries” finds relevant Swedish and German entries and distinguishes frozen/as-sold from prepared food.
- A product in both markets displays both listings and counts once in the unique-product total.
- A missing fibre value remains unknown through import, recipe calculation, UI display, and Health export eligibility.
- Updating a source record preserves internal identity or produces an explicit reviewed migration map.

## 7. Maintenance and catalogue releases

Proposed cadence: inspect branded-food source changes monthly; inspect generic source releases and errata quarterly or when announced; ship only reviewed catalogue versions with app releases. These are development-process recommendations, not automations created by this task.

Keep the preceding catalogue generation available for rollback and retain revisions needed by personal dependencies. Separate “source no longer lists it” from “record was invalid”: retirement should not erase a user's history.

Each release should contain a dated catalogue note, source/licence manifest, coverage report, changed-ID map, nutrition-change report, pack checksums, and a fixture demonstrating that overlays and historical logs remain intact after upgrade.

Initial source URLs and terms are verified only to the extent described above. In particular, the BLS downloadable documentation was protected by a browser security check during research; D04 must obtain and inspect the actual documentation and data before defining its adapter. An available download page is not proof that an importer has been validated.
