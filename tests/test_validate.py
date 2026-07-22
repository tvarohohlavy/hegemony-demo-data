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
    """The shared universe must come only from genuine boolean flags."""

    @staticmethod
    def _bundles(*, is_shared: object, is_active: object) -> dict[str, object]:
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

    def test_boolean_true_flags_publish_shared_universe(self) -> None:
        self.assertEqual(
            validate._shared_reference_universe(
                self._bundles(is_shared=True, is_active=True)
            ),
            ("shared", {"NTP_PRIMARY"}, set()),
        )

    def test_quoted_is_shared_string_yields_no_shared_universe(self) -> None:
        # YAML `is_shared: "false"`/`"true"` parses to a truthy string; a genuine
        # is_active must not rescue it, or a malformed flag would conjure a
        # universe that satisfies cross-tenant references. Covers the is_shared
        # `is True` check independently.
        for quoted in ("false", "true"):
            with self.subTest(is_shared=quoted):
                self.assertEqual(
                    validate._shared_reference_universe(
                        self._bundles(is_shared=quoted, is_active=True)
                    ),
                    (None, set(), set()),
                )

    def test_quoted_is_active_string_yields_no_shared_universe(self) -> None:
        # A quoted is_active likewise disqualifies the org even when is_shared is
        # a genuine boolean. Covers the is_active `is True` check independently.
        for quoted in ("false", "true"):
            with self.subTest(is_active=quoted):
                self.assertEqual(
                    validate._shared_reference_universe(
                        self._bundles(is_shared=True, is_active=quoted)
                    ),
                    (None, set(), set()),
                )


if __name__ == "__main__":
    unittest.main()
