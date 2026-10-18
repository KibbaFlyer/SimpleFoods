# Agent work packages

This is the complete implementation backlog. Following the planning task, three GPT-6.1 Sol agents researched the prerequisites and produced a first foundation batch for review. See [implementation status](IMPLEMENTATION_STATUS.md) for accepted work and remaining scope; a partial package is not complete acceptance of the whole package.

Use the [product/architecture plan](PRODUCT_AND_ARCHITECTURE_PLAN.md) and [database plan](DATA_ACQUISITION_PLAN.md) as shared context. There are **29 work packages**: 19 app/architecture packages, 7 data packages, and 3 integration/release packages.

## 1. Delegation rules

Give an agent one package at a time, together with the shared plans and its completed dependencies. A package should produce one reviewable deliverable. If it exceeds a few focused implementation sessions, split it along the listed work steps before dispatch; do not quietly enlarge its scope.

An integration owner maintains the shared contract, dependency wiring, build configuration, and merge order. Feature agents own their module and focused tests. They should propose a shared-contract change to that owner before editing types used by other agents. Use distinct branches/worktrees when agents work concurrently.

All implementation agents receive these invariants:

1. The app works offline from first launch. Developer-side data acquisition is separate.
2. Catalogue data, personal overrides, and historical snapshots have separate lifecycles.
3. A catalogue update cannot overwrite an explicit user edit or rewrite an old meal.
4. Unknown nutrient values are not zero; nutrient definitions and units are explicit.
5. Food market, manufacturing country, and ingredient origin are distinct fields.
6. App language is selected inside the app; user-entered text is not automatically translated.
7. A local meal save succeeds independently of Health export, with a persistent reconciliation queue.
8. Do not double-count ingredient and meal totals, workout and active energy, or salt and sodium.
9. Do not fetch live food data during normal logging or send private meal data to public sources.
10. Do not invent food values, source rights, origin claims, or successful device validation.

Every handoff returns: implemented behavior, owned files, public-interface changes, focused verification evidence, remaining limitations, and the next dependent package that can begin. Simulated Health tests must be distinguished from physical-device tests.

## 2. Dependency order and integration milestones

These waves describe useful starting groups, not permission to ignore a package's exact dependencies.

| Wave | Work that can proceed | Exit condition |
| --- | --- | --- |
| 0 | A01 and D01 | Shared concepts frozen; source-rights decisions documented or explicitly pending for affected sources |
| 1 | A02, A03, A05, D02 | Build foundation, design specification, nutrition contract, and data-pipeline skeleton |
| 2 | A04, A06, A07; then D03/D04/D05 | Localization, separate stores, and source adapters using the same contract |
| 3 | A08 and A16 | Effective food resolution and Health read/permission behavior |
| 4 | A09, A10, A11, A12 | Safe catalogue activation, local search, diary service, recipes |
| 5 | A13, A14, A15, A17; D06 when its data dependencies pass | User-facing logging and editing; durable Health export; starter meals |
| 6 | A18, A19, D07 | Settings, recovery, and release-quality bundled data |
| 7 | Q01 and Q02, then Q03 | Integrated evidence, release readiness, and distribution handoff |

Practical parallel streams after the contract is stable: app storage/domain, interface/localization, Health integration, and public food data. Limit simultaneous edits to shared project files. Extra agents are helpful only when their inputs and ownership are clear.

Recommended milestones:

- **M1 — Offline vertical slice:** launch → search a small fixture catalogue → log a portion → see a saved meal after restart.
- **M2 — Personal library durability:** customize a food → save a recipe → update the catalogue → verify personal edits and history.
- **M3 — Health round trip:** export → edit → delete → restart/retry, with no duplicates and honest permission states.
- **M4 — Complete product beta:** real Swedish/German catalogue, all three languages, accessible screens, backup and restore.
- **M5 — Release candidate:** all acceptance scenarios pass on the supported devices; source notices and review material are complete.

