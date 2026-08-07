# SPDX-FileCopyrightText: 2025-2026 Jakub Travnik <jakub.travnik@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Seed-object resolution guards in scripts/build.py.

Bucket and object_key become path components under dist/seed-s3, so the
resolver must reject anything that could escape the seed tree (review
finding on PR #13), and the computed metadata must come from the real
artifact bytes.
"""

import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import build  # noqa: E402  (import after sys.path shim)

GOLDEN_SOURCE = "src/files/standards/golden/baseline-config.txt"


def _merged(bucket: str, object_key: str) -> dict:
    return {
        "file_repositories": [
            {
                "name": "Golden Artifacts",
                "bucket": bucket,
                "files": [{"seed_file": GOLDEN_SOURCE, "object_key": object_key}],
            }
        ]
    }


class SeedResolutionGuardTests(unittest.TestCase):
    def test_valid_entry_resolves_metadata_and_dest(self):
        merged = _merged("meridian-golden", "standards/golden/baseline-config.txt")
        seeds = build._resolve_seed_files(merged)
        self.assertEqual(len(seeds), 1)
        entry = merged["file_repositories"][0]["files"][0]
        self.assertEqual(entry["filename"], "baseline-config.txt")
        self.assertEqual(len(entry["sha256"]), 64)
        self.assertGreater(entry["size_bytes"], 0)
        self.assertNotIn("seed_file", entry)
        dest = seeds[0].dest
        self.assertTrue(dest.is_relative_to(build.SEED_S3_DIR))

    def test_bucket_with_separators_or_dot_segments_rejected(self):
        for bucket in ("a/b", "a\\b", ".", ".."):
            with self.assertRaises(ValueError, msg=f"bucket {bucket!r} accepted"):
                build._resolve_seed_files(_merged(bucket, "safe/key.txt"))

    def test_object_key_escapes_rejected(self):
        for object_key in (
            "/absolute.txt",
            "a/../b.txt",
            "..\\windows.txt",
            "a\\b.txt",
            "a//b.txt",
            "a/./b.txt",
        ):
            with self.assertRaises(ValueError, msg=f"object_key {object_key!r} accepted"):
                build._resolve_seed_files(_merged("meridian-golden", object_key))

    def test_duplicate_destination_rejected(self):
        merged = _merged("meridian-golden", "same/key.txt")
        merged["file_repositories"][0]["files"].append(
            {"seed_file": GOLDEN_SOURCE, "object_key": "same/key.txt"}
        )
        with self.assertRaises(ValueError):
            build._resolve_seed_files(merged)

    def test_merge_fragments_can_skip_seed_resolution(self):
        configs = [config for config in build.load_manifest() if "shared" in config.id]
        self.assertEqual(len(configs), 1)
        merged, seeds = build.merge_fragments(configs[0], resolve_seeds=False)
        self.assertEqual(seeds, [])
        entries = merged["file_repositories"][0]["files"]
        # Raw references are kept: nothing was read or hashed.
        self.assertTrue(all("seed_file" in entry for entry in entries))
        self.assertTrue(all("sha256" not in entry for entry in entries))


if __name__ == "__main__":
    unittest.main()
