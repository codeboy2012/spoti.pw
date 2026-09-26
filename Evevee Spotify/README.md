# Evevee Spotify/ — EeveeSpotify payloads and source artifacts

Everything specific to **EeveeSpotify**: the extracted payload used by the unified
build, the upstream packages it was extracted from, and the legacy tools used to audit
them. The known-good file hashes recorded during the audit are preserved byte-for-byte
(re-verified after the reorganisation).

## What's here

| Path | What it is |
|---|---|
| `component/` | the extracted Eevee payload: `package/dynamic-libraries/EeveeSpotify.dylib` (+ plist filter), `frameworks/{Orion,EeveeSwiftProtobuf}.framework`, `bundles/EeveeSpotify.bundle`, `resources/` (142 icon PNGs), `manifest.json` with per-file SHA-256 and origin deb hash |
| `component/extract-components.pl` | rebuilds `component/` **and** `PwEvevee/components/spotipw/` from the source artifacts; deterministic, `--force` re-extracts |
| `source-artifacts/` | the audited upstream packages: `EeveeSpotify-6.6.8-SelfContained-v2.deb`, `com.spotipw_0.22.0_iphoneos-arm.deb`, the decrypted Spotify input IPA (`Sptoify-No_Watch_App.ipa`, gitignored), and the legacy Perl audit tools |

## Key hashes (audit-verified, unchanged by the move)

| File | SHA-256 (prefix) |
|---|---|
| `component/package/dynamic-libraries/EeveeSpotify.dylib` | `631d4f17cb5e6d3cd90e67f3043f723e1cb28e11dfca475d67f63657c979de70` |
| bundle `Localizable.strings`, 142 icons, frameworks | verified per-file in `component/manifest.json` |

## Rules

- **Never hand-edit anything under `component/`.** If payloads need refreshing, run
  `perl component/extract-components.pl --force` and check the per-file hashes.
- **`component/` output is wiped on `--force`** — never re-run it without confirming
  the manifests exist afterwards.
- The decrypted Spotify app the build takes as input lives in `source-artifacts/` and is
  gitignored (`*.ipa`); the debs are committed provenance.
- EeveeSpotify is upstream software: Eevee is its author, and the upstream self-contained
  deb integrated here is maintained by jaydenjcpy. This folder only extracts what upstream
  ships; it does not modify it. The integration and the unified package built around it are
  PwEevee's own work.
