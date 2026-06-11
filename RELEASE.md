# Release Guide

## Current State

This repository currently has test CI only.

Active workflow:

- `.github/workflows/tests.yaml`

What it does:

- runs on `pull_request`
- uses `macos-latest`
- runs `swift test` from the `app/` directory

What it does not do:

- build signed app archives
- produce `.zip` or `.dmg` artifacts
- create GitHub Releases
- notarize macOS builds
- publish Homebrew formulas or casks

## Current Release Posture

At this stage, Claude MCP Switch should be treated as a development-phase app.

That means:

- CI verifies the reduced Swift test suite
- release packaging is manual if needed
- there is no release workflow to rely on yet

## Manual Local Build

To build locally for development:

```bash
cd app
swift build
```

To run tests locally:

```bash
cd app
swift test
```

To work in Xcode:

```bash
open ClaudeMcpSwitch.xcodeproj
```

## If You Need a Manual App Build

Use Xcode:

1. Open `app/ClaudeMcpSwitch.xcodeproj`
2. Select the `ClaudeMcpSwitch` scheme
3. Build or archive the app from Xcode

This repository does not yet include a documented signing, notarization, or packaging pipeline, so any distributed build should be treated as ad hoc until that is added explicitly.

## Recommended Next Steps Before Public Releases

- add a dedicated build-and-package GitHub Actions workflow
- define versioning and tag conventions
- generate signed `.zip` or `.dmg` artifacts
- add macOS signing and notarization
- document installation and first-launch behavior for distributed builds
- update README badges once release automation exists
