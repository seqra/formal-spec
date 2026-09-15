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
(
  cd "$skill_dir/formal"
  lake exe describe-spec
)
for description in \
  index.md \
  vocabulary.md \
  spec/Workflow.md \
  model/SKILL.md \
  proof/Workflow.md
do
  description_path="$skill_dir/formal/.formal-spec/$description"
  if [ ! -s "$description_path" ]; then
    echo "describe-spec did not produce $description_path" >&2
    exit 1
  fi
done
python3 -m unittest discover -s "$skill_dir/tests" -p 'test_*.py'

echo "formal-spec skill check passed"
