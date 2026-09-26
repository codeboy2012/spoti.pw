<h1 align="center">PwEevee</h1>

<p align="center"><strong>An independent integration &amp; distribution project —
one Spotify IPA carrying two great tweaks, built, tested and published by us;
created by others.</strong></p>

<p align="center">
  <a href="#what-this-is">What this is</a> ·
  <a href="#build-it">Build it</a> ·
  <a href="#website">Website</a> ·
  <a href="#credits">Credits</a> ·
  <a href="#ai-disclosure">AI disclosure</a> ·
  <a href="#license--rights">Legal</a>
</p>

---

## What this is

PwEevee does **not** create the software it distributes. It is an independent
integration/build/distribution project that:

- obtains and prepares compatible upstream components
- integrates [spoti.pw](https://github.com/skopevoj/spoti.pw) and EeveeSpotify into one IPA
- resolves their dependencies (duplicates fail the build)
- injects the tweaks into your decrypted Spotify binary and installs their resources
- validates every build (Mach-O load commands, dependency presence, filesystem
  structure, package format)
- packages a reproducible IPA with a full build manifest
- hosts recent builds and archives older ones

We do **not** claim ownership of upstream projects, authorship of upstream tweaks, or
any affiliation with Spotify, Apple, spoti.pw or EeveeSpotify. All trademarks belong to
their respective owners; upstream licenses remain applicable.

### What's in a build

| Component | Upstream | Role in the IPA |
|---|---|---|
| spoti.pw 0.22.0 | [skopevoj/spoti.pw](https://github.com/skopevoj/spoti.pw) (PolyForm Strict 1.0.0; ≤ 0.21.1 GPL-3.0) | `Frameworks/spotifyglass.dylib` — Liquid Glass UI, Mod Settings, Live Activity |
| EeveeSpotify 6.6.8 | Eevee (author); the upstream self-contained deb is maintained by jaydenjcpy | `Frameworks/EeveeSpotify.dylib`, Orion + EeveeSwiftProtobuf frameworks, `EeveeSpotify.bundle`, 142 custom icons |
| CydiaSubstrate | Saurik (as shipped in the proven spoti.pw build) | runtime framework |
| Spotify 9.1.84 | Spotify AB | the app itself — the decrypted Spotify app is the build's input |

## Repository layout

```
Spotipw/             the upstream spoti.pw project, kept intact under its own identity
PwEvevee/            the unified integration/build system — this project's own code
  build-system/      the ONE pipeline: unified.sh, validate, package, tests, release
  dependencies.json  load-command + shared-dependency policy (single source of truth)
Evevee Spotify/      EeveeSpotify payloads + the audited artifacts they came from
  component/         extracted Eevee payload: dylib, frameworks, bundle, 142 icons
  source-artifacts/  the upstream debs/IPAs everything was extracted from
docs/                ARCHITECTURE · BUILD · TROUBLESHOOTING · DEVELOPMENT
website-src/         website source: layout + page templates (the site is generated)
website/             the generated website (static; downloads resolve to GitHub releases)
releases/ scripts/   local release archive + 6-month retention · shared tooling · update-releases.sh
```

## Build it

Requirements: bash, perl (core modules only), xz, unzip. No Theos, no Xcode, no macOS.

```bash
bash PwEvevee/build-system/unified.sh <decrypted Spotify 9.1.84 .ipa> -o dist/my-build.ipa
```

That single command runs the whole pipeline — merge → resolve → inject → validate →
package → manifest → tests — and stops with a named error if anything is wrong.
Details, verification steps and the test suite: [docs/BUILD.md](docs/BUILD.md).
The injected load-command contract is byte-audited against the proven reference build
(docs/UNIFICATION-AUDIT.md).

Output is an **unsigned** IPA; sign it with your own certificate (SideStore, Feather,
AltStore, Sideloadly). Compatibility is verified for Spotify 9.1.84 + spoti.pw 0.22.0 +
EeveeSpotify 6.6.8 — other Spotify versions are not tested.

Building the upstream tweak itself from source (Theos/macOS) still works exactly as
upstream documents it: see [docs/tweaks.md](docs/tweaks.md) and the
[upstream repository](https://github.com/skopevoj/spoti.pw).

## Website

Hosted on SkyTweak infrastructure:

- **Canonical:** `https://pweevee.skytweak.dpdns.org/`
- Alternate path `https://skytweak.dpdns.org/pweevee` redirects to the canonical URL

**GitHub is the release source of truth.** The website hosts no build files of its
own: every download it offers resolves to a published
[GitHub release](https://github.com/codeboy2012/spoti.pw-builds/releases) asset, or to
the download URL named by the upstream source that publishes it. Where a release has
no downloadable asset, the page says "Download currently unavailable" and offers the
release on GitHub instead of a broken button. The site includes full credits, an
AI-development disclosure, maintainer status, hosting/removal policy and contact
information.

The site is a static, dependency-free build generated from `website-src/`. Release
information is never typed in by hand — one command refreshes it:

```bash
scripts/update-releases.sh
```

That does four things:

1. queries the GitHub API for the newest published release of PwEevee, spoti.pw and
   EeveeSpotify (repositories declared once in `website/data/projects.json`) and
   regenerates `website/data/releases.json`
2. reads every declared AltSource — currently the
   [SideloadLabs source](https://github.com/SideloadLabs/SideloasLabs-AltSource), which
   publishes the installable EeveeSpotify IPA variants — into
   `website/data/altsource.json`
3. re-renders every page
4. runs the site checks

Drafts are never used; if a source is unreachable the previous known-good data is kept
and flagged rather than replaced with nothing. The two data sources stay separate and
are labelled on the page: a GitHub release is never presented as an AltSource entry, or
the other way round. No GitHub token ever reaches the browser.

## Credits

**Everything users love about this build was made by other people:**

- **spoti.pw** — Vojtěch Škopek ([skopevoj](https://github.com/skopevoj)) —
  [repo](https://github.com/skopevoj/spoti.pw) ·
  support: [Ko-fi](https://ko-fi.com/darkksh)
- **EeveeSpotify** — Eevee (upstream author); the upstream self-contained deb PwEevee
  integrates is maintained by jaydenjcpy —
  no official donation link was found; none is invented here
- **Orion** ([theos](https://github.com/theos/Orion)), **EeveeSwiftProtobuf**,
  **CydiaSubstrate** (Saurik) — bundled runtime dependencies, as shipped upstream
- **libbs2b** (MIT), **WDL/EEL2** (zlib) — vendored by spoti.pw, licenses preserved

**This project's contribution** is integration engineering, packaging, validation,
hosting and documentation — see the full credit page on the website.

If you enjoy this build, support the upstream developers. Donations go directly to
them; nothing is routed through this project.

## AI disclosure

Yes — AI was used to build this project:

- **Freebuff** — main coding/build agent (repository work, implementation, build
  automation, testing, troubleshooting)
- **ChatGPT** — prompting, planning, troubleshooting, debugging, research assistance
- **Human maintainer** — direction, implementation decisions, review, device testing,
  release decisions; participates directly in development

AI was used as a development tool for this integration project. It is not presented as
the creator of spoti.pw or EeveeSpotify.

## Maintainer status & continuation

Maintained by **one developer** in available free time. There is **no guaranteed
release schedule**. If this maintainer stops, someone else may be able to continue the
project from the available source and the applicable upstream licenses and rights —
preserving licenses, copyright notices, attribution and upstream requirements. This is
not a claim of unrestricted redistribution rights.

## License & rights

- spoti.pw 0.22.0: PolyForm Strict 1.0.0 (releases ≤ 0.21.1: GPL-3.0); its vendored
  third-party code keeps its own licenses
- EeveeSpotify: as distributed upstream with the self-contained package
- This project's build scripts, website and documentation: the integration glue of
  PwEevee — they do not and cannot re-license upstream software
- Hosting & removal: we may remove, replace, suspend or discontinue any published material
  at any time; rights-holder requests are reviewed and may result in removal. No claim
  of legal immunity or of ownership of upstream projects is made anywhere.

Not affiliated with Spotify. Not affiliated with Apple. Not the upstream projects.
