import LibSpec
import spec.Provenance
import spec.Workflow

namespace FormalSpec

/-!
The public description surface is intentionally explicit.  Register only the
normative declarations whose docstrings describe user-facing guarantees; do
not scan imported environments or source models for definitions.
-/
def specDescriptions : List String :=
  [ describeSpec% FormalSpec.Spec.proofFirstInvariant,
    describeSpec% FormalSpec.Provenance.Valid ]

end FormalSpec

def main : IO Unit := do
  IO.println (String.intercalate "\n" FormalSpec.specDescriptions)
