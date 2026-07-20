<!--
SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Demo Walkthrough — a guided tour of the Meridian MSP

This is a scripted tour of the demo. Follow it top to bottom and you will
exercise the whole platform — multi-tenancy, RBAC, the shared org, flows,
approvals, notifications, and the containerlab — by playing the people in the
story rather than clicking around at random.

## The story

**Meridian Networks** started as a single network operator and grew into a
**Managed Service Provider**. It now runs network automation for itself and
for two client tenants, and publishes a shared "golden standards" org that
every tenant inherits.

| Organization | Who they are |
| --- | --- |
| **Meridian Networks** (`default`) | The MSP's own network — the live containerlab lab, backups, change automation |
| **Shared Standards** (`shared`) | The golden baseline (NTP/DNS/syslog, approved images, a compliance flow) every org reads, curated only by Meridian |
| **Acme Retail** (`acme`) | A client tenant with its own store network — and its own NTP appliance |
| **Globex Manufacturing** (`globex`) | A second client tenant that takes the standards as-is |

### The cast (log in with these; password `hegemony`, changed on first login)

| Username | Role in the story | What they can reach |
| --- | --- | --- |
| `admin` | Meridian platform administrator | Every organization |
| `meridian-noc` | Meridian NOC engineer | `default` + `shared` (operator) |
| `acme-admin` | Acme's network administrator | `acme` (admin), `shared` (read-only) |
| `globex-admin` | Globex's network administrator | `globex` (admin), `shared` (read-only) |
| `consultant` | Contractor working both clients | `acme` + `globex` (operator), `shared` (read-only) |
| `compliance` | Cross-tenant compliance auditor | **All four** orgs (read-only) |

(The original `operator` / `auditor` / `viewer` users still exist and live in
the `default` org.)

Roles come from Keycloak group membership: each user's groups are mapped to org
roles at login (`HEGEMONY_ORG_IDP_SYNC` is on in the demo). Nothing is
hand-assigned per user in the database.

---

## Act 0 — Bring it up

```bash
task compose:demo:local:up     # build from source, or:
# curl -fsSL https://github.com/tvarohohlavy/hegemony-demo-data/releases/latest/download/install.sh | sh
```

