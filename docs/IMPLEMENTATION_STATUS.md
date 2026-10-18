# Implementation and integration record

Started 10 October 2026 after the user authorized GPT-6.1 Sol agents and implementation following review.

Agent work is staged in ignored, isolated candidate directories. The integration owner reads the proposed changes, checks important claims against primary evidence, requests corrections, and copies only reviewed artifacts into the repository. An accepted foundation is not a completed production app.

## Reviewed research

| Assignment | Decision | Important evidence and remaining gates |
| --- | --- | --- |
| A01 — shared contracts | Accepted v0.1 domain/wire baseline | Separate catalogue, overrides, and snapshots; precise decimal strings; stable identity/revisions; concrete v1/v2 synthetic fixtures. Corrected fixture source IDs to match registry. |
| D01 — source rights | Accepted research with unresolved release gates | Parent verified official SLV API CC BY metadata; conflicting website guidance remains documented. BLS licence confirmed but actual workbook acquisition/schema validation pending. OFF distribution structure still needs review. |
| HealthKit spike for A05/A16/A17/A19 | Accepted specification and test requirements | Parent inspected SDK availability and sync metadata. Limited-history introspection is availability-gated at iOS 27 in installed SDK. Same-version retries require device evidence. Carbohydrate mapping remains gated. No Health data was read or written. |

See [contracts](contracts/SHARED_CONTRACTS.md), [source registry](research/SOURCE_REGISTRY.md), and [Health decisions](research/HEALTHKIT_DECISIONS.md).

## Review policies settled for the foundation

- Use synthetic records only for development; they cannot be presented as verified production nutrition or exported to real Health.
- Freeze portable decimal input at at most 12 integer digits and 9 fractional digits, with explicit errors outside the supported range. Arithmetic policy and evidence belong to A05.
- Persistence now pins GRDB 7.11.1 and checks in the dependency lockfile. The Foundation nutrition core remains independent of GRDB.
- Keep production Health writing absent from the shell. The research defines later implementation requirements and does not substitute for device tests.
- Retain export cleanup obligations even while export is off, but do not execute them without a clearly expressed cleanup choice. Future Settings must distinguish stopping new writes from removing existing Health data.
- Treat restored Health intents as requiring reconciliation. A backup cannot prove that no later edit or deletion occurred in Health.
- Sugar/fibre and carbohydrate export remain subject to the documented semantic mapping policy. Valid independent energy/protein/fat/sodium mappings can proceed in a later adapter.

## Accepted implementation batch

Three GPT-6.1 Sol agents worked in separate staging directories, with the integration owner reviewing and copying accepted files. A second agent independently reviewed the nutrition and catalogue code. No agent changed the repository directly; the owner performed integration after corrections.

| Package | Accepted behavior | Boundaries |
| --- | --- | --- |
| A02 and a small part of A03 | Native SwiftUI iPhone project, iOS 18 deployment target, local Foundation package, deterministic project generator, privacy manifest for app-only UserDefaults, Today/Foods/Settings preview, persistent explicit sv/en/de preference | Preview has no logging or catalogue; design system, accessibility acceptance, app icon, production composition and signing remain pending. Language copy uses a small explicit provider until A04. |
| A05 foundation | Decimal-string values; validated nutrient units/statuses; mass/volume/portion conversion with evidence; recipe serving/yield calculation; complete/incomplete/trace/estimated totals; declared energy; direct sodium or one salt-derived fallback; pure semantic export checks | Fixture envelope is for development, not a production reader. Recipe helper takes totals, not persisted recipe definitions. Full source eligibility, overlays, snapshots and Health transport are absent. |
| D02 scaffold | Standard-library Python CLI; explicit public input allowlist; strict leaf-food schema; reviewed-source gates; reproducible JSON/SQLite; manifest, attribution and diff; immutable generations/revisions; active-only search indexes and separate market memberships | No real-source adapters, recipe schema, app reader or safe revision garbage collection. All production source gates remain closed. Four synthetic leaf foods are development fixtures only. |

