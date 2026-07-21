<!--
SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Release Process

This repo releases content, not Python packages. The release artifacts are the
generated single-YAML bundles under `dist/` (one per organization, imported in
filename order).

## Versioning

Use immutable Git tags. Either semver-style tags such as `v0.1.0` or date tags
such as `v2026.07.01` are fine as long as the project keeps one convention.

Recommended default for demo data is date tags:

```text
vYYYY.MM.DD
```

Use a suffix if more than one release is needed on the same day:

```text
v2026.07.01-2
```

## Before Tagging

Regenerate and verify the bundle:

```bash
uv run python scripts/build.py
uv run python scripts/build.py --check
```

Also confirm `install.sh`'s `HEGEMONY_PLATFORM_REF` default points at the
platform release this demo bundle targets — that value is baked into the
released installer. (`INSTALLER_VERSION` is stamped automatically; leave it as
`main` in the repo.)

Commit source changes and generated `dist/` changes together.

> **Note:** do not generate `SHA256SUMS` by hand here — the release workflow
> produces it *after* stamping `install.sh`, so a checksum computed against the
> unstamped (`INSTALLER_VERSION=main`) installer would not match the published
> asset. `SHA256SUMS` is release output and is not committed. (`task checksums`
> remains available for a local preview of the bundle digest.)

## Publishing

Pushing a `v*` tag runs the release workflow. It verifies generated bundles,
stamps the tag into `install.sh` (`INSTALLER_VERSION=<tag>`), creates
`SHA256SUMS`, and publishes a GitHub Release with:

- `dist/*.single.yaml` (a platform org-directory bundle plus one resource bundle per org)
- `install.sh`
- `SHA256SUMS`

### The installer is a versioned release asset

The stamped `install.sh` is self-identifying (`install.sh --version` prints the
tag) and defaults its `--demo-ref` to that same tag, so a released installer
reproducibly installs the demo data it shipped with. The **exact-tag** URL is
immutable and reproducible:

```bash
curl -fsSL https://github.com/tvarohohlavy/hegemony-demo-data/releases/download/vX.Y.Z/install.sh | sh
```

The `releases/latest/download/install.sh` URL is a moving alias — convenient for
always getting the newest release, but it changes as new releases ship, so it is
not pinned. `main` (raw URL) stays `INSTALLER_VERSION=main` and tracks bleeding
edge.

`SHA256SUMS` covers `install.sh` as well as the bundle, so both can be verified
before running.

The repository can also be consumed directly by cloning a tag and mounting
`dist/` into Hegemony's `/bootstrap` directory.

## Immutability

Do not replace release artifacts for an existing tag. If released content is
wrong, create a new tag and release.
