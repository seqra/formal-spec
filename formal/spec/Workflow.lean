/-!
  Normative proof-first gate.

  The specification is stated against projections rather than the concrete
  workflow transition relation.  This keeps the requirement independent of
  how a project records revisions or performs its implementation step.
 -/

namespace FormalSpec.Spec

/--
The proof-first implementation gate.

For a state observed through the three supplied projections, an implementation
at the current specification revision is permitted only when a proof records
that same revision.

Boundary:
* Included are the current specification revision and the optional proof and
  implementation revisions.
* An accepted case has both `implementationRevision state` and
  `proofRevision state` equal to `some (specRevision state)`.
* A rejected case has an implementation at the current revision while its
  proof revision is absent or names another revision.

Assumptions:
* Revision numbers identify normative specification intent.
* `some revision` means that the corresponding proof or implementation claims
  to address exactly that revision.

Exclusions:
* This predicate does not define how revisions, proofs, or implementations are
  stored or produced.
* It does not establish that an implementation matches executable source, or
  that a source model faithfully represents that source.
-/
def proofFirstInvariant {State : Type} (specRevision : State → Nat)
    (proofRevision implementationRevision : State → Option Nat) (state : State) : Prop :=
  implementationRevision state = some (specRevision state) →
    proofRevision state = some (specRevision state)

end FormalSpec.Spec
