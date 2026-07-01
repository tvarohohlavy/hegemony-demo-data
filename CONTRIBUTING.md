<!--
SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Contributing

This repository is part of the Hegemony project. It contains demo instance
bootstrap content, not application code or plugin packages.

## Workflow

1. Edit YAML fragments under `src/bundles/`.
2. Run `uv run python scripts/build.py`.
3. Run `uv run python scripts/build.py --check`.
4. Commit source fragment changes and generated `dist/` changes together.

The pre-commit hook regenerates the bundle automatically when source fragments
or the build script change. CI verifies that generated files are current.

External contributions are accepted only under the
[Hegemony Contributor License Agreement](CLA.md).

## Review Focus

Reviewers should check:

- The generated bundle is synced with source fragments.
- New data is safe for public demo use.
- Secrets are synthetic demo values only.
- Enabled schedules are intentional for demo bootstrap.
- Names and references remain deterministic.
