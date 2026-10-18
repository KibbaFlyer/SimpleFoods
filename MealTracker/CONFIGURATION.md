# Private build configuration

The repository contains anonymous defaults in `Config/Shared.xcconfig`. Real
signing and App Store identifiers are injected from an ignored local environment
file or from a protected GitHub Environment.

## Local Xcode builds

1. Copy `.env.example` to `.env.local`.
2. Fill in your Apple Developer and App Store values.
3. Run `Scripts/configure-local.sh`.
4. Open the project in Xcode and build or archive normally.

The script creates `Config/Local.xcconfig`. Both private files are ignored by
Git, and the generated file is loaded automatically by the Xcode project.
Re-run the script after changing `.env.local`.

The supported variables are:

- `APPLE_DEVELOPMENT_TEAM`: Apple Developer team ID.
- `APP_BUNDLE_IDENTIFIER`: registered App ID/bundle identifier.
- `APP_PROVISIONING_PROFILE`: provisioning-profile specifier used by Xcode.
- `TIP_PRODUCT_ID`: StoreKit product identifier for the optional tip.
- `PUBLIC_REPOSITORY`: repository in `owner/repository` form. This is used for
  the in-app GitHub link and the network user-agent.

## GitHub builds

Create a GitHub Actions Environment named `build` under **Settings →
Environments**, then add these environment secrets:

- `APPLE_DEVELOPMENT_TEAM`
- `APP_BUNDLE_IDENTIFIER`
- `APP_PROVISIONING_PROFILE`
- `TIP_PRODUCT_ID`

The repository name is supplied automatically by GitHub as
`github.repository`. The build workflow generates the ignored xcconfig on the
runner and performs an unsigned simulator build. Pull requests from forks build
with anonymous defaults because protected secrets are not made available to
them.

The workflow does not upload an App Store archive. A future release workflow
would additionally need a distribution certificate, its password, a
provisioning profile or managed-signing setup, and App Store Connect API
credentials. Store those only as protected environment secrets.

## Before making the repository public

Run a tracked-tree scan and review the output:

```sh
git grep -nIE '(mailto:|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|DEVELOPMENT_TEAM|/Users/)'
```

This only checks the current tree. Existing commits retain their original
author names, email addresses, and earlier file contents. Removing those items
requires rewriting Git history and force-pushing every affected branch and tag.
Back up the repository and coordinate with every collaborator before doing so.