## 3. Application and architecture packages

### A01 — Freeze shared contracts and implementation decisions

**Depends on:** No code dependencies; coordinate with D01 on source constraints.

**Owns:** Architecture decisions, conceptual schema, repository/service specifications, common fixture definitions. Only the integration owner later changes these without coordination.

**Work:** Set deployment target and module boundaries. Define stable IDs, revisions, nutrient semantics, portion basis, override operations, recipe components, log snapshots, time zones, and Health ledger states. Specify errors and change notifications. Decide backup policy and the carbohydrate-mapping investigation. Write examples of normal, unknown, cleared, retired, and conflict states.

**Deliverables:** Versioned contract document, field/unit crosswalk, dependency graph, fixture catalogue v1/v2, and a list of decisions needing source or device evidence.

**Acceptance:** Another agent can implement a repository or screen without inventing its own meal/food structure. An explicit customization-survival example and an idempotent Health-edit example have agreed expected outcomes. Unresolved source rights are isolated from unaffected work.

### A02 — Native project, modules, and build foundation

**Depends on:** A01.

**Owns:** App target, package manifests, project configuration, dependency composition, shared build/CI setup.

**Work:** Create the SwiftUI iPhone project, module boundaries, pinned storage dependency, simulator build configuration, resource packaging, and test targets. Introduce injectable clock, time-zone, persistence, and Health service boundaries. Add a preview/demo data path that cannot write to real Health.

**Deliverables:** Buildable app shell, three-tab navigation placeholders, reproducible build instructions, and dependency lockfile.

**Acceptance:** Clean checkout builds for the minimum target and current supported SDK. Demo mode is isolated. No API key, account, network response, or real Health permission is required to launch.

### A03 — Design system and screen specifications

**Depends on:** A01.

**Owns:** Design tokens, shared UI components, screen layouts, accessibility conventions.

**Work:** Specify color, typography, spacing, icons, input controls, meal cards, country badges, nutrient summaries, and validation states. Design Today, meal composer, search, detail, recipe editor, and Settings using realistic long Swedish/German labels. Components can be integrated into the app after A02.

**Deliverables:** Annotated layouts and reusable components with light/dark and large-text previews.

**Acceptance:** Meal type and sync status remain understandable without color. Country badges contain text. Quantity and Save controls survive large text and long names. The primary logging flow has a clear single next action at each step.

### A04 — In-app localization and formatting infrastructure

**Depends on:** A02; use A03's naming conventions.

**Owns:** Localization module, language preference, shared String Catalog conventions, formatters.

**Work:** Support sv, en, and de with an explicit persisted app language. Localize strings, plural forms, accessibility text, nutrient/unit labels, dates, and numeric input. Define fallback for untranslated food names and preserve official brand names. Provide a formatter/parser independent of phone language.

**Deliverables:** Language selection service, initial three-language resources, localization checklist for feature agents.

**Acceptance:** Switching language updates visible app-owned UI without restart or lost draft. Decimal comma/point input follows a documented rule and rejects ambiguous input. Device language does not override a saved choice. System-dialog limitations are documented.

### A05 — Nutrition calculation and nutrient definitions

**Depends on:** A01.

**Owns:** Pure nutrition/domain calculation module and golden numeric fixtures.

**Work:** Implement basis scaling, mass/volume conversion with documented density, portion equivalents, recipe yield/servings, salt/sodium conversion, precision, and unknown/derived states. Implement the reviewed carbohydrate crosswalk without silently substituting definitions. Define per-nutrient completeness and export eligibility.

**Deliverables:** Deterministic calculator, supported conversion table, source/Health nutrient-mapping specification, golden test cases.

**Acceptance:** Synthetic 75 g at 200 kcal/100 g yields 150 kcal; 1 g salt yields 400 mg sodium; missing density blocks an unsupported conversion; unknown fibre makes fibre incomplete; rounding does not accumulate per ingredient. Carbohydrate export cannot ship on an unresolved semantic assumption.

