# Signing the app and widgets

Widgets require a second App ID and a shared App Group. The simulator does not validate device provisioning profiles.

Using the example bundle ID below, configure these in Apple Developer → Certificates, Identifiers & Profiles:

1. Register the App Group `group.com.example.SimpleFoods`.
2. Enable App Groups on `com.example.SimpleFoods` and assign that group. Preserve the app's HealthKit capability.
3. Register the extension App ID `com.example.SimpleFoods.widgets`, enable App Groups, and assign the same group.
4. Regenerate the app's existing `Simple Foods` provisioning profile after the capability change. Download and install it.
5. Create, download, and install a separate provisioning profile for the widget App ID. Use the same distribution method and signing certificate as the app.

For another bundle ID, substitute the value of `SIMPLEFOODS_BASE_BUNDLE_IDENTIFIER` in these identifiers.

## Manual distribution signing

Add the widget profile's actual name to the private `.env.local` file:

```sh
APP_PROVISIONING_PROFILE='Simple Foods'
WIDGET_PROVISIONING_PROFILE='YOUR WIDGET PROFILE NAME'
WIDGET_SIGNING_IDENTITY='Apple Distribution'
```

Use the identity matching the installed certificate (for example, `iPhone Distribution` for a legacy certificate). Run `Scripts/configure-local.sh` to regenerate `Config/Local.xcconfig`.

Alternatively, set these values directly in the private `Config/Local.xcconfig`:

```xcconfig
SIMPLEFOODS_WIDGET_SIGNING_STYLE = Manual
SIMPLEFOODS_WIDGET_PROVISIONING_PROFILE = YOUR WIDGET PROFILE NAME
SIMPLEFOODS_WIDGET_SIGNING_IDENTITY = Apple Distribution
```

The app and extension cannot share one provisioning profile because their bundle identifiers differ. Both profiles must authorize the App Group.

## Development on an iPhone

Development profiles require a registered device. Connect an iPhone and register it with your team, or register its UDID in the developer account. Both targets need compatible development signing settings/profiles. The existing app target is configured for manual distribution signing; automatic development signing on just the widget target does not change that.

Do not remove the App Group entitlement to bypass signing: the widgets need it to read the app's summary.

Store your real identifiers in `.env.local` as `APP_BUNDLE_IDENTIFIER`, `WIDGET_BUNDLE_IDENTIFIER`, and `APP_GROUP_IDENTIFIER`. Run `Scripts/configure-local.sh` after editing it. Both `.env.local` and generated `Config/Local.xcconfig` are ignored by Git.
