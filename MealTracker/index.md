---
layout: default
title: Simple Foods Support
permalink: /support/
---

# Simple Foods Support

Simple Foods is a private, local-first food diary for logging meals, reviewing nutrition, saving recipes, and optionally connecting Apple Health.

## Frequently asked questions

### Do I need an account?

No. Simple Foods does not require an account. Your diary, recipes, goals, and personal foods are stored locally on your device.

### How do I log a meal?

Open the day you want, add a meal, search for a food, enter the amount in grams or millilitres, and save. You can edit or delete a logged meal from its detail view.

### Why can't the barcode scanner find a product?

Make sure camera access is enabled for Simple Foods in iOS Settings and that the entire barcode is visible in good light. Product lookups use Open Food Facts, so a valid barcode may still be missing or incomplete. You can enter the food manually when no suitable product is available.

### Does the app work offline?

Most diary, recipe, goal, and manual food features work with locally stored data. Looking up a product that is not cached and refreshing public food databases require an internet connection.

### Where does the nutrition information come from?

Simple Foods uses bundled and public food data, including Open Food Facts and the Swedish Food Agency, plus foods you create yourself. Public data can be incomplete or inaccurate. Check product packaging and use personal foods when you need to correct a value.

### How does Apple Health integration work?

Apple Health is optional. After you tap **Connect Apple Health** and approve access, Simple Foods can read active energy and write dietary energy, protein, carbohydrate, and fat for meals you log. You can change access at any time in the Health app or iOS Settings. Missing Health data does not necessarily mean a value of zero.

### Is recipe import private?

Yes. Pasted recipe text is analyzed on your device and is not uploaded. Review the detected ingredients, quantities, and matched foods before saving because recipe import is experimental.

### How can I share or import a meal, food, or recipe?

Use the system share sheet from the relevant item. Simple Foods exports a `.mealtracker` file that another Simple Foods installation can open. Only share files with people and services you trust because they can contain food names, quantities, and meal dates.

### How do I remove my data?

Individual meals and saved recipes can be deleted in the app. To remove all local Simple Foods data, delete the app and its data from your device. Entries previously written to Apple Health must be managed separately in the Health app, and exported files must be deleted from wherever you shared or saved them.

### My totals look wrong. What should I check?

Check the selected food, serving amount, unit, and whether the source reports nutrition per 100 g or 100 ml. Public food records may contain missing or approximate values. If the issue remains, include the app version, iOS version, and non-sensitive steps to reproduce it in a support report.

### The app is not behaving as expected. What can I try?

1. Confirm that you are using the latest available version of Simple Foods and iOS.
2. Close and reopen the app.
3. Check your internet connection for public food lookups.
4. Review Camera or Health permissions in Settings for features that need them.
5. If the problem continues, report it using the link below.

## Contact support

Open a [new GitHub issue](https://github.com/{{ site.github.repository_nwo }}/issues/new) and describe what happened, what you expected, and how to reproduce it. Include your Simple Foods version and iOS version when relevant.

GitHub issues are public. Do not attach screenshots or files containing meal history, Health information, or other sensitive personal data.

## Privacy

Read the [Simple Foods Privacy Policy]({{ '/privacy/' | relative_url }}).
