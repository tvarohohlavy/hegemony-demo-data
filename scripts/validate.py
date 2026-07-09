#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Validate semantic references in Hegemony demo-data bundles."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

import yaml

from build import ROOT, BundleConfig, load_manifest, merge_fragments

SECRET_CALL_RE = re.compile(r"secret\(\s*['\"]([^'\"]+)['\"]\s*\)")
VARS_REF_RE = re.compile(
    r"vars(?:\[['\"]([^'\"]+)['\"]\]|\.([A-Za-z_][A-Za-z0-9_]*))"
)
TEMPLATE_REF_RE = re.compile(r"{{\s*(env|file|secret)\s*\(")

NAME_UNIQUE_SECTIONS = {
    "devices",
    "flows",
    "git_repositories",
    "inventory_providers",
    "notification_destinations",
    "schedules",
    "secrets",
    "variables",
    "webhooks",
}

# Namespaced step-handler ids shipped by the hegemony-step-plugins wheels. The
# API validates flow graphs against its live registry and hard-fails unknown
# handler ids on import (there is no legacy-slug resolution), so a bundle that
# names a non-existent handler is rejected. Keep this list in sync with the
# installed plugin wheels.
KNOWN_HANDLERS = {
    "general.noop",
    "general.sleep",
    "container.run",
    "netcli.execute",
    "netcli.collect_evidence",
    "netcli.poll_until",
    "evidence.assert",
    "evidence.compare",
    "probe.connectivity",
    "probe.wait_reachable",
    "probe.http",
    "probe.dns",
    "shell.execute",
    "flow.run",
    "flow.notify",
    "flow.git_sync",
    "monitor.connectivity",
    "monitor.start",
    "monitor.stop",
    "cisco.iosxe.upgrade.preflight",
    "cisco.iosxe.upgrade.stage",
    "cisco.iosxe.upgrade.install",
    "cisco.iosxe.upgrade.verify",
    "cisco.iosxe.upgrade.cleanup",
}


