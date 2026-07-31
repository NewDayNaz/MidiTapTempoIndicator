# CI/CD

GitHub Actions builds the project on every push and pull request to `main`, and publishes signed, notarized macOS releases when you push a version tag.

## Continuous Integration

Workflow: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)

- Runs on `macos-14`
- Validates shell scripts and entitlements
- `swift build` + `swift test`
- Builds `dist/MidiTapTempoIndicator.app`
- Verifies bundle structure, resources, metadata, and ad-hoc signature

Run the same checks locally with:

```bash
./scripts/ci-verify.sh
```

## Release Builds

Workflow: [`.github/workflows/release.yml`](../.github/workflows/release.yml)

Create a release by pushing a tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The release workflow will:

1. Run the full `ci-verify` checks for the tagged commit
2. Build, sign, and notarize the app (only if verification passes)
3. Publish a GitHub Release with a changelog since the previous tag
4. Attach an architecture-labeled zip (`arm64`, `x86_64`, or `universal`)

## One-Time Apple Setup

1. Sign in at [Apple Developer](https://developer.apple.com/account).
2. Register the bundle ID `com.newdaynaz.miditaptempoindicator`.
3. Create a **Developer ID Application** certificate (or reuse an existing one).
4. Export the certificate as a `.p12` from Keychain Access.
5. Create an [App Store Connect API key](https://appstoreconnect.apple.com/access/integrations/api) with at least **Developer** access for notarization.

## GitHub Repository Secrets

| Secret | Description |
|--------|-------------|
| `MACOS_CERTIFICATE_P12` | Base64-encoded `.p12` export |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | Any strong random string used for the temporary CI keychain |
| `MACOS_SIGNING_IDENTITY` | Full cert name, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `APP_STORE_CONNECT_API_KEY_ID` | API key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer UUID from App Store Connect |
| `APP_STORE_CONNECT_API_KEY` | Base64-encoded `.p8` key file |

Release secrets are only required for tagged releases. CI builds work without any secrets configured.

## Local Signed Build

```bash
export MACOS_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
./scripts/build-app.sh
# or sign an existing build:
./scripts/sign-and-notarize.sh
```
