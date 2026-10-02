<!--
SPDX-FileCopyrightText: 2026 Iva Horn
SPDX-License-Identifier: MIT
-->

# Contributing to Cirruscope

Thanks for your interest in contributing.
This document is written for developers, in the same spirit as [README.md](./README.md).
For a more general introduction, see [the official website](https://cirruscope.app).

## Before You Start

For anything beyond a small fix, please open an issue first and check it against the project's scope in [GOVERNANCE.md](./GOVERNANCE.md) before writing code.
Cirruscope is a single-maintainer project with a deliberately focused scope, so a pull request that falls outside it may be declined regardless of how well it's built — opening an issue first saves you that wasted effort.
Small, obvious fixes (typos, clear bugs) are fine to send directly.

## Developer Certificate of Origin

Every contribution to Cirruscope must be signed off under the [Developer Certificate of Origin](https://developercertificate.org/) (DCO).
By signing off a commit, you certify that you wrote it (or otherwise have the right to submit it) under this project's license.

Add a `Signed-off-by: Your Name <your@email.com>` trailer to every commit message, using the name and email address you want associated with the contribution:

```
git commit -s -m "Your commit message"
```

To avoid typing `-s` every time, set up a git alias:

```
git config --global alias.ci 'commit -s'
```

If you forgot to sign off a commit you already made, amend it:

```
git commit --amend -s
```

For multiple commits on a branch, sign them all off at once against the branch you're merging into (e.g. `develop`):

```
git rebase --exec 'git commit --amend --no-edit -s' develop
```

then force-push your branch to update the pull request.

[.github/workflows/dco.yml](.github/workflows/dco.yml) checks every commit on every push and pull request against `main`/`develop` for a `Signed-off-by:` trailer, and must pass before a pull request can be merged.

> **Note:** GitHub's default "Squash and merge" only carries commit *titles* into the squashed commit, dropping `Signed-off-by:` trailers along the way.
Either merge with "Create a merge commit" instead, or manually keep a `Signed-off-by:` line in the squash commit message before confirming the merge.

## AI-Assisted Contributions

If you used an AI tool (e.g. GitHub Copilot, ChatGPT, Claude, or similar) to help write any part of a contribution — code, tests, documentation, or commit messages — check the corresponding box in the pull request template.

Disclosure doesn't lower the bar: you must be able to explain every part of your contribution — what it does, why it's written the way it is, and any trade-offs involved — in review, and you are personally accountable for it regardless of how it was produced.
Do not open a pull request for code you have not reviewed and understood yourself.
This doesn't replace the Developer Certificate of Origin above either: signing off a commit still certifies that you have the right to submit its content.

## Code Signing

Every build of Cirruscope is signed for real, with a team and the entitlements in [Cirruscope/Cirruscope.entitlements](./Cirruscope/Cirruscope.entitlements), whether it is a Debug build, a test run or a Release build.
The apps and the widget extension share their data through an App Group, from the store to the cached assets and the widget's last good feed, so a build without that entitlement is not a working build and stops at launch rather than running without its data.
There is no ad-hoc or unsigned build to fall back to.
The tracked configuration in [Cirruscope.xcconfig](./Cirruscope.xcconfig) signs with the maintainer's team, which is why the maintainer needs no further setup and everyone else needs the steps below:

1. Sign in to Xcode with an Apple ID in **Xcode ▸ Settings ▸ Accounts**.
   A free Apple Developer account is enough, with no paid membership: App Groups, Keychain Sharing, App Sandbox and Background Modes, every capability the project uses, are available to it on macOS and iOS alike.
2. Copy [Local.xcconfig.example](./Local.xcconfig.example) to `Local.xcconfig` at the repository root, where it is gitignored, and fill in both values it holds.
   - `DEVELOPMENT_TEAM` is your own team ID, which takes the place of the maintainer's.
   - `CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER` is a reverse-DNS prefix of your own followed by `.cirruscope`.
     The shipping bundle identifiers and the App Group `group.de.i2h3.cirruscope` are registered to the maintainer's team, and no other team can claim them.
     Every identifier the project uses derives from this one, from both apps, the widget extension and the test bundles to the App Group, the Keychain service, the Keychain access group and the iOS background task, so setting it moves them all.

   Keep the file at the repository root rather than in a target's folder.
   Those folders are synchronized, so a `Local.xcconfig` placed in one would be copied into the built product of every target that lists it.
3. If you already have a `Local.xcconfig` made from an earlier version of the template, one that switched signing to Manual, named a provisioning profile or set `CODE_SIGN_ENTITLEMENTS`, replace it with a fresh copy rather than keeping it.
   Those assignments would now reach the widget extension and both test bundles as well, and sign them against a profile made for something else.

Never pick a team in a target's **Signing & Capabilities** tab.
Doing so writes a target-level `DEVELOPMENT_TEAM` into `project.pbxproj`, which overrides `Local.xcconfig` and ends up in your commit.

Xcode registers your identifiers and downloads provisioning profiles for them on its own.
`xcodebuild` does so only when it is passed `-allowProvisioningUpdates`, so every build or test run from a terminal needs that flag, as the commands under [Code Quality Checks](#code-quality-checks) show.

A provisioning profile a free account gets for a physical iPhone expires after about a week, after which the app has to be built and installed onto the device again.
The Mac and the iOS Simulator are not affected.

## Code Quality Checks

- Run `swiftformat .` before committing; the SwiftFormat check on GitHub lints with `swiftformat --lint`.
- Run `biome check --write --error-on-warnings .` before committing if you touched any JavaScript (install it with `brew install biome`); the Biome check on GitHub runs `biome ci --error-on-warnings`.
  Keep the flag — some rules report at warning level, and leaving it off lets a diagnostic pass here that the check still rejects.
- New files need SPDX copyright/license headers; run `reuse lint` to confirm compliance.
- Run the unit tests before opening a pull request: **Product ▸ Test (⌘U)** with the `Cirruscope for macOS` scheme selected, or from a terminal:

  ```
  xcodebuild test -project Cirruscope.xcodeproj -scheme 'Cirruscope for macOS' -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates
  ```

  The scheme is shared, so once signing is set up as described above a fresh clone needs nothing else configured for it.
  GitHub does not build or test pull requests: the maintainer runs the same tests, and a Release build, in Xcode Cloud before merging.
  See [AGENTS.md → Testing](./AGENTS.md#testing) for what the suites cover.
- Changing anything in `Core/` or `Cirruscope/` changes more than the Mac app, since `Core/` compiles into the macOS app, the iOS app and the widget extension alike and `Cirruscope/` into both apps.
  Build and test the `Cirruscope for iOS` scheme on an iOS Simulator as well before opening a pull request, signed like every other build; the iOS app embeds the widget extension, so that run builds the extension too:

  ```
  xcodebuild test -project Cirruscope.xcodeproj -scheme 'Cirruscope for iOS' -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -allowProvisioningUpdates
  ```

  Substitute any iPhone Simulator you have installed for `iPhone 17`.
  See [AGENTS.md → Platform Scope](./AGENTS.md#platform-scope) for why shared placement is the default and what each shared folder is allowed to depend on.
- Changing Swift-only logic that needs no server or web view — shortcut handling, string rendering, pure decision functions — means adding or updating its tests in the same pull request.
  The WebKit-facing code is deliberately not unit-tested; see [AGENTS.md → Testing](./AGENTS.md#testing) for where the line sits and why.
- Any claimed performance improvement must be backed by evidence: include the benchmark, profiling data, or test results that show the before/after impact and explain the scenario it applies to.
- See [AGENTS.md](./AGENTS.md) for the full set of project conventions followed by human and AI contributors alike.

## Contribution Workflow

1. Fork the repository or create a branch.
2. Open a pull request against `develop`.
3. The GitHub checks — DCO, SwiftFormat, Biome and REUSE — must pass before a pull request can be accepted.
   None of them builds or tests the app: before merging, the maintainer runs Xcode Cloud, which builds and tests from a clean clone.

## License

By contributing to Cirruscope, you agree that your contributions will be licensed under this project's [LICENSE](./LICENSE).