class Validator:
    def __init__(self, bundle_id: str, bundle: dict[str, Any]) -> None:
        self.bundle_id = bundle_id
        self.bundle = bundle
        self.errors: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(f"{self.bundle_id}: {message}")

    def validate(self) -> list[str]:
        self._validate_unique_names()
        site_paths = self._validate_sites()
        flow_names = self._names("flows")
        destination_names = self._names("notification_destinations")
        secret_paths = self._validate_secret_paths()

        self._validate_devices(site_paths)
        self._validate_flow_references(flow_names)
        self._validate_subscription_references(flow_names, destination_names)
        self._validate_template_references(secret_paths)
        self._validate_ref_fields()
        self._validate_handlers()
        return self.errors

    def _items(self, section: str) -> list[dict[str, Any]]:
        items = self.bundle.get(section, [])
        if not isinstance(items, list):
            self.error(f"{section} must be a list")
            return []
        return [item for item in items if isinstance(item, dict)]

    def _names(self, section: str) -> set[str]:
        names: set[str] = set()
        for item in self._items(section):
            name = item.get("name")
            if isinstance(name, str) and name:
                names.add(name)
        return names

    def _validate_unique_names(self) -> None:
        for section in sorted(NAME_UNIQUE_SECTIONS):
            seen: set[str] = set()
            for item in self._items(section):
                name = item.get("name")
                if not isinstance(name, str) or not name:
                    self.error(f"{section} item is missing a non-empty name")
                    continue
                if name in seen:
                    self.error(f"{section} has duplicate name {name!r}")
                seen.add(name)

    def _validate_sites(self) -> set[str]:
        paths: set[str] = set()
        for site in self._items("sites"):
            name = site.get("name")
            parent = site.get("parent")
            if not isinstance(name, str) or not name:
                self.error("sites item is missing a non-empty name")
                continue
            if parent is not None and not isinstance(parent, str):
                self.error(f"site {name!r} has non-string parent")
                continue
            path = f"{parent}/{name}" if parent else name
            if path in paths:
                self.error(f"sites has duplicate path {path!r}")
            paths.add(path)

        for site in self._items("sites"):
            name = site.get("name")
            parent = site.get("parent")
            if isinstance(parent, str) and parent not in paths:
                self.error(f"site {name!r} references missing parent {parent!r}")
        return paths

    def _validate_secret_paths(self) -> set[str]:
        paths: set[str] = set()
        for secret in self._items("secrets"):
            name = secret.get("name")
            folder = secret.get("folder")
            values = secret.get("values")
            if not isinstance(folder, str) or not folder.strip("/"):
                self.error(f"secret {name!r} is missing a non-empty folder")
                continue
            if not isinstance(values, dict) or not values:
                self.error(f"secret {name!r} must define at least one value")
                continue
            for key in values:
                if not isinstance(key, str) or not key:
                    self.error(f"secret {name!r} has an invalid value key")
                    continue
                path = f"{folder.strip('/')}/{key}"
                if path in paths:
                    self.error(f"secrets define duplicate vault path {path!r}")
                paths.add(path)
        return paths

    def _validate_devices(self, site_paths: set[str]) -> None:
        for device in self._items("devices"):
            name = device.get("name")
            site = device.get("site")
            if site not in site_paths:
                self.error(f"device {name!r} references missing site {site!r}")

    def _validate_flow_references(self, flow_names: set[str]) -> None:
        for attachment in self._items("flow_attachments"):
            flow = attachment.get("flow")
            if flow not in flow_names:
                self.error(
                    f"flow attachment {attachment.get('filename')!r} references missing flow {flow!r}"
                )

        for schedule in self._items("schedules"):
            flow = schedule.get("flow")
            if flow not in flow_names:
                self.error(f"schedule {schedule.get('name')!r} references missing flow {flow!r}")

        for webhook in self._items("webhooks"):
            flows = webhook.get("flows") or []
            if not isinstance(flows, list):
                self.error(f"webhook {webhook.get('name')!r} has non-list flows")
                continue
            for flow in flows:
                if flow not in flow_names:
                    self.error(f"webhook {webhook.get('name')!r} references missing flow {flow!r}")

    def _validate_subscription_references(
        self, flow_names: set[str], destination_names: set[str]
    ) -> None:
        for subscription in self._items("flow_subscriptions"):
            flow = subscription.get("flow")
            destination = subscription.get("destination")
            if flow not in flow_names:
                self.error(f"flow subscription references missing flow {flow!r}")
            if destination not in destination_names:
                self.error(
                    f"flow subscription references missing destination {destination!r}"
                )

    def _validate_template_references(self, secret_paths: set[str]) -> None:
        variables = self._names("variables")
        for location, value in self._walk_strings(self.bundle):
            for match in SECRET_CALL_RE.finditer(value):
                ref = match.group(1)
                scheme, sep, target = ref.partition("://")
                if sep and scheme == "vault" and target.strip("/") not in secret_paths:
                    self.error(f"{location} references missing bundled secret {ref!r}")
            for match in VARS_REF_RE.finditer(value):
                name = match.group(1) or match.group(2)
                if name not in variables:
                    self.error(f"{location} references missing variable {name!r}")

    def _validate_handlers(self) -> None:
        for flow in self._items("flows"):
            name = flow.get("name")
            definition = flow.get("definition")
            if not isinstance(definition, dict):
                continue
            graph = definition.get("graph")
            if not isinstance(graph, dict):
                continue
            nodes = graph.get("nodes")
            if not isinstance(nodes, list):
                continue
            for node in nodes:
                if not isinstance(node, dict):
                    continue
                handler = node.get("handler")
                if handler is None:
                    continue
                if handler not in KNOWN_HANDLERS:
                    self.error(
                        f"flow {name!r} node {node.get('id')!r} uses unknown handler {handler!r}"
                    )

    def _validate_ref_fields(self) -> None:
        for location, key, value in self._walk_mapping_values(self.bundle):
            if not isinstance(value, str) or not value.strip():
                continue
            if key.endswith("_ref") and not TEMPLATE_REF_RE.search(value):
                self.error(f"{location} should use env(), file(), or secret() template syntax")
            if key == "url_secret" and not TEMPLATE_REF_RE.search(value):
                self.error(f"{location} should use env(), file(), or secret() template syntax")

    def _walk_strings(self, value: Any, location: str = "$") -> list[tuple[str, str]]:
        found: list[tuple[str, str]] = []
        if isinstance(value, dict):
            for key, item in value.items():
                found.extend(self._walk_strings(item, f"{location}.{key}"))
        elif isinstance(value, list):
            for index, item in enumerate(value):
                found.extend(self._walk_strings(item, f"{location}[{index}]"))
        elif isinstance(value, str):
            found.append((location, value))
        return found

    def _walk_mapping_values(
        self, value: Any, location: str = "$"
    ) -> list[tuple[str, str, Any]]:
        found: list[tuple[str, str, Any]] = []
        if isinstance(value, dict):
            for key, item in value.items():
                next_location = f"{location}.{key}"
                if isinstance(key, str):
                    found.append((next_location, key, item))
                found.extend(self._walk_mapping_values(item, next_location))
        elif isinstance(value, list):
            for index, item in enumerate(value):
                found.extend(self._walk_mapping_values(item, f"{location}[{index}]"))
        return found


