<!--
SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Release Process

This repo releases content, not Python packages. The release artifact is the
generated single-YAML bundle under `dist/`.

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

Run:

```bash
uv run python scripts/build.py
uv run python scripts/build.py --check
uv run python scripts/checksums.py > SHA256SUMS
```

Commit source changes and generated `dist/` changes together. `SHA256SUMS` is
release output and is not committed.

## Publishing

Pushing a `v*` tag runs the release workflow. It verifies generated bundles,
creates `SHA256SUMS`, and publishes a GitHub Release with:

- `dist/hegemony-demo.single.yaml`
- `SHA256SUMS`

The repository can also be consumed directly by cloning a tag and mounting
`dist/` into Hegemony's `/bootstrap` directory.

## Immutability

Do not replace release artifacts for an existing tag. If released content is
wrong, create a new tag and release.
