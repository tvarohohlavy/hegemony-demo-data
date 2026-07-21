# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Regression tests for scripts/validate.py shared-org resolution."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import validate  # noqa: E402  (import after sys.path shim)


class SharedReferenceUniverseTests(unittest.TestCase):
    """The shared universe must come only from a genuine boolean flag."""

    @staticmethod
    def _bundles(is_shared, is_active):
        return {
            "orgs": {
                "organizations": [
                    {"slug": "shared", "is_shared": is_shared, "is_active": is_active}
                ]
            },
            "shared_res": {
                "organization": "shared",
                "variables": [{"name": "NTP_PRIMARY"}],
            },
        }

    def test_boolean_true_flags_publish_shared_universe(self):
        slug, variables, secrets = validate._shared_reference_universe(
            self._bundles(True, True)
        )
        self.assertEqual(slug, "shared")
        self.assertIn("NTP_PRIMARY", variables)

    def test_quoted_false_flag_yields_no_shared_universe(self):
        # YAML `is_shared: "false"` parses to the truthy string "false"; the
        # validator must not accept it as a shared org, or a malformed flag
        # would conjure a universe that satisfies cross-tenant references.
        self.assertEqual(
            validate._shared_reference_universe(self._bundles("false", "true")),
            (None, set(), set()),
        )

    def test_quoted_true_flag_yields_no_shared_universe(self):
        # A quoted "true" is likewise a string, not a boolean, and is rejected.
        self.assertEqual(
            validate._shared_reference_universe(self._bundles("true", "true")),
            (None, set(), set()),
        )


if __name__ == "__main__":
    unittest.main()
