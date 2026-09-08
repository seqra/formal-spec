#!/usr/bin/env python3
"""Materialize the LibSpec delivery into a project's formal build area."""

from __future__ import annotations

import argparse
import filecmp
from pathlib import Path
import shutil
import sys
import tempfile


SKILL_DIR = Path(__file__).resolve().parents[1]
SOURCE = SKILL_DIR / "LibSpec"


def delivery_files(root: Path) -> dict[Path, Path]:
    return {
        path.relative_to(root): path
        for path in root.rglob("*")
        if path.is_file() and ".lake" not in path.relative_to(root).parts
    }


def trees_equal(left: Path, right: Path) -> bool:
    if not left.is_dir() or not right.is_dir():
        return False
    left_files = delivery_files(left)
    right_files = delivery_files(right)
    return left_files.keys() == right_files.keys() and all(
        filecmp.cmp(path, right_files[name], shallow=False)
        for name, path in left_files.items()
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="project root")
    parser.add_argument("--check", action="store_true", help="check without writing")
    parser.add_argument("--force", action="store_true", help="replace a changed delivery")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project = args.project.resolve()
    destination = project / "formal" / ".formal-spec" / "LibSpec"
    if not (SOURCE / "LibSpec.lean").is_file():
        print("materialize error: delivered LibSpec is incomplete", file=sys.stderr)
        return 1
    if trees_equal(SOURCE, destination):
        print(f"LibSpec delivery current: {destination}")
        return 0
    if args.check:
        print(f"materialize error: LibSpec delivery differs: {destination}", file=sys.stderr)
        return 1
    if destination.exists() and not args.force:
        print(
            f"materialize error: refusing to replace changed delivery: {destination}; "
            "pass --force after review",
            file=sys.stderr,
        )
        return 1
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".libspec-", dir=destination.parent) as temporary:
        staged = Path(temporary) / "LibSpec"
        shutil.copytree(SOURCE, staged, ignore=shutil.ignore_patterns(".lake"))
        if destination.exists():
            shutil.rmtree(destination)
        staged.rename(destination)
    print(f"LibSpec delivery materialized: {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
