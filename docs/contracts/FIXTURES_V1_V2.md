# Synthetic acceptance fixture specifications v1/v2

All foods, values, labels, identifiers and source claims below are synthetic. No manufacturer association. This deliberately small set covers contracts rather than catalogue coverage targets. Wire values follow SHARED_CONTRACTS §11. Unlisted nutrients = unknown(notProvided); not zero. Every profile is per 100 g unless specified. Namespace mealtracker.synthetic; recordID values below are literal stable IDs. v1 generation 00000000-0000-4000-8000-000000000001; v2 generation 00000000-0000-4000-8000-000000000002. Revision strings r1/r2 are opaque catalogue revisions, never numeric counters.

## Catalogue v1

| recordID | kind/revision | Names sv/en/de | Profile or components |
| --- | --- | --- | --- |
| sausage | product/r1 | Testkorv/Test sausage/Testwurst | energy 200 kcal, protein 10 g, fat 15 g, EU carbohydrate 5 g, fibre unknown, salt 1 g; sales SE+DE; origin unknown; portion slice stable p1 = 25 g labelled Testskiva |
| potato | ingredient/r1 | Testpotatis/Test potato/Testkartoffel | energy 80 kcal, protein 2 g, fat knownZero, EU carbohydrate 17 g, fibre 2 g; cooked |
| oil | ingredient/r1 | Testolja/Test oil/Testöl | basis 100 ml, energy 810 kcal, fat 90 g, density 0.9 g/ml measured |
| trace | ingredient/r1 | Testspår/Test trace/Testspur | energy 10 kcal, fibre trace upperBound 0.1 g exclusive, protein knownZero |
| starter | recipe/r1 | Testrätt/Test dish/Testgericht | c-sausage: sausage/r1 100 g; c-potato: potato/r1 200 g; servings 2; finished yield 250 g |

Barcode sausage = string 0000000000001 (alias only). All descriptions carry provenance synthetic-fixture/noRealSource; source permission only for synthetic generated test data. Recipe leaf pins retain exact effective r1 profiles. Recipe total energy = 360 kcal; per serving 180; 125 g finished = 180. Total fibre incomplete with known subtotal 4 g. Sodium from salt = derived 400 mg; no second addition if direct sodium 400 mg is also supplied in an alternate fixture. oil 10 ml = 81 kcal; oil 9 g = 81 kcal; remove density and 9 g logging returns missingConversion.

## Private state before upgrade

1. Overlay sausage revision 1: name en set "My sausage"; energy set 215 kcal on accepted 100 g basis; p1 label clear; protein inherit. Accepted effective profile is retained.
2. Overlay starter revision 1 removes component c-potato by ID. Separate alternate fixture edits c-potato amount to 250 g instead of removing it.
3. Personal recipe P UUID 10000000-0000-4000-8000-000000000001 pins sausage effective overlay revision 1 at 100 g, servings 1, yield absent. Energy 215 kcal; protein 10 g; mass logging fails missingYield. Pin does not change when overlay later resets.
4. Meal M UUID 20000000-0000-4000-8000-000000000001 at 2026-10-10T12:00:00+02:00, Europe/Stockholm, recorded date 2026-10-10, lunch automatic; 75 g effective sausage. Energy 161.25 kcal, protein 7.5 g, fat 11.25 g, fibre incomplete. Health carbohydrate blocked despite complete EU carbohydrate. Snapshot stores r1 plus overlay revision 1. No production Health write occurs in fixture evaluation.

## Catalogue v2

sausage/r2 energy 205 kcal, protein 11 g, p1 label "Updated slice"; all other facts unchanged. potato/r2 retired with r1 retained for pins; starter/r2 reorders c-potato before c-sausage. Independent structural branch starter/r2 removes c-potato. Independent basis branch sausage/r2 changes to 100 ml with no density and energy 190 kcal; do not combine branches in one case.

## Expected upgrade outcomes

| Scenario | Expected |
| --- | --- |
| Standard v2 effective sausage | personal name, energy 215, protein 11, p1 label absent; sourceChanged on edited energy/name if source name changed |
| Reset energy after standard v2 | 205 inherited; personal name and cleared label remain |
| Old M after activation | 161.25 kcal, protein 7.5 g, same name snapshot; no rewrite |
| Change old M quantity to 100 g | 215 kcal, protein 10 g from stored snapshot |
| Explicit refresh M at 75 g before energy reset | 161.25 kcal, protein 8.25 g; new event revision |
| Personal P after standard v2 and reset | remains energy 215/protein 10 until accepted refresh |
| Starter reorder with removal overlay | c-potato still removed, c-sausage survives |
| Structural branch with edited c-potato | retained private c-potato pin at 250 g; no array-index reassignment |
| Basis branch sausage | entire last accepted personal profile retained: 100 g, 215 kcal, protein 10; needsReview(basisChanged); current ml protein cannot leak in |
| Retired potato | hidden new-search selection; retained pins resolve; historical recipe survives |
| No-density oil branch | ml works, g returns missingConversion |
| Unknown fibre/trace | no complete fibre export; trace not numeric zero |

## Temporal and concurrency cases

Europe/Stockholm 2026-03-29 day interval is 23 hours; 2026-10-25 is 25 hours. Local 2026-03-29 02:30 is nonexistent and returns typed error with suggestion; local 2026-10-25 02:30 has two choices (+02:00 and +01:00). Manual dinner at 10:00 remains dinner after time edit; automatic at 10:59→11:00 changes breakfast→lunch. Travel meal retains original recorded date after device-zone change. Future wall time needs confirmEaten.

Pause save after generation lease v1; activate v2; resume save: all meal components use v1, or whole command re-resolves, never mixed generation. Overlay edit while save reads revision 1 makes staleRevision on commit, no partial meal/outbox. Storage-full during activation leaves v1 pointer and private edits intact. Index built at sequence 10 with rename at 11 must catch up or use fallback; renamed food searchable immediately.

## Health desired-state fixture (device execution still required)

M energy desired generation 1 payload 500 kcal/version 1; fake external save succeeds, crash before local acknowledgement. Retry same immutable version/identity converges one current 500. Edit generation 2 payload 600/version 2; stale generation-1 completion cannot mark generation 2 exported. Current sample total 600, never 1,100. Known→unknown generation 3 is absent with cleanup; crash after deletion before acknowledgement retries to absent. Timestamp edit preserves identity and increases version. Direct user removal after completed export does not automatically recreate. Restoring archive containing version 1 enters reconciliationRequired; never guesses current Health version from archive. These are expected outcomes, not verified HealthKit API claims.

Fixture scope clarification: starter recipe and all private-state scenarios are Markdown specifications only; the concrete JSON files contain four leaf foods. Barcode 0000000000001 is an intentionally invalid synthetic alias for leading-zero preservation tests, never a real GTIN.
