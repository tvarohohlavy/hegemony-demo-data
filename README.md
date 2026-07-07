<!--
SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Hegemony Demo Data

Generated demo Configuration Exchange data for Hegemony instance bootstrap.

This repository owns source YAML fragments and committed generated single-YAML
bundles. Hegemony can load the generated bundle through its generic instance
bootstrap path by mounting `dist/` into the API container at `/bootstrap`.

## Layout

```text
manifest.yaml
src/bundles/
dist/hegemony-demo.single.yaml
scripts/build.py
scripts/validate.py
```

- `manifest.yaml` declares generated bundles.
- `src/bundles/` contains human-edited Configuration Exchange fragments.
- `dist/` contains generated bundles committed for direct mounting.
- `scripts/build.py` performs deterministic merge and sync checks.
- `scripts/validate.py` checks bundle references and current secret-ref patterns.

## Build

```bash
uv sync
uv run python scripts/build.py
```

With [Task](https://taskfile.dev/):

```bash
task build
task check
task release:check
```

## Check

```bash
uv run python scripts/build.py --check
uv run python scripts/validate.py
```

`--check` fails when `dist/hegemony-demo.single.yaml` is not in sync with the source fragments. `validate.py` fails on broken flow, site, destination, variable, or bundled `vault://` references. The pre-commit hook regenerates the bundle automatically.

To generate release checksums:

```bash
uv run python scripts/checksums.py > SHA256SUMS
```

## Use With Hegemony

Check this repository out beside the Hegemony repository, or set `HEGEMONY_BOOTSTRAP_HOST_DIR` to an absolute path ending in this repository's `dist` directory. The Hegemony demo compose overlay mounts the directory into the API container as `/bootstrap`, and the API imports it once for a fresh database.

Instance bootstrap is intentionally one-shot. To apply changed demo data, reset the Hegemony database or import the generated bundle manually through Configuration Exchange.

## Compatibility

- Bundles use Configuration Exchange `schema_version: 2`. Hegemony validates
  schema versions at import time and fails API startup with a clear error on
  unsupported bundles.
- Instance bootstrap ships in Hegemony releases **newer than 1.0.1**; older
  releases ignore the mounted `/bootstrap` directory entirely.
- For reproducible installs, consume a tagged release of this repository (see
  [docs/release.md](docs/release.md)) instead of tracking `main`. Hegemony's
  CI pins a specific commit of this repository for its bundle contract check.

## Docs

- [Repository structure](docs/structure.md)
- [Release process](docs/release.md)
- [Contributing](CONTRIBUTING.md)
- [Contributor License Agreement](CLA.md)
- [Licensing](LICENSING.md)