def _derive_site_path(sites_root: Path, site_file: Path) -> str:
    """Derive a git-inventory site path from a site file's location.

    Mirrors the git inventory plugin: a file whose stem equals its parent
    directory name identifies that directory (``sites/emea/emea.yaml`` ->
    ``emea``); any other file is a leaf site under its directory
    (``sites/emea/nl/ams01.yaml`` -> ``emea/nl/ams01``).
    """
    rel_dir = site_file.parent.relative_to(sites_root)
    dir_path = rel_dir.as_posix()
    if site_file.stem == site_file.parent.name:
        return dir_path
    return f"{dir_path}/{site_file.stem}" if dir_path != "." else site_file.stem


def validate_inventory_tree(root: Path) -> list[str]:
    """Validate the git-provider inventory tree under ``demo-inventory/``.

    Applies the same fail-closed rules the git inventory plugin enforces at
    runtime so the seeded source of truth cannot silently drift: schema_version
    1, ``external_id`` equal to the file stem, required device fields, resolved
    site references, and templated (never literal) access-config refs.
    """
    errors: list[str] = []
    if not root.is_dir():
        return errors

    site_paths: set[str] = set()
    sites_root = root / "sites"
    for site_file in sorted(sites_root.rglob("*.y*ml")) if sites_root.is_dir() else []:
        try:
            doc = yaml.safe_load(site_file.read_text(encoding="utf-8"))
        except yaml.YAMLError as exc:
            errors.append(f"{site_file}: invalid YAML: {exc}")
            continue
        rel = site_file.relative_to(root)
        if not isinstance(doc, dict):
            errors.append(f"{rel}: expected a YAML mapping")
            continue
        if doc.get("schema_version") != 1:
            errors.append(f"{rel}: site schema_version must be 1")
        if doc.get("kind") != "site":
            errors.append(f"{rel}: kind must be 'site'")
        if doc.get("external_id") != site_file.stem:
            errors.append(
                f"{rel}: external_id {doc.get('external_id')!r} must equal file stem {site_file.stem!r}"
            )
        site_paths.add(_derive_site_path(sites_root, site_file))

    devices_root = root / "devices"
    for device_file in sorted(devices_root.rglob("*.y*ml")) if devices_root.is_dir() else []:
        try:
            doc = yaml.safe_load(device_file.read_text(encoding="utf-8"))
        except yaml.YAMLError as exc:
            errors.append(f"{device_file}: invalid YAML: {exc}")
            continue
        rel = device_file.relative_to(root)
        if not isinstance(doc, dict):
            errors.append(f"{rel}: expected a YAML mapping")
            continue
        if doc.get("schema_version") != 1:
            errors.append(f"{rel}: device schema_version must be 1")
        if doc.get("kind") != "device":
            errors.append(f"{rel}: kind must be 'device'")
        if doc.get("external_id") != device_file.stem:
            errors.append(
                f"{rel}: external_id {doc.get('external_id')!r} must equal file stem {device_file.stem!r}"
            )
        if not doc.get("mgmt_host"):
            errors.append(f"{rel}: device is missing mgmt_host")
        site = doc.get("site")
        if site is not None and site not in site_paths:
            errors.append(f"{rel}: references unknown site {site!r}")
        errors.extend(_check_access_refs_templated(rel, doc.get("access_config")))

    return errors


def _check_access_refs_templated(location: Any, access_config: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(access_config, dict):
        return errors
    for section in access_config.values():
        if not isinstance(section, dict):
            continue
        for key, value in section.items():
            if key.endswith("_ref") and isinstance(value, str) and not TEMPLATE_REF_RE.search(value):
                errors.append(f"{location}: {key} must use env()/file()/secret() template syntax")
    return errors


def _selected_configs(bundle_id: str | None) -> list[BundleConfig]:
    configs = load_manifest()
    if bundle_id is None:
        return configs
    selected = [config for config in configs if config.id == bundle_id]
    if not selected:
        raise ValueError(f"Unknown bundle {bundle_id!r}")
    return selected


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", help="validate only the named manifest bundle")
    args = parser.parse_args()

    try:
        configs = _selected_configs(args.bundle)
        errors: list[str] = []
        for config in configs:
            errors.extend(Validator(config.id, merge_fragments(config)).validate())
        errors.extend(validate_inventory_tree(ROOT / "demo-inventory"))
    except Exception as exc:
        print(f"validate.py: {exc}", file=sys.stderr)
        return 2

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    for config in configs:
        output = Path(config.output)
        print(f"validated {output}")
    print(f"validated {ROOT / 'demo-inventory'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
