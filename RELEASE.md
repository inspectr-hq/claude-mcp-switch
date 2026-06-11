# Release Process

This repository now has both test CI and a tag-driven release workflow.

## Workflows

- `.github/workflows/tests.yaml`
- `.github/workflows/release.yaml`

## Trigger

The release workflow runs when a tag matching `v*` is pushed:

```yaml
on:
  push:
    tags:
      - "v*"
```

Examples:

- `v1.0.0`
- `v1.1.3`

## What The Release Workflow Does

1. Checks out the repository.
2. Selects the full Xcode install.
3. Reads the version from the tag and strips the leading `v` for `MARKETING_VERSION`.
4. Builds `ClaudeMcpSwitch.app` from `app/ClaudeMcpSwitch.xcodeproj` using the `ClaudeMcpSwitch` scheme in `Release` configuration.
5. Disables code signing during build.
6. Ad-hoc signs the built app bundle to reduce unsigned distribution warnings.
7. Packages release assets as:
   - `ClaudeMcpSwitch-<version>.zip`
   - `ClaudeMcpSwitch-<version>.dmg`
8. Publishes both assets to a GitHub Release with generated notes.
9. Downloads the just-published DMG in a second job.
10. Computes the DMG SHA256.
11. Checks out `inspectr-hq/homebrew-inspectr`.
12. Rewrites `Casks/claude-mcp-switch.rb` with the new version, SHA, and release URL.
13. Commits and pushes the cask update to the tap repository.

## Expected Artifact URLs

For version `1.0.0`, the workflow publishes:

- `https://github.com/inspectr-hq/claude-mcp-switch/releases/download/v1.0.0/ClaudeMcpSwitch-1.0.0.zip`
- `https://github.com/inspectr-hq/claude-mcp-switch/releases/download/v1.0.0/ClaudeMcpSwitch-1.0.0.dmg`

## Brew Setup

The release workflow expects:

- tap repository: `inspectr-hq/homebrew-inspectr`
- cask path: `Casks/claude-mcp-switch.rb`
- secret: `HOMEBREW_TAP_TOKEN`

The repository also includes a cask template at:

- `packaging/homebrew/claude-mcp-switch.rb`

The live tap cask should point at the GitHub Release DMG URL pattern:

```ruby
url "https://github.com/inspectr-hq/claude-mcp-switch/releases/download/v#{version}/ClaudeMcpSwitch-#{version}.dmg"
```

## How To Cut A Release

1. Make sure the intended release commit is pushed.
2. Create and push a tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

3. Wait for `.github/workflows/release.yaml` to finish.
4. Verify that the GitHub Release contains:
   - ZIP
   - DMG
5. Verify that the Homebrew tap was updated with the new cask version and SHA.

## Current Constraints

- release artifacts are ad-hoc signed, not notarized
- the workflow assumes write access to `inspectr-hq/homebrew-inspectr`
- `HOMEBREW_TAP_TOKEN` must exist in repository secrets
- the packaged app bundle is renamed to `Claude MCP Switch.app` inside the DMG for installation clarity

## Local Development Commands

Build locally:

```bash
cd app
swift build
```

Run tests locally:

```bash
cd app
swift test
```

Open in Xcode:

```bash
open app/ClaudeMcpSwitch.xcodeproj
```