### A06 — Read-only catalogue repository

**Depends on:** A02 and A01's schema.

**Owns:** Catalogue reader, manifests, source identity and revision lookup.

**Work:** Load immutable source packs, localized descriptions, profiles, portions, recipe records, provenance, and archived revisions. Validate reader/schema compatibility. Expose the same contract for fixture and production packs.

**Deliverables:** Catalogue repository, first-load behavior, source-attribution access, dependency lookup.

**Acceptance:** A valid bundled pack is usable in airplane mode. Invalid/incompatible packs fail with a recoverable state. The catalogue API has no feature-level mutation path. Same-named foods from different sources remain distinguishable.

### A07 — User database, migrations, and transaction boundaries

**Depends on:** A02 and A01.

**Owns:** Private database migrations, personal entities, meal snapshots, outbox/ledger persistence.

**Work:** Store custom foods, overrides, favorites, recipe pins, settings, immutable log revisions, and Health intent. Provide serialized writes and atomic save-plus-outbox transactions. Apply file protection to database and sidecars. Define deletion/tombstone retention and migration failure behavior.

**Deliverables:** Repositories, migration fixtures, transaction API, documented protected storage locations.

**Acceptance:** Simulated failure cannot save half a meal or lose its export intent. Relaunch preserves drafts and logs. Migrations retain custom IDs and snapshots. A catalogue import cannot replace this database.

### A08 — Effective food resolution and personal override behavior

**Depends on:** A05, A06, A07.

**Owns:** Resolver, override commands, reset behavior, conflict detection.

**Work:** Implement inherit/set/clear, per-language name edits, nutrient-basis grouping, stable recipe-component operations, and source-revision comparisons. Support independent personal variations and retired-source dependencies. Return effective values plus field provenance.

**Deliverables:** Resolver and editing service, changed-source review model, customization regression suite.

**Acceptance:** All update examples in architecture section 6 pass. Explicit clears survive updates. Reset inherits the newest base. Removed/reordered recipe components never cause an override to affect the wrong component. User edits win over catalogue data.

### A09 — Catalogue activation, upgrade, and recovery

**Depends on:** A06, A07, A08.

**Owns:** Catalogue generation manager, compatibility checks, rollback state, cache-generation protocol.

**Work:** Stage and validate replacement packs, preserve personal dependencies, coordinate search-index activation, and atomically select a generation. Pin generation during save operations. Handle corrupt packs, interrupted activation, low storage, skipped versions, retired IDs, and index rebuild.

**Deliverables:** Versioned activation process and upgrade/recovery fixtures. Work with A10 on the agreed index interface.

**Acceptance:** Forced failure at each activation stage leaves either the prior valid catalogue or the new valid catalogue usable. Personal edits survive. Old logs remain byte-for-byte nutritionally equivalent. Rolling back public data does not roll back new diary entries.

### A10 — Offline search and country filtering

**Depends on:** A04, A06, A08; use the A09 generation contract.

**Owns:** Search index, query normalization, ranking, filters, change invalidation.

**Work:** Index effective names, aliases, brands, categories, barcodes, market membership, and preparation states. Support Swedish/German characters and transliterations. Include private foods and renamed overrides. Implement Sweden/Germany/All and verified-origin filters with distinct labels.

**Deliverables:** Search service, reproducible ranking fixtures, generation-aware index rebuild.

**Acceptance:** Falukorv, Bratwurst, flour/vetemjöl/Mehl, and brand+product queries find expected fixtures. A personal rename is immediately searchable. A multi-market item appears once with both badges. Unknown origin is never synthesized. Measure the agreed latency budget with D07's final pack.

### A11 — Meal drafts, suggested category, and diary commands

**Depends on:** A05, A07, A08.

**Owns:** Meal composer state and save/edit/duplicate/delete domain service.

**Work:** Implement selected-time suggestions, user override, custom windows, quantity validation, draft persistence, immutable snapshots, event revisions, time-zone/local-date policy, and export intent creation. Separate an occurrence edit from food-library editing.

