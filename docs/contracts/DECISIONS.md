# A01 review decisions

Contract v0.1 was reviewed and accepted for the foundation implementation. Research was staged separately before integration; open gates below remain explicit.

## Accept before implementation

- iOS 18 minimum deployment target, native modular Swift/SwiftUI. Integration review deferred GRDB selection to A06/A07; the shell/core have no external dependency. Upstream master was inspected but is not pinned or recommended as a dependency. [Primary Package.swift](https://raw.githubusercontent.com/groue/GRDB.swift/master/Package.swift).
- JSON tagged IDs and tri-state operations; decimal strings (12 integer/9 fractional digits), revision-counter strings, UUID generation IDs, separate immutable revision domains. A05 golden cases now validate the decimal policy: Foundation Decimal, no intermediate display rounding, final half-even storage rounding to nine places. Recurring division uses Decimal precision; add/multiply precision loss is rejected.
- Per-nutrient overrides carry accepted basis and a complete last-accepted profile. Incompatible basis drift freezes that profile with review status; no mixed g/ml nutrient arithmetic.
- Personal recipe component pins include full effective profiles; stable component IDs; no live nested recipes. Saved meals expand selected recipes to pinned leaf snapshots.
- Historical quantity edits scale old snapshot; explicit refresh creates a new revision. Diary save/outbox intent atomic; catalogue generation lease prevents mixed-source saves.
- Strict wall-time ambiguity handling and original-zone diary dates. Explicit comparison-zone interval for Health; mixed-zone day flagged approximate.
- Health desired/observed states separate, payload immutable per sync version, monotonic high-water mark, restore reconciliationRequired. Carbohydrate export blocked until source-to-Health definition reviewed. Health sibling confirmed these conclusions.

## Open gates and risky original-plan tensions

1. Minimum-OS runtime coverage remains pending. A06/A07 must verify the selected GRDB stable tag, toolchain, migrations and native SQLite features. Foundation build results are recorded separately in implementation status. No Xcode license acceptance is authorized by this document.
2. Carbohydrate needs exact EU/source definitions and Health mapping; EU includes polyols and excludes fibre, so adding fibre alone is not an approved universal mapping. Per-nutrient eligibility stays independent from completeness.
3. Clear versus unknown must stay distinct in the overlay even though both resolve to unavailable nutrient amount. Required fields cannot always clear. Grouped basis conflicts make single-field reset a review operation.
4. All pinned dependencies/old generations cannot be retained regardless of rights forever. D01 decides legal retention; revocation/removal is a separate reviewed migration. No automatic licence compatibility from file separation.
5. Integration review settled export-off behavior: retain cleanup obligations but execute only following an explicit cleanup choice. Health/Settings must implement and verify that distinction.
6. Backup defaults proposed: protected private files excluded from automatic backup and explicit encrypted local archive. A19 must verify Apple requirements, OS behavior, destination privacy and reviewed encryption/KDF design. This spec does not claim verified compliance or choose cryptography.
7. Approximate nutrient export still needs policy review. The pure A05 gate withholds estimates, trace/unknown values, carbohydrate and standalone sugar/fibre. Exact salt→sodium fallback may be semantically eligible; this is not authorization to export synthetic fixtures or proof of a working Health adapter.
8. Index fallback must remain available while activation/overlay catch-up runs; otherwise “personal rename immediately searchable” and atomic activation can conflict.

## Evidence and limits

Read all three repository planning documents and A01/A05/A12/A17/A19 package requirements. Primary GRDB manifest inspected through web on 10 October 2026; [repository licence location](https://github.com/groue/GRDB.swift/blob/master/LICENSE). [Apple Calendar interval API](https://developer.apple.com/documentation/foundation/calendar/dateinterval(of:for:)) located; web page required JavaScript, so implementation behavior is an A11 gate, not asserted from inaccessible API text. DST fixture expectations require platform validation. Health semantics were researched independently; defer to the primary-source report and future device spike. No production datasets were downloaded, messages sent externally, or licence agreements accepted by agents. Subsequent implementation verification is recorded in [implementation status](../IMPLEMENTATION_STATUS.md).

## Handoff

SHARED_CONTRACTS.md: implementable domain, wire, service, storage, time and provisional Health boundaries.
FIXTURES_V1_V2.md: small human-readable synthetic generation/state/acceptance specifications.
The first bounded A02/A05/D02 implementations were reviewed against these decisions. A07/A08 should consume the same fixtures. Health adapter work remains evidence-gated.
