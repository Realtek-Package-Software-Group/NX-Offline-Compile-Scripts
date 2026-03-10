#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Repair relocated CPython sysconfig files after portable install."
    )
    parser.add_argument("--python-prefix", required=True)
    parser.add_argument("--llvm-prefix", required=True)
    parser.add_argument("--metadata-file", required=True)
    return parser.parse_args()


def load_metadata(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def iter_target_files(python_prefix: Path) -> list[Path]:
    patterns = (
        "bin/python*-config",
        "lib/pkgconfig/python*.pc",
        "lib/python*/_sysconfigdata_*.py",
        "lib/python*/config-*/Makefile",
    )
    targets: set[Path] = set()
    for pattern in patterns:
        targets.update(python_prefix.glob(pattern))
    return sorted(path for path in targets if path.is_file())


def patch_file(path: Path, replacements: list[tuple[str, str]]) -> bool:
    original = path.read_text(encoding="utf-8", errors="surrogateescape")
    updated = original
    for old, new in replacements:
        updated = updated.replace(old, new)
    if updated == original:
        return False
    path.write_text(updated, encoding="utf-8", errors="surrogateescape")
    return True


def main() -> int:
    args = parse_args()
    python_prefix = Path(args.python_prefix).resolve()
    llvm_prefix = Path(args.llvm_prefix).resolve()
    metadata_file = Path(args.metadata_file).resolve()

    if not metadata_file.is_file():
        print(f"metadata file not found: {metadata_file}", file=sys.stderr)
        return 1

    metadata = load_metadata(metadata_file)
    python_build_prefix = metadata.get("python_build_prefix")
    llvm_build_prefix = metadata.get("llvm_build_prefix")
    if not python_build_prefix or not llvm_build_prefix:
        print(
            "python_build_prefix/llvm_build_prefix missing in metadata file",
            file=sys.stderr,
        )
        return 1

    replacements = [
        (python_build_prefix, str(python_prefix)),
        (llvm_build_prefix, str(llvm_prefix)),
    ]

    modified: list[Path] = []
    for target in iter_target_files(python_prefix):
        if patch_file(target, replacements):
            modified.append(target)

    if modified:
        print("Repaired relocated Python sysconfig files:")
        for path in modified:
            print(path)
    else:
        print("No relocated Python sysconfig files needed patching.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