**Deliverables:** Meal command service and representative temporal/snapshot fixtures.

**Acceptance:** Boundary times suggest the specified category. Manual category choices survive time edits. Backdated meals use eating time, not current save time. A catalogue change during save cannot mix revisions. An old meal uses its snapshot unless explicitly refreshed. DST and travel behavior matches the contract.

### A12 — Recipes and saved-meal domain service

**Depends on:** A05, A07, A08.

**Owns:** Recipe/saved-meal creation, component pinning, yields, portions, refresh review.

**Work:** Support original recipes, customized starter recipes, reusable combinations, servings, cooked yields, component replacement, and explicit refresh from updated foods. Prohibit nested recipes and cycles in the first release. Preserve dependencies when source items retire.

**Deliverables:** Reusable-meal service, validation rules, tested example meals.

**Acceptance:** One saved recipe can be logged repeatedly at different portions without altering its definition. Component revisions stay pinned until refreshed. Missing cooked yield prevents invented weight-based nutrition. Resetting a customization restores current inherited behavior without rewriting old logs.

### A13 — Food search, details, and meal composer screens

**Depends on:** A03, A04, A10, A11.

**Owns:** Add-meal flow, search-results UI, food detail, portion input.

**Work:** Connect local search and filters, listing badges, source/preparation labels, recent/favorite choices, quantity editing, selected time/type, running totals, and local save. Handle empty search, unknown nutrition, invalid portion, draft recovery, and errors without losing edits.

**Deliverables:** Complete accessible meal-entry screens in three languages.

**Acceptance:** A tester can add a branded sausage and potatoes, adjust grams, choose dinner, and save offline. Countries are explained without opening a help page. Save remains available at large text sizes. Incomplete totals are visibly qualified.

### A14 — Today, history, and energy presentation

**Depends on:** A03, A04, A11, A16.

**Owns:** Today/history UI, day navigation, macro summary, energy cards, meal actions.

**Work:** Display four categories, multiple events, recorded totals, Health energy components, freshness, and incomplete/no-data states. Support date changes, meal edit/delete/duplicate, and first-use guidance.

**Deliverables:** Integrated diary and history views.

**Acceptance:** A saved meal appears correctly after restart and date navigation. No readable Health energy appears as unavailable, not zero. Active-only data is not presented as total expenditure. Today's values say “so far.” Health delay never blocks diary use.

### A15 — My foods, ingredient editing, and recipe editor screens

**Depends on:** A03, A04, A08, A12.

**Owns:** Personal library, custom ingredient/product forms, recipe builder, customization comparison UI.

**Work:** Provide create from scratch, customize, create variation, field reset, full reset, component editing, saved combinations, and pinned-component refresh. Show current source versus personal values clearly. Support safe hiding/removal when items are referenced.

**Deliverables:** Accessible personal-food and recipe flows with localized validation.

**Acceptance:** A user can correct nutrition on a base product, see its customized status, reset one field, create an independent variation, and save a full meal. Discarding edits changes nothing. A referenced item cannot be destructively removed without preserving its dependencies/history.

### A16 — Health availability, authorization, and energy reads

**Depends on:** A02, A04, A07.

**Owns:** Health gateway availability/authorization and energy-reading adapter.

**Work:** Configure capability and usage descriptions through A02's owner. Implement optional permission flow, active/basal statistics, matching calendar intervals, refresh, freshness, locked-device deferral, and availability-gated limited-history support. Provide deterministic fakes for UI work.

**Deliverables:** Health read service, Settings status model, real-device verification instructions and results when available.

**Acceptance:** Read denial is not falsely claimed from empty results. Partial data remains partial. No workout double-counting. Multiple sources, late updates, day boundaries, no Watch data, and access revocation are checked on a real device before release. Any hardware limitation is reported rather than marked passed.

### A17 — Reliable Health nutrition export

