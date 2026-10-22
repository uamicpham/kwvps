#!/usr/bin/env python3
"""Extract a KwVPS source archive into an empty, root-owned staging directory.

Only regular files and directories below public/ are allowed. No links, devices,
absolute paths, parent traversal, ownership, or archive permissions are applied.
"""
import os
import shutil
import sys
import tarfile
from pathlib import Path, PurePosixPath

MAX_MEMBERS = 100_000
MAX_BYTES = 8 * 1024**3


def fail(message: str) -> None:
    raise ValueError(message)


def inspect(archive_name: str) -> list[tuple[tarfile.TarInfo, tuple[str, ...]]]:
    with tarfile.open(archive_name, "r:gz") as archive:
        members = archive.getmembers()
        if not members or len(members) > MAX_MEMBERS:
            fail("Archive entry count is invalid")
        total = 0
        checked = []
        for member in members:
            name = member.name.removesuffix("/")
            path = PurePosixPath(name)
            parts = path.parts
            if (name.startswith("/") or "\x00" in name or
                not parts or parts[0] != "public" or
                any(part in ("", ".", "..") for part in name.split("/")) or
                not (member.isfile() or member.isdir())):
                fail(f"Unsafe archive entry: {name!r}")
            if member.isfile() and len(parts) < 2:
                fail("public must be a directory")
            total += member.size
            if total > MAX_BYTES:
                fail("Archive expands beyond size limit")
            checked.append((member, parts))

        return checked


def extract(archive_name: str, stage_name: str) -> None:
    stage = Path(stage_name)
    if not stage.is_dir() or stage.is_symlink() or any(stage.iterdir()):
        fail("Staging directory must be an empty real directory")
    inspect(archive_name)
    with tarfile.open(archive_name, "r:gz") as archive:
        checked = [(member, tuple(PurePosixPath(member.name.removesuffix("/")).parts))
                   for member in archive.getmembers()]
        (stage / "public").mkdir(mode=0o750)
        for member, parts in checked:
            target = stage.joinpath(*parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True, mode=0o750)
                if not target.is_dir() or target.is_symlink():
                    fail("Directory collision in archive")
                continue
            target.parent.mkdir(parents=True, exist_ok=True, mode=0o750)
            source = archive.extractfile(member)
            if source is None:
                fail("Could not read archive file")
            with source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            os.chmod(target, 0o640)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        action = "check"
    elif len(sys.argv) == 3:
        action = "extract"
    else:
        print("usage: restore_source.py [--check] ARCHIVE [EMPTY_STAGE]", file=sys.stderr)
        sys.exit(2)
    try:
        if action == "check":
            inspect(sys.argv[2])
        else:
            extract(sys.argv[1], sys.argv[2])
    except (OSError, ValueError, tarfile.TarError) as exc:
        print(f"Unsafe or unreadable source archive: {exc}", file=sys.stderr)
        sys.exit(2)
