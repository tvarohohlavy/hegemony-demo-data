#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Build the generated Hegemony demo single-YAML bundle."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

import yaml

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "manifest.yaml"

RESOURCE_ORDER = [
    "secrets",
    "secret_backends",
    "sites",
    "devices",
    "git_repositories",
    "inventory_providers",
    "flows",
    "flow_attachments",
    "variables",
    "file_repositories",
    "notification_destinations",
    "schedules",
    "webhooks",
    "flow_subscriptions",
    "permission_overrides",
]

RESERVED_KEYS = {"schema_version", "exported_at"}
KNOWN_TOP_LEVEL_KEYS = {*RESERVED_KEYS, *RESOURCE_ORDER, "flow_defaults"}


@dataclass(frozen=True)
class BundleConfig:
    id: str
    source_dir: Path
    output: Path


def _repo_path(value: str, *, field_name: str) -> Path:
    if not value or Path(value).is_absolute():
        raise ValueError(f"manifest.yaml: {field_name} must be a non-empty relative path")
    path = (ROOT / value).resolve()
    try:
        path.relative_to(ROOT)
    except ValueError as exc:
        raise ValueError(f"manifest.yaml: {field_name} must stay inside the repository") from exc
    return path


def load_manifest() -> list[BundleConfig]:
    raw = yaml.safe_load(MANIFEST_PATH.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("manifest.yaml: expected a YAML mapping")
    if raw.get("schema_version") != 1:
        raise ValueError("manifest.yaml: schema_version must be 1")

    bundles = raw.get("bundles")
    if not isinstance(bundles, list) or not bundles:
        raise ValueError("manifest.yaml: bundles must be a non-empty list")

    configs: list[BundleConfig] = []
    seen_ids: set[str] = set()
    for index, item in enumerate(bundles, start=1):
        if not isinstance(item, dict):
            raise ValueError(f"manifest.yaml: bundles[{index}] must be a mapping")
        bundle_id = item.get("id")
        if not isinstance(bundle_id, str) or not bundle_id.strip():
            raise ValueError(f"manifest.yaml: bundles[{index}].id must be a non-empty string")
        if bundle_id in seen_ids:
            raise ValueError(f"manifest.yaml: duplicate bundle id {bundle_id!r}")
        seen_ids.add(bundle_id)
        source_dir = item.get("source_dir")
        output = item.get("output")
        if not isinstance(source_dir, str):
            raise ValueError(f"manifest.yaml: bundle {bundle_id!r} source_dir must be a string")
        if not isinstance(output, str):
            raise ValueError(f"manifest.yaml: bundle {bundle_id!r} output must be a string")
        configs.append(
            BundleConfig(
                id=bundle_id,
                source_dir=_repo_path(source_dir, field_name=f"bundle {bundle_id!r} source_dir"),
                output=_repo_path(output, field_name=f"bundle {bundle_id!r} output"),
            )
        )
    return configs


def load_fragment(path: Path) -> dict[str, Any]:
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"{path}: expected a YAML mapping")
    if raw.get("schema_version") != 2:
        raise ValueError(f"{path}: schema_version must be 2")
    unknown = sorted(set(raw) - KNOWN_TOP_LEVEL_KEYS)
    if unknown:
        raise ValueError(f"{path}: unsupported top-level keys: {', '.join(unknown)}")
    return raw


def merge_fragments(config: BundleConfig) -> dict[str, Any]:
    files = sorted({*config.source_dir.glob("*.yaml"), *config.source_dir.glob("*.yml")})
    if not files:
        raise FileNotFoundError(f"No YAML fragments found in {config.source_dir}")

    sections: dict[str, Any] = {}
    for path in files:
        fragment = load_fragment(path)
        for key, value in fragment.items():
            if key in {"schema_version", "exported_at"}:
                continue
            if isinstance(value, list):
                sections.setdefault(key, []).extend(value)
            elif isinstance(value, dict):
                sections.setdefault(key, {}).update(value)
            elif value is not None:
                raise ValueError(f"{path}: unsupported top-level value for {key!r}")

    merged: dict[str, Any] = {"schema_version": 2}
    for key in RESOURCE_ORDER:
        if key in sections:
            merged[key] = sections.pop(key)
    for key in sorted(sections):
        merged[key] = sections[key]
    return merged


def render_bundle(bundle: dict[str, Any], config: BundleConfig) -> str:
    body = yaml.safe_dump(
        bundle,
        sort_keys=False,
        allow_unicode=True,
        default_flow_style=False,
        width=120,
    )
    source = config.source_dir.relative_to(ROOT)
    copyright_marker = "SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>"
    license_marker = "SPDX-License-" "Identifier: AGPL-3.0-or-later"
    return (
        f"# {copyright_marker}\n"
        "#\n"
        f"# {license_marker}\n"
        "# Generated by scripts/build.py; edit "
        f"{source}/*.yaml instead.\n"
        + body
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify generated output is current")
    parser.add_argument("--bundle", help="build only the named manifest bundle")
    args = parser.parse_args()

    configs = load_manifest()
    if args.bundle:
        configs = [config for config in configs if config.id == args.bundle]
        if not configs:
            print(f"Unknown bundle {args.bundle!r}", file=sys.stderr)
            return 2

    failed = False
    for config in configs:
        rendered = render_bundle(merge_fragments(config), config)
        if not args.check:
            config.output.parent.mkdir(parents=True, exist_ok=True)
            config.output.write_text(rendered, encoding="utf-8")
            print(f"wrote {config.output.relative_to(ROOT)}")
            continue

        current = config.output.read_text(encoding="utf-8") if config.output.exists() else ""
        if current != rendered:
            print(f"{config.output} is not up to date; run scripts/build.py", file=sys.stderr)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