Accepted review corrections include estimated conversion propagation, saturated-fat parent consistency, derived evidence resolution, strict tagged nutrient shapes, explicit null encoding, lowercase UUID encoding, optional portion labels, unknown-field rejection at public ingestion, immutable provenance/evidence, and preservation of every prior revision during scaffold updates. V2 retains both the replaced sausage r1 and retired potato r1.

The pure Health eligibility helper checks numerical completeness and semantics only. It does **not** approve a source or a fixture for real Health export. A17 must independently verify source eligibility, user choices, durable identities and reconciliation.

## First-batch verification

Run `python3 tools/check_foundation.py` from the repository root to reproduce the combined suites and interoperability check. It checks the two shared fixture copies, runs both suites, writes Swift-encoded fixture data to a temporary directory, validates it with Python, and compares normalized meaning.

| Check | Result |
| --- | --- |
| Python catalogue suite from integrated repository | 34 tests passed |
| Swift Foundation suite from integrated repository | 18 XCTest cases passed, zero failures |
| Swift → Python wire contract | Passed strict validation and normalized semantic comparison |
| Xcode project regeneration | Identical bytes; project, scheme and privacy manifest parsed |
| Debug generic iOS Simulator build | Passed for integrated app/core |
| Release generic iOS device build, signing disabled | Passed for integrated app/core |
| Simulator launch / initial Swedish screen | Preview launched on iPhone 18 Pro / iOS 27; initial screen visually inspected |

Environment: Xcode 27.0, Swift 6.4, macOS arm64, iOS 27 SDK/runtime; deployment target remains iOS 18. Both builds emitted only the expected skipped App Intents metadata extraction warning because the preview has no App Intents dependency. The initial Xcode licence/setup block was resolved outside agent actions; no agent accepted or bypassed an agreement. Compilation for a deployment target is not runtime testing on that OS. Physical-device testing, iOS 18 runtime coverage, interactive language-change/relaunch tests, VoiceOver, large text and all Health permissions/reconciliation tests remain pending. Native UI automation could not bind the Simulator application, so no interactive UI verification is claimed.

## Second integration batch — 11 October 2026

Three GPT-6.1 Sol agents implemented bounded candidates for storage, interface, Open Food Facts and Health reads. The integration owner reviewed code, compiled the full app and requested corrections; the storage agent independently reviewed the other candidates. Staging is ignored by Git. Source and personal databases remain separate, with complete iOS file protection and backup exclusion on dedicated directories. Device lock behavior still needs physical-device validation.

| Area | Accepted implementation | Limits |
| --- | --- | --- |
| Catalogue reader | Read-only bundled SQLite; manifest/file/row checksum and identity checks; localized search, market filters, barcode matching, retained revisions | Bundled pack is four fictional development records, visibly labeled; production pack activation remains pending. |
| Diary | Transactional events/history/operation receipts/change sequence/disabled export intents; immutable food and nutrition snapshots; add/edit/duplicate/delete; positive g/ml quantities; explicit date/zone and automatic/manual meal type; protected draft recovery including invalid raw input | Saved recipes, portions UI, conflict resolution UI and Health exports remain pending. |
| Personal library | Separate per-language inherit/set/clear operations; atomic complete nutrition overrides; source updates retain overrides; incompatible source basis flags review; custom ingredients/products with revisions, history and hiding; v1 migration preserves diary | Nutrition override freezes a whole coherent profile. Editing one nutrient retains other profile values until reset; no automatic rebasing of that profile. Recipe definitions remain pending. |
| iOS interface/localization | Native SwiftUI Today/Foods/Settings, resource-based sv/en/de in-app preference, localized numeric input, errors and permission purposes; camera EAN-8/EAN-13 and manual barcode fallback | OS permission sheets follow system language. Accessibility, large text, long German copy and physical camera acceptance remain open. |
| Open Food Facts | Explicit barcode lookup, durable offline cache with immutable source revisions; explicit refresh/sync, remote revision/modified comparisons, attempt/success timestamps, community-data attribution; country-filtered discovery; overlays resolved after updates | Country labels mean listed sales markets, not manufacturing origin. Discovery is bounded and cannot promise a complete country mirror. Remote records remain community/unverified; no redistribution approval is implied. |
| Health energy | Explicit Connect; read active and resting cumulative energy separately; daily Gregorian/time-zone windows, today so far; missing data stays unknown; matching coverage totals; stale and cancellation handling; memory-only values | Read-only. Historical access coverage remains unknown. No nutrition writes, background reads, or Health disk cache. Physical-device permission/source behavior remains open. |

