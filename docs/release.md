# Release Guide

Vigil is distributed outside the App Store as a Developer ID-signed, Apple-notarized
`.zip` attached to GitHub Releases. Pushing a `v*` tag runs everything on a
GitHub-hosted `macos-26` runner (`.github/workflows/release.yml`) — no local steps needed.

```
git tag v1.0 && git push origin v1.0
```

The workflow:

1. Imports the Developer ID Application certificate into a temporary keychain
2. Writes the tag into `CFBundleShortVersionString` (`v1.2` → `1.2`) and the run
   number into `CFBundleVersion`
3. `make bundle` with a universal (arm64 + x86_64) build, signed with
   Developer ID + Hardened Runtime + secure timestamp
4. `xcrun notarytool submit --wait` → `xcrun stapler staple`
5. `gh release create` attaches `Vigil.zip` to the release

## Required repository secrets

Same six secrets as [morishin/Voxt](https://github.com/morishin/Voxt) — the
Developer ID certificate is team-wide and the app-specific password belongs to the
Apple ID (not to an app), so the identical values can be reused:

| Secret | Content |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application `.p12`, base64-encoded |
| `P12_PASSWORD` | Password of the `.p12` |
| `KEYCHAIN_PASSWORD` | Any string (temporary CI keychain) |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_APP_PASSWORD` | App-specific password from appleid.apple.com |
| `APPLE_TEAM_ID` | `4GERXBURZN` |

## Manual local release (fallback)

```sh
make bundle \
  BUILD_FLAGS="--arch arm64 --arch x86_64" \
  RELEASE_DIR=".build/apple/Products/Release" \
  SIGN_IDENTITY="Developer ID Application" \
  SIGN_FLAGS="--options runtime --timestamp"

ditto -c -k --keepParent dist/Vigil.app /tmp/Vigil.zip
xcrun notarytool submit /tmp/Vigil.zip --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" --team-id 4GERXBURZN --wait
xcrun stapler staple dist/Vigil.app
ditto -c -k --keepParent dist/Vigil.app /tmp/Vigil.zip   # re-zip after stapling

gh release create v1.0 /tmp/Vigil.zip --title v1.0 --generate-notes
```

## Troubleshooting

- **Notarization returns `Invalid`**: fetch the log with
  `xcrun notarytool log <submission-id> --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id 4GERXBURZN`.
  Common causes: missing Hardened Runtime or secure timestamp (both are set by the
  workflow's `SIGN_FLAGS`).
- **`macos-26` runner not found**: check
  [actions/runner-images](https://github.com/actions/runner-images) and update
  `runs-on` in `release.yml`.
