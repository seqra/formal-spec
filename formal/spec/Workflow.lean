/-!
  Normative proof-first gate.

  The specification is stated against projections rather than the concrete
  workflow transition relation.  This keeps the requirement independent of
  how a project records revisions or performs its implementation step.
 -/

namespace FormalSpec.Spec

def proofFirstInvariant {State : Type} (specRevision : State → Nat)
    (proofRevision implementationRevision : State → Option Nat) (state : State) : Prop :=
  implementationRevision state = some (specRevision state) →
    proofRevision state = some (specRevision state)

end FormalSpec.Spec
