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
      "$skill_dir/LibSpec" "$skill_dir/formal" -g '*.lean'; then
    echo "unchecked Lean declaration or placeholder found" >&2
    exit 1
  fi
fi

(
  cd "$skill_dir/LibSpec"
  lake build
)
python3 "$skill_dir/scripts/materialize_libspec.py" --project "$skill_dir" --force
python3 "$skill_dir/scripts/materialize_libspec.py" --project "$skill_dir" --check
(
  cd "$skill_dir/formal"
  lake build
)
spec_report="$skill_dir/formal/.formal-spec/spec.md"
(
  cd "$skill_dir/formal"
  lake exe describe-spec > "$spec_report"
)
if [ ! -s "$spec_report" ]; then
  echo "describe-spec produced an empty report: $spec_report" >&2
  exit 1
fi
if [ -f "$skill_dir/formal/provenance.yaml" ]; then
  python3 "$skill_dir/scripts/check_provenance.py" \
    "$skill_dir/formal/provenance.yaml" --root "$skill_dir" \
    --html "$skill_dir/formal/.formal-spec/provenance.html"
fi
python3 -m unittest discover -s "$skill_dir/tests" -p 'test_*.py'

echo "formal-spec skill check passed"
