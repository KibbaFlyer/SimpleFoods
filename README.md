# SimpleFoods

A native, offline iPhone meal tracker focused on Swedish food, with German coverage, an in-app Swedish/English/German language selector, and Apple Health energy reads.

The creation of Simple Foods was greatly supported by AI agentic tooling.

The app now has a durable local meal diary, catalogue search, personal foods and overrides, camera/manual barcode lookup, and explicit Open Food Facts sync. Health connection reads active and resting energy only after you tap Connect. Nutrition export and saved recipes are still pending. The bundled catalogue contains four visibly fictional development foods; real OFF records are fetched only through explicit lookup or sync.

## Run the app

Open `MealTracker/MealTracker.xcodeproj` in Xcode, select the MealTracker scheme and an iPhone simulator, and Run. Minimum deployment target is iOS 18. Physical-device deployment requires your own signing team, HealthKit capability and bundle identifier; the current identifier is `com.example.MealTracker`.

SwiftPM resolves the pinned GRDB 7.11.1 dependency; the Python tools use the standard library. The package requires Swift tools 6.1 and uses Swift 5 language mode. Verification used Xcode 27.0 and Swift 6.4; minimum-OS runtime testing remains pending.

Run both test suites, check fixture consistency, and validate Swift-encoded data against the Python schema with `python3 tools/check_foundation.py` from the repository root.

```sh
cd MealTracker
swift test
xcodebuild -project MealTracker.xcodeproj -scheme MealTracker -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The project is checked in. To regenerate it from the repository root, run `python3 tools/generate_xcode_project.py`. The generator owns the project and shared scheme; update it alongside project configuration changes.

## Build a development catalogue

From the repository root:

```sh
python3 -m unittest discover -s tests/catalogue -v
python3 -m tools.catalogue --input data/fixtures/fixture-v1.json --registry data/source-registry.json --allow-input data/fixtures/fixture-v1.json --allow-input data/source-registry.json --output /private/tmp/mealtracker-pack-v1
```

Choose a new output directory on each run. The builder validates explicit public inputs and emits SQLite, canonical JSON, checksums, attribution, and an update diff. The supplied fixtures have fictional nutrition values and are for development only. Real Swedish/German datasets have not been acquired or approved for bundling. See [catalogue tooling](tools/catalogue/README.md) for update commands and the supported schema.

## Implementation handoff

Read [implementation status](docs/IMPLEMENTATION_STATUS.md) for the review decisions, verified behavior, limits, and next packages. The complete product plan remains:

1. [Product and architecture plan](docs/PRODUCT_AND_ARCHITECTURE_PLAN.md) — user experience, scope, data model, customization rules, nutrition calculations, Apple Health, and release criteria.
2. [Database acquisition plan](docs/DATA_ACQUISITION_PLAN.md) — sources, licensing decisions, Swedish and German coverage, ingestion, quality checks, and catalogue releases.
3. [Agent work packages](docs/AGENT_WORK_PACKAGES.md) — 29 bounded assignments, dependencies, ownership, acceptance criteria, implementation waves, and a reusable handoff prompt.

The reviewed [shared contracts](docs/contracts/SHARED_CONTRACTS.md), [source decisions](docs/research/SOURCE_REGISTRY.md), and [HealthKit decisions](docs/research/HEALTHKIT_DECISIONS.md) constrain subsequent implementation. Dispatch bounded packages using their dependency map.

The central architectural rule is:

**A replaceable, read-only food catalogue + separately stored user customizations + immutable historical meal snapshots.**

This lets the catalogue improve without overwriting personal edits or changing meals already logged.
