# Acquisition decision and handoff

Research date: 10 October 2026. Read shared product/data plans and D01/D02 acceptance requirements. Original agent research was staged separately and reviewed before repository integration.

## Evidence actually inspected

1. [SLV live search entry](https://soknaringsinnehall.livsmedelsverket.se/) reports dataset version 2026-07-01. [Reuse guidance](https://www.livsmedelsverket.se/livsmedel-och-innehall/naringsamne/livsmedelsdatabasen/sok-naringsinnehall/) requires named source and current version date, offers whole-database download from the search UI, and contains the unchanged-data sentence quoted in registry.
2. [SLV official OpenAPI JSON](https://dataportal.livsmedelsverket.se/livsmedel/swagger/v1/swagger.json) inspected through web reader: OpenAPI 3.0.1; API version 1.0; base `/livsmedel`; licence URL `https://creativecommons.org/licenses/by/4.0/deed.sv`. GET paths include `/api/v{version}/api-info`, paginated `/livsmedel`, and item `/livsmedel/{nummer}/naringsvarden`. Languages 1 Swedish / 2 English. Nutrient schema includes `euroFIRkod`, `varde`, `enhet`, `viktGram`, `matrisenhet`, `matrisenhetkod`, value-type/origin/method metadata and calculation. Matrix-specific values need careful mapping; do not assume every number is ordinary grams per food mass. Schema examples are documentation, not acquired food observations.
3. [MRI BLS page](https://www.mri.bund.de/de/institute/ernaehrungsverhalten/forschungsbereiche/bundeslebensmittelschluessel-bls/) confirms version 4.0 CC BY4 and DOI. [BLS download landing page](https://blsdb.de/download) confirms publisher credit. Its download action, technical documentation PDF action, and errata PDF action returned web internal errors. No security check was bypassed. [Indexed technical documentation](https://blsdb.de/bls) lists `BLS_4_0_Daten_2025_DE.xlsx`, `BLS_4_0_Components_DE_EN.xlsx` and documentation PDF. Reacquire the documentation using the current official UI; do not persist temporary download tokens. Actual workbooks and errata were not retrieved or parsed. [BLS current documentation/errata landing page](https://blsdb.de/bls) explains per-component value, provenance and reference columns and missing-value distinction; it also contains legacy 3.02 text, so do not use old sections as the 4.0 adapter specification.
4. OFF licensing and data-field documentation plus original ODbL were inspected (links in registry). No product API response or bulk snapshot downloaded.

Attempted bounded curl of SLV OpenAPI (1 MB cap, 20 s timeout) failed DNS resolution in shell. Web inspection succeeded; no saved raw JSON exists. No hashes, archived licence snapshots, imported nutrients or actual dataset sample validation can honestly be reported. Deliverables are independently authored summaries of verified pages, not complete archived terms. Acquire dated exact terms with release inputs later.

## Concrete next steps

D02 can start now against A01 synthetic fixtures. Implement fail-closed rights manifest checks and distinct research/acquisition/schema/release gates. Keep source packs and source-specific search indexes traceable; build combined-search policy only after licence review. Document licence inheritance for authored translations and derived recipe inputs.

D03: first capture current official licence metadata and dataset revision, then bounded one-record API sample. Confirm IDs, unknown/trace semantics, nutrient definitions, matrix bases, and source methods before selecting records. SLV release must await policy reconciliation below.

D04: use ordinary official download workflow to obtain main workbook, components dictionary, documentation and current errata; store SHA-256 and retrieved time. Confirm current revision and parse headers/missing markers; apply reviewed errata as a separate transformation, preserving raw input. Do not silently correct using third-party error lists. CC BY permits this path subject to source notices; release requires validated data and attribution.

D05: obtain approved bulk snapshot (not repeated API search), filter actual sales-country tags for Sweden/Germany, record selected fields and exact revision/digest. Preserve multi-market identity and separate origin/manufacturing fields. Stage unrestricted OFF derivative plus licence/attribution and reproducibility materials. Release only after combined-index/collective-vs-derivative and distribution review passes. No product images.

## Exact outstanding questions (prepared, not sent)

SLV: Your search guidance says data must not be changed, but the official API explicitly links CC BY 4.0. Does CC BY4 apply to all downloaded/API food and nutrient records, including publication of an offline subset in an app? Does the unchanged-data instruction prohibit only alteration presented as original source values, or also separately identified unit conversions, scaled portion totals, calculated recipes, translated display names/aliases and private user overlays? May immutable original values coexist with clearly labelled personal changes? Which statement governs, and which current dataset version and attribution wording should a redistributed pack use?

BLS acquisition: Which workbook revision and errata version are current on acquisition day? Does the obtained package include any additional attribution notices or excluded materials? Obtain files through supported workflow; no provider message is presently necessary merely because tools could not download them.

OFF distribution review: For independent source packs with source-specific indexes and a federated search UI, is the precise shipped structure a collective database or a derivative? What changes if a combined persisted index, identity-equivalence table, curated translations or recipes mix OFF and other inputs? Is the proposed unrestricted downloadable OFF derivative sufficient under §§4.6/4.7 for the chosen app distribution? Confirm exact contents/image licence versions if those assets are ever included. Do not interpret share-alike as a demand to publish personal diaries.

Manufacturers: Obtain written scope permitting offline redistribution, normalization, translation, attribution, version retention and corrections before acquisition for public packs. Otherwise omit.

## Permitted fallback

Proceed with explicitly synthetic fictional fixtures and original test combinations for development and demo. They must be labelled synthetic, never counted as real Swedish/German coverage, and never exported to real Health in demo mode. For production, BLS is a viable permitted generic-source candidate after acquisition/schema/quality gates; Swedish branded coverage remains unfulfilled until another source passes its gates. Reducing coverage is preferable to fabricating data or silently weakening rights gates.
