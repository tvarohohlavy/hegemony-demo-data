<!--
SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Repository Structure

This repository is a content repo for Hegemony instance bootstrap bundles. It
does not publish Python packages or runtime plugin modules.

## Layout

```text
manifest.yaml
src/bundles/
src/files/
demo-inventory/
dist/
scripts/build.py
scripts/validate.py
```

- `manifest.yaml` lists generated bundles and their source/output paths.
- `src/bundles/*.yaml` contains human-edited Configuration Exchange fragments.
- `src/files/**` holds larger flow-attachment payloads (Dockerfile, containerlab
  topology, FRR configs, provisioning scripts) referenced from
  `flow_attachments` entries via `content_file:` and inlined at build time.
- `demo-inventory/{sites,devices}/**` is the Git inventory source of truth read
  by the `lab-inventory` git provider (`schema_version: 1` records; site paths
  derived from directory layout, `external_id` equal to the file stem).
- `dist/*.yaml` contains generated single-YAML bundles committed for direct use.
- `scripts/build.py` merges fragments deterministically, inlines `content_file`
  attachments, and verifies generated bundles are in sync.
- `scripts/validate.py` checks cross-fragment references, secret-ref patterns,
  step-handler ids, and the `demo-inventory/` tree before bundles are published.

## Fragment Rules

- Every source fragment must be a YAML mapping with `schema_version: 2`.
- Edit source fragments, not files under `dist/`.
- Files in a bundle source directory are merged in lexical filename order
  (the demo fragments are numbered `05`–`55` to control that order).
- Top-level list sections are concatenated.
- Top-level mapping sections are shallow-merged by key.
- Unsupported top-level keys fail the build so typos do not silently ship.
- A `flow_attachments` entry may set `content_file: <repo-relative path>` in
  place of `content:`; the build reads that file (from `src/files/`) and inlines
  it as the attachment `content`. Setting both is an error.

The generated bundle is consumed by Hegemony's generic instance bootstrap path:
mount the generated `dist/` directory into the API container at `/bootstrap`.

## Adding Another Bundle

Add a new entry to `manifest.yaml`:

```yaml
schema_version: 1
bundles:
  - id: hegemony-demo
    source_dir: src/bundles
    output: dist/hegemony-demo.single.yaml
  - id: another-example
    source_dir: src/another-example
    output: dist/another-example.single.yaml
```

Then run:

```bash
uv run python scripts/build.py
uv run python scripts/build.py --check
uv run python scripts/validate.py
```
