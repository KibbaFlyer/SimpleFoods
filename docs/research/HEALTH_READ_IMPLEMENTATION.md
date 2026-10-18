# A16 read-only Health energy handoff

Implemented in `MealTracker/Sources/MealTrackerHealth` with portable tests in `MealTracker/Tests/MealTrackerHealthTests`. The app project enables the HealthKit entitlement and localized read-purpose strings. Foundation models and reader compile on macOS; NativeHealthEnergyGateway is iOS-only and imports HealthKit.

The @MainActor EnergyReader exposes active/resting EnergyReadState and optional total. Call connect() only for an explicit user Connect action, then refresh(day:timeZone:). Constructing a reader, calling refresh before connect or viewing Settings never requests authorization. Request completion does not establish read authorization. Read states distinguish notRequested/loading/noReadableData/value/error/stale; no readDenied state exists. Nil quantities remain noReadableData while a real returned zero remains value(0). Availability is separate. Stale states retain original fetchedAt/window/coverage; totals use only two current values with equal windows and equal coverage. UI should label unknown coverage and reported expenditure, and today is explicitly isSoFar with end=now. No physiological completeness is claimed.

Native requests read types activeEnergyBurned/basalEnergyBurned only, with an empty write set. Each type gets a cumulative statistics collection query with a Gregorian calendar/time zone, day interval and midnight anchor. The same explicit window bounds both requests. No workouts, raw arrays, separate-source sums, dietary estimates or network/disk Health caches are used. Task cancellation stops the query. The Foundation QueryOperation bridge handles cancel-before-install, cancel-during-execute and callback/cancel races with one continuation completion and one eventual stop. Later refresh results cannot overwrite a newer generation.

Earliest-authorized-date introspection is deferred. Native coverage is always unknown, including historical days; neither missing data nor a completed request is represented as full access. No background delivery, nutrition write, export ledger or Health cache is implemented here.

## Primary evidence and validation

Reviewed existing docs/research/HEALTHKIT_DECISIONS.md and shared contracts. Apple primary pages were opened:
- https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- https://developer.apple.com/documentation/healthkit/executing-statistical-queries
The public tool returned their JavaScript/Markdown links but could not fetch Markdown (unsupported content type); installed SDK headers supply the precise callable declarations:
- iPhoneOS.sdk/System/Library/Frameworks/HealthKit.framework/Headers/HKHealthStore.h: isHealthDataAvailable, read authorization and stopQuery.
- HKStatisticsCollectionQuery.h: daily interval/anchor initializer, initialResultsHandler; nil quantities for empty intervals.
The installed SDK marks callback-based collection queries as API_TO_BE_DEPRECATED rather than setting an unavailable deployment floor. The module compiles against the installed iPhoneOS SDK with arm64-apple-ios18.0 / Swift 5 mode. No HealthKit calls were executed.

Eleven portable tests pass (including the integration owner’s cross-day stale-value regression): explicit-connect gating, nil-vs-real-zero, matching coverage sum, differing coverage refusal, stale original timestamp, Stockholm 23/25-hour DST days, invalid numbers/future windows, cancellation-before-install, callback-before-cancel and cancellation-during-execute. Native SDK typecheck passes with no diagnostics. These tests do not establish physical-device behavior for permissions, locks, source overlap, interval clipping, or purpose-string localization. Those remain device acceptance gates.

## App composition requirements

Enable HealthKit entitlement in the app. Supply NSHealthShareUsageDescription and system-localized sv/en/de purpose strings explaining active/resting energy reads; root owns signing and these resources. Do not advertise nutrition export or add write-purpose claims for this module. The OS permission sheet follows system localization, while app strings follow app localization. A settings Connect button and Today cards should show unavailable / no readable data / stale distinctly, with comparison time zone visible when relevant.