Open the UI (default <http://localhost:8080>). Log in as **`admin`** and set a
new password when prompted.

---

## Act 1 — The platform admin sees everything

Playing **`admin`** (Meridian's platform administrator).

1. Open the **organization switcher** (top of the sidebar). You see all four
   orgs; **Shared Standards** carries a **Shared** badge.
2. Go to **Settings → Organizations**. Note that `shared` is active and flagged
   as the shared organization — that flag is what makes its resources readable
   from every other org.
3. Open **Acme Retail → Members** and **→ IdP Mappings**. The memberships were
   granted from the `/Acme-Admins`, `/Consultants` and `/Compliance` group
   mappings — nobody was added by hand except the consultant's one manual
   membership in the shared org.

> **Feature:** platform-admin cross-org visibility, the enabled shared org, and
> IdP-group→org-role mappings seeded from the config bundle.

---

## Act 2 — Meridian runs its own network

Switch the org picker to **Meridian Networks (`default`)** (still as `admin`, or
log in as **`meridian-noc`** / the original `operator`).

1. **Flows → "Lab: Provision and tear down demo datacenter" → Run.** This builds
   the images and stands up the containerlab (eleven FRR routers, a Gitea, and
   the endpoint hosts). It parks at an approval gate at the end so the lab stays
   up for you to explore; the NOC is emailed when it parks (see MailHog at the
   port your env prints).
2. While it runs, watch the **Run detail** graph: parallel branches, live step
   events, and the container steps executing.
3. When the lab is up, run **"Net: Lab routing health check"** against the four
   synced lab routers (pick them as targets). It probes reachability and asserts
   OSPF neighbors are Full.
4. Run **"Ops: Announce service prefix"**. It **pauses at a human approval
   gate** — approve or reject it from the Run detail page (or the Approvals
   list). Approvals and the run outcome email the NOC.
5. Run **"Ops: Backup lab configs to Git"** to push device configs to the demo
   Gitea; the backup manifest records the org standards — note it prints
   `ntp=192.0.2.123`, resolved from the **shared** org (see Act 4 for the
   contrast).

> **Feature:** the containerlab, parallel flow execution, approval gates,
> notifications, git-backed backups, and shared-variable resolution for the
> MSP's own org.

---

## Act 3 — Curating the golden standards

Still as **`meridian-noc`**, switch the org picker to **Shared Standards
(`shared`)**. Meridian NOC is an *operator* here, so it may edit.

1. **Variables** — the golden `NTP_PRIMARY` / `DNS_PRIMARY` / `SYSLOG_PRIMARY`
   and `APPROVED_CONTAINER_IMAGES`. Edit `NTP_PRIMARY` to a new address.
2. **Secrets** — a read-only `shared-monitoring-token` under
   `orgs/shared/secrets/…`.
3. **File Repositories** — the shared **Golden Artifacts** object store.
4. **Flows** — three golden flows Meridian publishes for every tenant, each
   **runnable with no form input**:
   - **"Shared: Compliance baseline report"** — a shell step that renders the
     effective standards,
   - **"Shared: Ansible config audit"** — an **Ansible** playbook (localhost)
     that asserts the standards are set and writes a PASS/FAIL report,
   - **"Shared: Terraform network baseline plan"** — a provider-less
     **Terraform** init + plan that renders the baseline as a plan output.

   Each container step carries **no inline script**: it mounts a file
   attachment (the playbook, the `.tf`, the report script) and passes every
   value as an environment variable — open a step to see the mounted files.

> **Feature:** the shared org is a normal, editable org *for its own members*
> while everyone else only reads it — and golden **Ansible** and **Terraform**
> activities driven by mounted file attachments, runnable with zero inputs.

---

## Act 4 — A client tenant: Acme (isolation + override)

Log out. Log in as **`acme-admin`**.

1. Open the **org switcher**: you see **only Acme Retail and Shared Standards** —
   not Meridian's own org, not Globex. **Tenant isolation.**
2. In **Acme Retail**, browse **Sites / Devices** — Acme's own store estate,
   and **Secrets** — only `orgs/acme/…`, never another tenant's.
3. **Flows → "Acme: Store standards check" → Run.** The run form opens with
   Acme's **store routers already preselected** as targets — the flow ships
   preselected default targets that resolved to Acme's devices on import
   (they travel as portable device names in the bundle). Read the artifact:
   - `NTP` resolves to **`10.20.0.123`** — Acme's store-local override,
   - `DNS` / `syslog` fall through to the **shared** golden values.
   **Per-org variable precedence** and **preselected targets**, live.
4. Now run a **shared** flow from Acme — try **"Shared: Ansible config audit"**
   or **"Shared: Terraform network baseline plan"** (both carry a **Shared**
   badge, and both run with **no inputs**). They run **as Acme**, so the Ansible
   report and the Terraform plan output both show Acme's NTP override while
   reading the shared DNS/syslog. **A shared Ansible/Terraform activity executing
   as the consumer org.**
5. Open a flow's config field and use the **variable picker** (the `{{ }}`
   button): the shared golden variables appear, marked as belonging to the
   shared organization.
6. Try to **edit** a shared variable or the shared flow: it is **read-only** for
   Acme (the Shared badge, no save). Acme reads the standards; it cannot change
   them.

> **Feature:** tenant isolation, per-org override precedence, shared-org
> read-through with differentiation, and the read-only guard.

---

## Act 5 — The other tenant: Globex (the contrast)

Log out. Log in as **`globex-admin`**.

1. The org switcher shows **only Globex and Shared Standards**.
2. **Flows → "Globex: Plant standards check" → Run.** Globex defines **no**
   override, so every value — NTP included — comes straight from the shared
   golden standards. Put this artifact next to Acme's: same shared baseline, one
   overridden, one not.

> **Feature:** the shared read-through with and without a per-org override, side
> by side.

---

## Act 6 — One person, two clients: the consultant

Log out. Log in as **`consultant`**.

1. The org switcher shows **Acme, Globex and Shared Standards** — the consultant
   is an *operator* in both client tenants at once.
2. Switch between **Acme** and **Globex** and run each tenant's standards flow.
   Same person, different org context each time, scoped to whatever org is
   active.

> **Feature:** a single identity holding different roles across multiple orgs.

---

## Act 7 — The auditor sees all, changes nothing

Log out. Log in as **`compliance`**.

1. The org switcher shows **all four organizations** — the auditor is a member
   (read-only) of every one.
2. Switch through them: everything is visible, every create/edit/run control is
   disabled. Open **Audit Logs** to review who did what during this tour.

> **Feature:** a cross-org, read-only role for compliance.

---

## Act 8 — Tear it down

Back as an operator in the `default` org, approve the parked teardown gate on
**"Lab: Provision and tear down demo datacenter"** to destroy the lab cleanly.
To wipe everything (volumes and all flow containers):

```bash
task compose:demo:reset
```

---

## What you just exercised

Multiple organizations and tenant isolation · an enabled shared org with golden
read-through and a differentiation badge · per-org variable override precedence
· shared-secret cross-org read and tenant secret confinement · IdP
group→org-role mappings and mixed manual/IdP membership · one user with
different roles per org · a cross-org auditor · shared **Ansible** and
**Terraform** activities executing as the consumer org, driven by mounted file
attachments and runnable with no inputs · flows with **preselected default
targets** that survive import as portable device names · the containerlab,
parallel execution,
approval gates, notifications, git backups, file repositories, and inventory
providers.
