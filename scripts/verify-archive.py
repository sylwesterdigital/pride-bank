#!/usr/bin/env python3
"""Validate a Pride Bank release ZIP before extraction."""

from __future__ import annotations

import pathlib
import stat
import sys
import zipfile


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: verify-archive.py <release.zip>")

    archive = pathlib.Path(sys.argv[1])
    if not archive.is_file():
        fail(f"release ZIP does not exist: {archive}")

    try:
        with zipfile.ZipFile(archive) as zf:
            bad_crc = zf.testzip()
            if bad_crc:
                fail(f"corrupt ZIP entry: {bad_crc}")

            entries = zf.infolist()
            if not entries:
                fail("release ZIP is empty")

            for info in entries:
                raw = info.filename.replace("\\", "/")
                path = pathlib.PurePosixPath(raw)

                if raw.startswith("/") or path.is_absolute():
                    fail(f"absolute path is not allowed: {raw}")
                if ".." in path.parts:
                    fail(f"parent traversal is not allowed: {raw}")
                if any(part == "" for part in path.parts):
                    fail(f"invalid empty path component: {raw}")
                if path.parts and path.parts[0] == ".git":
                    fail("release ZIP must not contain .git metadata")

                unix_mode = (info.external_attr >> 16) & 0xFFFF
                if stat.S_ISLNK(unix_mode):
                    fail(f"symbolic links are not allowed in releases: {raw}")

    except zipfile.BadZipFile as exc:
        fail(f"invalid ZIP: {exc}")

    print("Archive structure OK")


if __name__ == "__main__":
    main()
