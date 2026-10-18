# Numerical and Health-state fixture specification

2026-10-10. Specification only; no cases executed. Decimal expected values before display rounding; synthetic inputs. Calculator tolerance: exact decimal where feasible; if Double adapter used, absolute 1e-9 for these bounded fixtures. Display formatting is tested separately; never round ingredient contributions before summing.

| ID | Input/action | Expected |
|---|---|---|
| N01 | 75 g, 200 kcal/100 g | 150 kcal |
| N02 | Three portions each 1 g at 33.333 kcal/100 g | 0.99999 kcal internal; display 1 kcal, not sum of individually rounded values |
| N03 | Salt 1 g | derived sodium 400 mg; salt stays 1 g |
| N04 | Same source lists salt 1 g and sodium 400 mg | sodium total 400 mg, never 800 |
| N05 | Salt 1 g and sodium 500 mg on same source | conflict evidence; authoritative-selection policy required, no automatic sum |
| N06 | 250 ml at density 1.04 g/ml; 100 kcal/100 g | mass 260 g; 260 kcal |
| N07 | 250 ml, only per-100-g nutrients, no density | unsupported conversion; no invented total/export |
| N08 | Meal fibre component A 2 g, component B unknown | fibre incomplete; energy may independently be complete/exportable |
| N09 | Known zero protein for every component | complete 0 g protein; distinct from unknown |
| N10 | Recipe 1000 kcal, yield 500 g; log 125 g | 250 kcal |
| N11 | Recipe 1000 kcal, 4 servings, no cooked mass | serving 250 kcal; grams unavailable |
| N12 | EU carbohydrate 20 g, fibre 5 g, polyols 3 g | preserve all definitions; carbohydrate Health export blocked, no inferred 25/17/22 g |
| N13 | 100 kcal supplied; macros imply 110 kcal | preserve supplied 100 with provenance; flag validation as appropriate, do not silently replace |
| N14 | Negative, NaN, infinity, invalid unit | validation error before calculation/export |

| ID | Fake gateway sequence | Expected persisted/UI behavior |
|---|---|---|
| H01 | isAvailable false | unavailable; no authorization/query calls; diary save succeeds |
| H02 | request completes success; queries return nil sums | noReadableData, never readDenied or 0 |
| H03 | active 300 kcal, basal nil | active shown, total absent |
| H04 | active 300, basal 1400, identical window | reported total 1700; coverage caveat retained |
| H05 | active explicit quantity 0; basal 1400 | active zero is valid; total 1400 |
| H06 | active/basal differing limited-history bounds | partial/truncated states; no full-day total |
| H07 | locked error after prior successful query | deferred/stale with old fetchedAt; no cache timestamp refresh |
| H08 | Stockholm 2026-03-29 / 2026-10-25 | calendar windows 23 / 25 hours; no fixed 86400-second day |
| H09 | save local meal energy 500; protein unknown | local commit and outbox atomic; energy pending, protein blockedIncomplete |
| H10 | energy authorized, protein denied | independent energy confirmation; partial export/attention; no false all-success |
| H11 | known energy revision 1 500→revision 2 600 | stable identity, increasing version, one current 600 sample; never intake 1100 |
| H12 | time-only payload edit | replace with higher version at new instant; old instant absent |
| H13 | category-only edit, payload unchanged | local revision may advance; no needless Health payload/version change |
| H14 | known protein→unknown | removal intent retained until owned prior sample absent; no zero substitution |
| H15 | meal deleted while write in flight | stale completion cannot confirm new desired state; latest deletion reconciles |
| H16 | older operation queued after newer desired state | older job superseded before issuing write |
| H17 | ambiguous save result / crash before ledger commit | query exact owned identity; matching version/hash acknowledged; uncertainty deferred; do not blindly allocate new version |
| H18 | deletion with revoked share | cleanupBlocked and prior value may remain; tombstone survives restart/local erase |
| H19 | deletion identity query finds nothing | absent confirmed, no delete([]) call |
| H20 | explicit user deletion of completed sample detected | externallyRemoved; no automatic recreation |
| H21 | export turned off | new writes paused; existing samples retained; explicit cleanup state preserved |
| H22 | restore backup v2 while Health identity has v5 | reconciliationRequired; no v2 write or auto v6 stale overwrite |
| H23 | restore backup sample absent in Health | absence not treated as permission to resurrect; require explicit repair |
| H24 | repeat import same backup ID/digest | rejected/no duplicate meals, identities or Health samples |
| H25 | invalid backup/password/version/interruption | live diary untouched; temporary plaintext cleaned |

Physical-device gates (record OS/SDK, device, app build, Health source settings, sample identities, observed quantities and timestamps):

1. Multi-source active/basal overlap compared to Health app for matching day/window; workout calories never separately added. Do not bake raw-sample sum into expected total.
2. Same sync identity + equal version + exact payload after lost acknowledgement: count/version/payload and callback verified. Also lower version versus existing newer and higher-version replacement. Gate idempotency claim on evidence.
3. Save array containing permitted and denied nutrient: confirm documented none-saved behavior; independent per-type saves permit partial export.
4. Share revocation blocks write/delete; read denial produces honest unknown/no-readable-data; partial grants and later Settings changes refresh per-type state.
5. Start=end eating instant accepted; timestamp edit and day boundary reflect one current sample.
6. Crash after allocation, Health save, local acknowledgement, deletion, and supersession converges without duplicates/stale success.
7. Manual Health sample deletion is respected; old backup restore never revives it automatically.
8. Mismatched app/system language records OS sheet/purpose-string behavior. No promise of system language override.
9. OS backup exclusion verified for database, WAL/SHM, private index, cache, ledger, newly-created files and exports; CloudKit entitlement absent. Local encrypted restore preserves IDs and snapshots.

Do not mark these device gates passed using mocks, simulator results, header inspection, or successful compilation.
