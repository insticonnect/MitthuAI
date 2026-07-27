# Releasing MitthuAI

How code on `main` becomes a download on **mitthuai.com**.

```
git push                     tag v1.2.0                    mitthuai.com
    │                            │                              │
    ▼                            ▼                              ▼
Build workflow             Release workflow            install.sh (redirect)
macos-14 runner            macos-14 runner                      │
./build.sh --universal     ./build.sh --universal --dmg          ▼
  --dmg                    → MitthuAI.dmg                 GitHub Releases
verify-bundle.sh           → SHA256SUMS.txt              /latest/download/…
    │                      → install.sh                         │
    ▼                            │                              ▼
CI artifact (14 days)      GitHub Release ──────────────► user's /Applications
```

Nothing is built on anyone's laptop. `build/` stays git-ignored; the disk image
only ever exists as a CI artifact or a release asset.

## Every push

`.github/workflows/build.yml` runs on every branch and PR: builds the universal
app, packages the DMG, runs `Tools/verify-bundle.sh`, and uploads
`MitthuAI.dmg` as a workflow artifact (14-day retention). That artifact is for
testing — it is not what users download.

## Cutting a release

```bash
git checkout main && git pull
git tag v1.2.0
git push origin v1.2.0
```

`.github/workflows/release.yml` then:

1. builds `arm64 + x86_64` and stamps the tag into `CFBundleShortVersionString`
   (`CFBundleVersion` becomes the run number) — no manual `Info.plist` edit,
2. packages `MitthuAI.dmg` and verifies it,
3. writes `SHA256SUMS.txt`,
4. publishes a release with `MitthuAI.dmg`, `SHA256SUMS.txt` and `install.sh`
   attached, marked **latest**.

Re-running for an existing tag re-uploads the assets (`--clobber`), so a failed
publish is safe to retry. You can also run the workflow manually from the
Actions tab with a version input — it creates the tag from the current `main`.

## The stable URLs

These never change, so the website can hard-code them:

| URL | Serves |
|---|---|
| `https://github.com/insticonnect/MitthuAI/releases/latest/download/MitthuAI.dmg` | the current disk image |
| `https://github.com/insticonnect/MitthuAI/releases/latest/download/install.sh` | the current installer |
| `https://github.com/insticonnect/MitthuAI/releases/latest/download/SHA256SUMS.txt` | its checksum |

## Wiring mitthuai.com

The goal is:

```bash
curl -fsSL https://mitthuai.com/install.sh | bash
```

`curl -L` follows redirects, so **point `/install.sh` at the release asset** and
the website never needs redeploying when the installer changes.

**Cloudflare** — Rules → Redirect Rules: when URI path equals `/install.sh`,
302 to `https://github.com/insticonnect/MitthuAI/releases/latest/download/install.sh`.

**nginx**

```nginx
location = /install.sh {
    return 302 https://github.com/insticonnect/MitthuAI/releases/latest/download/install.sh;
}
location = /download {
    return 302 https://github.com/insticonnect/MitthuAI/releases/latest/download/MitthuAI.dmg;
}
```

**Vercel** (`vercel.json`) or **Netlify** (`netlify.toml`) equivalents:

```json
{ "redirects": [
  { "source": "/install.sh",
    "destination": "https://github.com/insticonnect/MitthuAI/releases/latest/download/install.sh" },
  { "source": "/download",
    "destination": "https://github.com/insticonnect/MitthuAI/releases/latest/download/MitthuAI.dmg" }
] }
```

If you serve a copy of `install.sh` from the site instead of redirecting, send it
as `text/plain` and keep it in sync with the repo — a stale copy pointing at an
old tag is the usual way this breaks. The **Download for Mac** button should
point at `/download` (or the DMG URL) so it always tracks the latest release.

## Gatekeeper: ad-hoc today, notarized later

The build is **ad-hoc signed** (`codesign -s -`). Consequences:

- `curl … | bash` works — `install.sh` strips the quarantine attribute
  (`xattr -cr`) after copying, so the app launches normally.
- A user who instead downloads the DMG in a browser and drags the app across
  will hit *"Apple could not verify MitthuAI is free of malware"*. They can
  right-click → **Open** once, but the installer path avoids it entirely — which
  is why the website should lead with the one-liner.

To remove that caveat you need a paid Apple Developer account ($99/yr) and a
**Developer ID Application** certificate. Then, in the release workflow, replace
the ad-hoc signing step with real signing plus notarization:

```yaml
- name: Import signing certificate
  env:
    CERT_P12: ${{ secrets.APPLE_CERT_P12 }}          # base64 of the .p12
    CERT_PASSWORD: ${{ secrets.APPLE_CERT_PASSWORD }}
  run: |
    echo "$CERT_P12" | base64 --decode > /tmp/cert.p12
    security create-keychain -p ci build.keychain
    security default-keychain -s build.keychain
    security unlock-keychain -p ci build.keychain
    security import /tmp/cert.p12 -k build.keychain -P "$CERT_PASSWORD" \
      -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k ci build.keychain

- name: Sign, notarize, staple
  env:
    APPLE_ID: ${{ secrets.APPLE_ID }}
    TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
    APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}  # app-specific password
  run: |
    codesign --force --deep --options runtime --timestamp \
      --entitlements entitlements.plist \
      -s "Developer ID Application: <Your Name> ($TEAM_ID)" build/MitthuAI.app
    xcrun notarytool submit build/MitthuAI.dmg --wait \
      --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD"
    xcrun stapler staple build/MitthuAI.dmg
```

Notarize the **DMG** (after `--dmg` builds it) and staple the ticket, so even the
browser-download path is clean. Keep `--options runtime` — the hardened runtime
is required for notarization, and the entitlements the app already ships
(Apple Events, network client) are compatible with it.

## Updating an installed copy

There is no in-app updater. Re-running the installer is the update path: it
quits the running app, replaces `/Applications/MitthuAI.app`, and leaves
`~/Library/Application Support/MitthuAI/mitthuai.db` untouched, so the token,
settings, rules and history carry over. Sparkle (or a "new version available"
check against the GitHub releases API) is the natural next step if you want
silent updates.

## Testing the installer without publishing

```bash
./build.sh --universal --dmg
MITTHUAI_DMG_URL="file://$PWD/build/MitthuAI.dmg" ./install.sh
```

`install.sh` skips the checksum check for a custom `MITTHUAI_DMG_URL`. Pin a
published version instead with `MITTHUAI_VERSION=v1.1.0 ./install.sh`.
