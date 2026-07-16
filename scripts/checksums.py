#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Generate SHA256SUMS for releasable assets (bundles + the installer).

Run this after any release-time stamping of install.sh so the recorded digest
matches the asset that is actually uploaded.
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
DIST_DIR = ROOT / "dist"


def main() -> int:
    files = sorted(DIST_DIR.glob("*.yaml"))
    if not files:
        raise FileNotFoundError(f"No releasable YAML bundles found in {DIST_DIR}")

    # The installer is a released, versioned asset too.
    installer = ROOT / "install.sh"
    if installer.is_file():
        files.append(installer)

    for path in files:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        print(f"{digest}  {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
