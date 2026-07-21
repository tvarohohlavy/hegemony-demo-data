<!--
SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Repository Structure

This repository is a content repo for Hegemony instance bootstrap bundles. It
does not publish Python packages or runtime plugin modules.

## The multi-organization demo

The demo tells a Managed-Service-Provider story. **Meridian Networks** runs
network automation both for itself and for client tenants:

| Org | Slug | Who | Bundle |
| --- | --- | --- | --- |
| Meridian Networks | `default` | The MSP's own network (the original containerlab demo) | `src/bundles` → `dist/10-meridian…` |
| Shared Standards | `shared` | The **enabled shared org** — golden baseline plus golden compliance / Ansible / Terraform flows that every org can read and run | `src/bundles-shared` → `dist/20-…` |
| Acme Retail | `acme` | Isolated client tenant; overrides the shared NTP standard | `src/bundles-acme` → `dist/30-…` |
| Globex Manufacturing | `globex` | Isolated client tenant; inherits the shared standards unchanged | `src/bundles-globex` → `dist/40-…` |

The platform org directory (`src/bundles-organizations` → `dist/00-…`) declares
all four orgs with their **IdP group→org-role mappings**, designates `shared`,
and carries the one platform-global permission override. It imports first, so
the per-org bundles bind to orgs that already exist and `shared` imports before
the tenants that reference its golden flow.

For a scripted, click-by-click tour of the story — logging in as each persona
and running flows — see the [demo walkthrough](walkthrough.md).

Role grants come from the mappings: with `HEGEMONY_ORG_IDP_SYNC` on (set in the
demo env), a user's Keycloak groups grant the mapped org roles at login. The
demo realm ships matching groups and users (`meridian-noc`, `acme-admin`,
`globex-admin`, `consultant`, `compliance`); the `consultant` also has one
explicit manual membership in the shared org, so both membership sources are
shown. Because IdP reconciliation runs before default-org auto-join, mapped
tenant users never leak into the default org — that is what keeps the client
tenants isolated.

Shared variables and secrets (the `orgs/shared/…` namespace) resolve for every
org at run time, so a bundle may reference them; the validator mirrors this
(`own ∪ shared`) while still rejecting references to another tenant's
resources.

## Layout

```text
manifest.yaml
src/bundles/                 # default org — Meridian's own environment
src/bundles-organizations/   # platform org directory + IdP mappings + global policy
src/bundles-shared/          # the shared org's golden standards
src/bundles-acme/            # client tenant: Acme Retail
src/bundles-globex/          # client tenant: Globex Manufacturing
src/files/
demo-inventory/
dist/
scripts/build.py
scripts/validate.py
```

- `manifest.yaml` lists generated bundles and their source/output paths.
- `src/bundles*/` directories each merge into one dist bundle; the instance
  bootstrap imports every `dist/*.single.yaml` in filename order (the numeric
  prefixes sequence the import).
- `src/bundles/*.yaml` contains human-edited Configuration Exchange fragments.
- `src/files/**` holds larger flow-attachment payloads (Dockerfile, containerlab
  topology, FRR configs, provisioning scripts) referenced from
  `flow_attachments` entries via `content_file:` and inlined at build time.
- `demo-inventory/{sites,devices}/**` is the Git inventory source of truth read
  by the `lab-inventory` git provider (`schema_version: 1` records; site paths
  derived from directory layout, `external_id` equal to the file stem).
- `dist/*.single.yaml` contains generated single-YAML bundles committed for direct use.
- `scripts/build.py` merges fragments deterministically, inlines `content_file`
  attachments, and verifies generated bundles are in sync.
- `scripts/validate.py` checks cross-fragment references, secret-ref patterns,
  step-handler ids, and the `demo-inventory/` tree before bundles are published.

## Fragment Rules

- Every source fragment must be a YAML mapping with `schema_version: 2`.
- Edit source fragments, not files under `dist/`.
- Files in a bundle source directory are merged in lexical filename order
  (the demo fragments are numbered `00`–`55` to control that order).
- Top-level list sections are concatenated.
- Top-level mapping sections are shallow-merged by key.
- `organization` (scalar) is optional: a bundle may omit it (an unbound bundle
  imports into the caller's active org). When present it must be one consistent
  non-empty value across fragments (repeating the same slug is fine) and binds
  the whole import to that org. The `organizations` list (the platform org
  directory) is a separate section — it declares orgs with their members and IdP
  mappings, concatenates like any list section, and does **not** create an
  `organization` binding on its own. The validator rejects `orgs/<other>/...`
  secret folders that fall outside a declared organization's namespace.
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
  - id: hegemony-demo-default
    source_dir: src/bundles
    output: dist/10-meridian.single.yaml
  - id: another-example
    source_dir: src/another-example
    output: dist/another-example.single.yaml
```

A bundle that binds to a non-default org sets `organization: <slug>` and, if the
org is not seeded by the platform, is declared in the `organizations` directory
of the first-imported bundle. Prefix the `output` filename so the bootstrap
imports directories before the orgs that depend on them.

Then run:

```bash
uv run python scripts/build.py
uv run python scripts/build.py --check
uv run python scripts/validate.py
```