Review corrections include protected SQLite draft recovery instead of UserDefaults, matching OFF snapshot/provenance recovery, preserved meal zones, new component identities for duplicates, renamed-food search, no silent g/ml basis reinterpretation, explicit nutrient clears blocking salt-derived sodium fallback, cross-day stale Health rejection, strict OFF metadata/basis/modifier handling and server Retry-After backoff. No Health data was read or written during development.

The user explicitly requested discovery of new Swedish and German OFF products as well as refreshing known products. Each imported source remains separate from personal changes; a source update does not mutate old diary snapshots. Discovery checkpoint metadata describes completed bounded batches, not full-market freshness. See the [OFF implementation notes](research/OFF_SYNC_IMPLEMENTATION.md) for pagination and API limitations.

## Remaining bounded assignments

1. **D03/D04 production Swedish/German food adapters and D05 release rights** — acquire real versioned inputs, verify terms and actual schemas, build a release catalogue and country/brand coverage checks. Fictional bundled foods must remain development-only.
2. **Saved recipes and full meals** — persist ingredient revisions, yields/servings and personal recipe edits, then reuse a saved meal with new diary identities. The calculation helper alone does not satisfy this feature.
3. **A17 Health nutrition writing and reconciliation** — implement durable export ledger, eligibility, explicit user controls and cleanup, with physical-device permission/retry evidence. Existing disabled intents are not an exporter.
4. **Catalogue generation activation and broader migration/recovery** — safely switch production packs while retaining personal overlays and referenced historical revisions.
5. **Device and release acceptance** — minimum-iOS runtime, barcode camera, offline/relaunch/edit flows, VoiceOver/large text, Health locks/permissions/source overlap, signing, privacy review and app icon.

The full dependency map and acceptance criteria remain in [agent work packages](AGENT_WORK_PACKAGES.md). This batch implements the local diary foundation; it is not a production-ready app.

## Second-batch verification

- Integrated suites: **70 Swift XCTest cases and 34 Python tests passed**; shared fixture consistency and Swift → Python strict wire comparison passed.
- The mocked OFF → personal overlay → diary → source refresh → restart test preserves custom nutrition/name and historical snapshots while unedited names/markets inherit the new source.
- OFF tests cover local-first/offline cache, metadata/basis/modifier validation, immutable revisions, partial failure/backoff, country discovery, fair budgets, checkpoint retries, page-size changes and pagination progress.
- Health tests cover explicit connection, missing versus real zero, coverage-compatible totals, DST, cancellation races and stale values confined to the selected day/zone.
- Project generation is byte-reproducible; project, privacy and entitlement plists parse. sv/en/de resource keys have parity.
- Final Debug Simulator and Release iOS device builds pass with signing disabled. Only expected skipped App Intents metadata extraction warnings remain.
- The app launched in iPhone 18 Pro / iOS 27 Simulator; initial Swedish Today screen visually inspected. Native automation could not bind Simulator, so no interactive UI-flow acceptance is claimed.

No live OFF products were imported by the tests. Camera scanning, permission sheets, Health values and file behavior while locked require physical-device validation. Compilation against iOS 18 does not establish iOS 18 runtime acceptance. Full production catalogue, saved recipes and Health nutrition export remain open as listed above.