**Depends on:** A05, A07, A11, A16.

**Owns:** Outbox worker, nutrient export mapping, sync identities/versions, cleanup and reconciliation.

**Work:** Map complete meal totals to authorized Health types. Implement stable per-meal/per-nutrient identity, monotonic versions, edit replacement, obsolete-nutrient removal, deletion, retry, superseded-job handling, historical range export, and partial status. Serialize conflicting operations for one meal. Reconcile restoration without blind replay.

**Deliverables:** Export adapter, state-transition specification, failure-injection tests, physical-device evidence.

**Acceptance:** Repeated save/retry produces one current sample per nutrient; 500→600 kcal edit replaces intake rather than totaling 1,100. A timestamp edit moves the sample. Deletion removes only app-owned data. Revocation leaves an honest pending/attention state. Known→unknown removes the former value where permitted. Crash/restart after every stage converges without duplicates.

**Split if needed:** Implement create/idempotency first, edit/delete reconciliation second, and restore/backfill handling third. Keep one owner of the ledger protocol.

### A18 — Onboarding and Settings

**Depends on:** A03, A04, A07, A16, A17.

**Owns:** Initial language/market choice, meal windows, units, Health settings, catalogue/source information.

**Work:** Offer Swedish/English/German independently of system language; configure preferred market and meal windows. Explain optional Health reading/writing separately. Expose export status, future-only default, deliberate historical export, catalogue version, attributions, privacy information, and recovery actions supplied by A19.

**Deliverables:** Complete settings/onboarding flows and localized explanatory copy.

**Acceptance:** Onboarding can finish without Health access. Changing language does not change preferred market. Export-off semantics are clear. Attribution is accessible offline. Overlapping meal windows are rejected with a useful explanation.

### A19 — Local backup, restore, and scoped deletion

**Depends on:** A07, A08, A09, A17; coordinate UI integration with A18.

**Owns:** Backup format, encryption integration, import validation, restore reconciliation, deletion orchestration.

**Work:** Implement the agreed protected local backup route using a reviewed encryption design, schema/integrity validation, and temporary-file cleanup. Preserve private dependencies, IDs, snapshots, and Health ledger. Restore into an empty diary, detect repeated imports, and separate local erase from exported-Health deletion. Validate automatic OS-backup exclusions/inclusions against the agreed policy.

**Deliverables:** Documented backup format/version, restore service, recovery instructions, deletion previews.

**Acceptance:** Export/restore preserves totals and customizations. Wrong password, corrupt file, unsupported version, and interruption leave existing data intact. Import does not duplicate Health records. Reset never claims blocked Health deletion succeeded. Uninstall/backup limitations are disclosed accurately.

**Split if needed:** Backup contract and encryption review; export/restore implementation; deletion/Health reconciliation. Treat these as sequential sub-deliverables with focused review.

## 4. Public food-data packages

### D01 — Source permissions, attribution, and provenance policy

**Depends on:** None; coordinate with A01.

**Owns:** Source registry, licence snapshots, reuse decisions, public/private data boundary.

**Work:** Review the exact source versions and terms listed in the database plan. Resolve Livsmedelsverket's unchanged-data wording for the intended transformations and private overlays. Define Open Food Facts distribution/attribution obligations and whether source combinations are permitted. Record manufacturer-feed rights and recipe authorship rules.

**Deliverables:** Source-by-source allowed-use matrix, required notices, unresolved questions, and permitted fallback sources.

**Acceptance:** Every source has an explicit status before release. Physical separation is not treated as automatic licence compliance. Personal records never enter a public release. If external clarification is needed, prepare the precise question; do not send messages without authorization.

### D02 — Data preparation framework and package contract

**Depends on:** A01, D01.

**Owns:** Developer-side pipeline, common normalizer/validator, source adapter contract, build manifests.

