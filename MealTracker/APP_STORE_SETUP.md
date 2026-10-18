# App Store release setup

Private signing, bundle, StoreKit, and repository values are configured as
described in `CONFIGURATION.md`. Generate the local configuration before
creating an archive.

## Optional developer tip

The About screen loads the StoreKit consumable configured as `TIP_PRODUCT_ID`
in the private `.env.local` file. Run `Scripts/configure-local.sh` after changing
it. The configured value must match App Store Connect exactly.

Before submitting the app:

1. Accept the Paid Applications Agreement and complete banking/tax setup in
   App Store Connect.
2. Create an In-App Purchase with product type **Consumable**.
3. Use the configured product ID exactly; product IDs are case-sensitive.
4. Give it a reference name such as `Small developer tip`, select a price, and
   add localized display names and descriptions for English, Swedish, and
   German.
5. Attach the purchase to the app version submitted for review and include a
   review screenshot showing the About-page tip button.
6. Test successful, cancelled, pending, interrupted, and unverified purchases
   with a StoreKit configuration and the App Store sandbox.

The tip is optional and consumable. It grants no entitlement, feature,
content, status, or other benefit. Verified transactions are finished after
StoreKit confirms the purchase. Unfinished verified tip transactions are also
finished when the About screen loads.

## Data licensing

Review `THIRD_PARTY_NOTICES.md` and the bundled
`Sources/MealTrackerOpenFoodFacts/Resources/OFF_DATASET_NOTICE.md` before each
release. Regenerate the Open Food Facts index with:

```sh
python3 Tools/build_off_name_index.py Sources/MealTrackerOpenFoodFacts/Resources/OFFNameIndex.jsonl
```

The generator also updates `OFFNameIndex.metadata.json`. Commit the index,
metadata, and notice together.
