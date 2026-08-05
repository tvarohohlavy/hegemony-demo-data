# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Guard against a stray apostrophe inside a multi-line ``sh -c '...'`` block.

A literal apostrophe inside a single-quoted shell block closes the quote early
and silently truncates everything after it. In a ``container.run`` flow step
that drops the tail of the command -- often the line that starts the
long-running process -- so the container exits or restart-loops with no obvious
error in the logs. This exact bug wedged the lab bastion (the truncation landed
just before ``sshd``/``microsocks`` started), so lint the flow bundles for it.
"""

from __future__ import annotations

import unittest
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"
# Every bundle root, not just src/bundles: the per-organization roots
# (bundles-acme, bundles-globex, …) carry container.run steps of their own, and
# an apostrophe inside one of their sh -c blocks truncates the script exactly
# the same way.
BUNDLE_ROOTS = sorted(path for path in SRC.glob("bundles*") if path.is_dir())


def offending_lines(text: str) -> list[tuple[int, str]]:
    """Return (lineno, line) for apostrophes inside a multi-line sh -c block.

    A block opens on a line that ends with the ``sh -c '`` opener (nothing after
    the quote, i.e. a multi-line single-quoted script) and closes on the next
    line that is just the lone closing quote. Balanced one-liners such as
    ``vtysh -c 'show version'`` never open a block and are ignored.
    """
    inside = False
    offenders: list[tuple[int, str]] = []
    for lineno, line in enumerate(text.splitlines(), 1):
        if not inside:
            if line.rstrip().endswith("sh -c '"):
                inside = True
            continue
        if line.strip() == "'":
            inside = False
            continue
        if "'" in line:
            offenders.append((lineno, line.strip()))
    return offenders


class FlowShellQuotingTests(unittest.TestCase):
    def test_no_apostrophe_inside_single_quoted_sh_c_blocks(self) -> None:
        for path in sorted(p for root in BUNDLE_ROOTS for p in root.glob("*.yaml")):
            with self.subTest(bundle=path.name):
                offenders = offending_lines(path.read_text(encoding="utf-8"))
                self.assertEqual(
                    offenders,
                    [],
                    f"{path.name}: apostrophe inside a single-quoted `sh -c` "
                    f"block truncates the script at these lines: {offenders}",
                )


if __name__ == "__main__":
    unittest.main()