**Work:** Define pinned tooling and acquisition/cache layout. Preserve immutable inputs and checksums. Implement shared field crosswalks, identifiers, error quarantine, provenance, unit normalization, deterministic packaging, and diff reports. Coordinate the pack format with A06.

**Deliverables:** Reproducible pipeline with small fixtures and adapter instructions for D03–D05.

**Acceptance:** Same inputs/configuration produce logically identical records and manifests. Unknown nutrients survive intact. Malformed units or broken references fail visibly. No private user store is an input.

### D03 — Swedish generic-food adapter and curation

**Depends on:** D02; D01 permission decision for the selected source.

**Owns:** Livsmedelsverket acquisition adapter, Swedish category selection, Swedish source mapping.

**Work:** Obtain the approved download/API snapshot; inspect actual schema, version, units, method qualifiers, and portion information. Select Swedish staples and prepared references. Preserve raw/cooked distinctions and original values. Produce missing-coverage and translation queues.

**Deliverables:** Versioned Swedish pack inputs, provenance, nutrient mapping, category report, reproducible adapter fixtures.

**Acceptance:** Representative flour, vegetable, fruit, fish, dairy, and generic sausage records trace to real source IDs. No inferred manufacturer association. Transformations comply with D01's decision. Counts represent usable records, not every raw row.

### D04 — German generic-food adapter and curation

**Depends on:** D02; D01 permission decision.

**Owns:** BLS 4.0 adapter, German category selection, nutrient/food-code mapping.

**Work:** Obtain actual release files, documentation, and errata. Inspect definitions and choose relevant foods. Handle food-code changes with explicit mappings. Retain preparation state and distinguish flour types, fat variants, and different sausages. Prepare source-language and translation information.

**Deliverables:** German pack inputs, documentation-derived mapping, attribution, curation report, adapter fixtures.

**Acceptance:** Selected records trace to the actual release. No assumption that older licence models or older codes still apply. Reference dishes are labelled as references. German data does not silently overwrite a similar Swedish food.

### D05 — Branded Sweden/Germany product adapter

**Depends on:** D02; D01 permission decision.

**Owns:** Open Food Facts bulk filtering, product identity and quality review, permitted manufacturer supplementation.

**Work:** Process a dated bulk snapshot; filter by sales countries; preserve brand, barcode, variant, basis, nutrition, source dates, and separate origin fields. Quarantine implausible/incomplete records, prioritize high-value categories, and review a representative product basket. Retain reformulation history.

**Deliverables:** Curated branded inputs, inclusion/exclusion report, per-market coverage, identity-conflict queue, notices.

**Acceptance:** Real branded sausage and fries records are present when validated evidence exists. Multi-market items have one identity. Barcode prefixes do not become country claims. Per-serving values are never mistaken for per-100-g values. Incomplete records are honestly labelled or excluded.

### D06 — Original starter meals, translations, and search aliases

**Depends on:** D02, D03, D04; use A05's agreed calculations and A12's recipe contract.

**Owns:** Authored Swedish/German meal templates, curated content translations, alias dataset.

**Work:** Prepare the proposed 40 Swedish and 20 German templates as quality permits, with weighed ingredients, source references, servings/yield, and original descriptions. Translate curated generic names and descriptors. Build culturally appropriate cross-language aliases without collapsing distinct foods.

**Deliverables:** Recipe/template pack, translation coverage report, reviewed alias/query corpus, authorship record.

**Acceptance:** Templates are editable and calculate from explicit inputs. A native-language reviewer checks important food terms. No copied recipe prose or guessed branded nutrition. Official product names remain recognizable. Missing yield is not replaced with an invented weight.

### D07 — Catalogue quality review and release packaging

**Depends on:** D03, D04, D05, D06, A06, A09, A10.

**Owns:** Final pack assembly, validation/coverage report, release diff, public database distribution materials.

**Work:** Run schema/nutrition/provenance checks, human review, search-query evaluation, size measurement, and source-notice generation. Build country packs and the bundled index. Test actual activation against a populated private fixture database. Document shortfalls against target coverage.

