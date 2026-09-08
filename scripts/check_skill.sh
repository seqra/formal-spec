#!/bin/sh
set -eu

skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export PYTHONDONTWRITEBYTECODE=1

if ! command -v lake >/dev/null 2>&1; then
  echo "lake is required but was not found" >&2
  exit 127
fi

if command -v rg >/dev/null 2>&1; then
  if rg -n '^[[:space:]]*(axiom|unsafe|sorry|admit)([[:space:]]|$)' \
      "$skill_dir/LibSpec" -g '*.lean'; then
    echo "unchecked Lean declaration or placeholder found" >&2
    exit 1
  fi
fi

(
  cd "$skill_dir/LibSpec"
  lake build
)
python3 -m unittest discover -s "$skill_dir/tests" -p 'test_*.py'

echo "formal-spec skill check passed"
