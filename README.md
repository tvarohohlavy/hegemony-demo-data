<!--
SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Hegemony Demo Data

Generated demo Configuration Exchange data for Hegemony instance bootstrap.

This repository owns source YAML fragments and committed generated single-YAML
bundles. Hegemony can load the generated bundle through its generic instance
bootstrap path by mounting `dist/` into the API container at `/bootstrap`.

## What the demo shows

The data is built around a small set of network-operations use cases for a
fictional operator, **Meridian Networks**, so that each platform capability
appears as part of a story rather than a feature checklist:

- **Global variables** — organisation facts (NOC contact, maintenance window,
  shared service addresses, Gitea location) consumed by flows, container
  environments, and step output, including a nested `{{ vars.* }}` reference.
- **Secrets** — vault-backed SSH credentials for the estate and the lab routers,
  Gitea credentials, webhook HMAC material, and Shoutrrr URLs.
- **Git repositories & the git inventory provider** — the eleven lab routers,
  four Linux endpoint hosts, and their four-site hierarchy (two datacenters +
  two branches) are defined in [`demo-inventory/`](demo-inventory) and synced
  into Hegemony by a Git inventory provider that reads this public repository
  over HTTPS.
- **Flow forms** — every flow ships a launch form (`interface_graph`). "Ops:
  Announce service prefix" is the flagship: it exercises number/text/bool/enum
  fields, cross-field templated defaults, input validation, a conditional
  (`visible_when`) field, and a device picker, in front of an approval gate.
- Plus schedules, inbound webhooks, notification destinations/subscriptions,
  containerised steps, evidence collection/comparison, and a self-contained
  virtual lab (containerlab + FRR) the device flows run against for real.

Start by running **"Lab: Provision and tear down demo datacenter"** — it builds
the lab images, deploys a multi-area OSPF topology of eleven routers and four
Linux endpoint hosts (two lab datacenters with backbone ABRs plus two
branches), attaches the lab network to the
workers, and (optionally) stands up a local Gitea for config backups, then parks
on an approval gate **with no expiry**. While the run is held there the lab keeps
running, so you can SSH to the routers and exercise the other flows against them;
approving the gate tears the lab down (rejecting leaves it up). It doubles as an
example of a long-running, human-in-the-loop run.

## Layout

```text
manifest.yaml
src/bundles/          # human-edited Configuration Exchange fragments
src/files/            # attachment payloads inlined at build time (content_file)
demo-inventory/       # git-provider inventory tree (sites/ + devices/)
dist/hegemony-demo.single.yaml
scripts/build.py
scripts/validate.py
```

- `manifest.yaml` declares generated bundles.
- `src/bundles/` contains human-edited Configuration Exchange fragments, merged
  in lexical filename order.
- `src/files/` holds larger attachment payloads (Dockerfile, containerlab
  topology, FRR configs, scripts) referenced from flow attachments via
  `content_file:` and inlined into the bundle at build time.
- `demo-inventory/` is the Git inventory source of truth read by the
  `lab-inventory` provider (`schema_version: 1` site/device records).
- `dist/` contains generated bundles committed for direct mounting.
- `scripts/build.py` performs deterministic merge, `content_file` inlining, and
  sync checks.
- `scripts/validate.py` checks bundle references, secret-ref patterns, step
  handler ids, and the `demo-inventory/` tree.

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

`--check` fails when `dist/hegemony-demo.single.yaml` is not in sync with the source fragments. `validate.py` fails on broken flow, site, destination, variable, or bundled `vault://` references, on unknown step-handler ids, and on a malformed `demo-inventory/` tree. The pre-commit hook regenerates the bundle automatically.

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
- The flows use **namespaced step-handler ids** (`general.noop`, `container.run`,
  `netcli.*`, `evidence.*`, `probe.*`), which require a platform build carrying
  the `hegemony-step-plugins` wheels (the handler-namespace migration).
- The `lab-inventory` git provider references its Git repository **by name**
  (`git_repository: hegemony-demo-data`); the name is resolved to the target
  instance's repository UUID on import. This requires a Hegemony build with
  name-based inventory-provider git references.
- Because Hegemony refuses git URLs on private/internal hosts (SSRF protection),
  the git inventory source is this **public** repository over HTTPS. The
  `demo-inventory/` tree must therefore exist on the default branch of the
  repository the provider points at for the sync to succeed.
- The `config-backups` git repository points at the demo Gitea over `http://`
  on the Docker host so operators can browse pushed backups in Hegemony's
  repository browser. This needs `HEGEMONY_GIT_ALLOW_INSECURE_URLS=true` (the
  demo compose overlay sets it) and only works after the lab bootstrap flow has
  deployed Gitea.
- For reproducible installs, consume a tagged release of this repository (see
  [docs/release.md](docs/release.md)) instead of tracking `main`. Hegemony's
  CI pins a specific commit of this repository for its bundle contract check.

## Docs

- [Repository structure](docs/structure.md)
- [Release process](docs/release.md)
- [Contributing](CONTRIBUTING.md)
- [Contributor License Agreement](CLA.md)
- [Licensing](LICENSING.md)