**Deliverables:** Candidate catalogue generation, integrity manifest, licence artifacts, coverage/quality report, upgrade fixture.

**Acceptance:** No unresolved critical errors or unapproved source rights. All starter recipes resolve. Search and size budgets are measured. Every shipped field requiring attribution is traceable. Personal overrides and historical logs survive replacing the actual bundled catalogue.

## 5. Integration and release packages

### Q01 — End-to-end integration and failure scenarios

**Depends on:** A02–A19 and D07 completed for the candidate build.

**Owns:** Integrated regression scenarios, cross-module defect triage, milestone evidence.

**Work:** Run the first-install offline journey and the complete customization/update/Health round trip. Inject failures during local saves, pack activation, Health export, and restore. Verify time boundaries, unknown nutrients, duplicate operations, retired foods, and repeated imports. Coordinate fixes with owning agents.

**Deliverables:** Reproducible scenario suite, failure evidence, resolved blocker list, candidate-build identifier.

**Acceptance:** All critical scenarios pass on the integrated build, not merely in isolated mocks. Real-device Health evidence is present. No known data-loss or duplicate-export defect remains. Re-run only affected checks after fixes, then the agreed release smoke test.

### Q02 — Accessibility, privacy, performance, and language audit

**Depends on:** Completed user-facing A packages and D07; can run alongside Q01.

**Owns:** Cross-language/accessibility audit, storage/privacy inspection, measured device budgets.

**Work:** Test Swedish/English/German on mismatched phone languages, large text, VoiceOver, dark mode, contrast, and reduced motion. Measure launch, search, save, and catalogue size. Inspect private storage, temporary files, logs, backup policy, third-party dependencies, and network behavior.

**Deliverables:** Auditable findings with severity, screenshots/device conditions, measurements, and confirmation of privacy disclosures.

**Acceptance:** No blocking accessibility or localization issue. No undisclosed private-data upload or logs. Backup behavior matches the user-facing explanation. Performance targets pass or have an explicit reviewed tradeoff. Apple-controlled language limitations are described accurately.

### Q03 — Release documentation and distribution handoff

**Depends on:** Q01 and Q02 passing; final D01 licence review.

**Owns:** Release checklist, privacy/attribution text, store materials, device-support notes, review instructions.

**Work:** Prepare localized app description/screenshots, optional Health explanations, data-source notices, catalogue version notes, and review steps. Verify current Apple requirements against the final implementation and distribution target. Prepare TestFlight/App Store submission artifacts without assuming publication authorization.

**Deliverables:** Release-ready build identification, completed acceptance matrix, review packet, known limitations, and maintenance runbook.

**Acceptance:** Claims match implemented behavior and actual catalogue coverage. Health permissions are justified, source rights are complete, support/recovery instructions exist, and a fresh device can follow the review steps. Any upload/submission/public release is a separate explicitly authorized action.

## 6. Reusable agent handoff prompt

Copy the following prose, replacing the bracketed fields. Include the exact package text and the dependency handoffs; a package number alone is not sufficient context.

> Implement work package [ID and title] for the native iOS meal tracker. Read the product/architecture plan and database plan, then the attached package brief and completed dependency reports. Own [module/files] and deliver only this package's scope. Follow the frozen contracts and ten shared invariants. Do not change another agent's module or shared schema without coordinating with the integration owner. Implement the listed behavior and run the focused acceptance checks. Report changed files, interface changes, verification evidence, and unresolved limitations. Do not claim real-device Health tests passed unless actually performed. Use synthetic or approved public fixtures, never invented production nutrition. Do not publish the app, contact data providers, or upload private data as part of this assignment.

For a data-only package, replace “implement” with “prepare and validate the data pipeline/content” and attach the relevant source-rights decision. For Q packages, attach the candidate build and all outstanding limitations. Keep dependency reports short enough that a smaller agent can locate the contract and its own task without reading unrelated implementation history.
