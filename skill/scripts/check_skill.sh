#!/bin/sh
set -eu

skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project_dir=$(CDPATH= cd -- "$skill_dir/.." && pwd)
export PYTHONDONTWRITEBYTECODE=1

if ! command -v lake >/dev/null 2>&1; then
  echo "lake is required but was not found" >&2
  exit 127
fi

if command -v rg >/dev/null 2>&1; then
  if rg -n '^[[:space:]]*(axiom|unsafe|sorry|admit)([[:space:]]|$)' \
      "$skill_dir/LibSpec" "$project_dir/formal" -g '*.lean'; then
    echo "unchecked Lean declaration or placeholder found" >&2
    exit 1
  fi
fi

(
  cd "$skill_dir/LibSpec"
  lake build
)
python3 "$skill_dir/scripts/materialize_libspec.py" --project "$project_dir" --force
python3 "$skill_dir/scripts/materialize_libspec.py" --project "$project_dir" --check
(
  cd "$project_dir/formal"
  lake build
)
(
  cd "$project_dir/formal"
  lake exe describe-spec
)
for description in \
  index.md \
  vocabulary.md \
  spec/Workflow.md \
  model/SKILL.md \
  proof/Workflow.md
do
  description_path="$project_dir/formal/.formal-spec/$description"
  if [ ! -s "$description_path" ]; then
    echo "describe-spec did not produce $description_path" >&2
    exit 1
  fi
done
python3 -m unittest discover -s "$project_dir/tests" -p 'test_*.py'

echo "formal-spec skill check passed"
