/-!
  Normative controlled-loop gate.

  The specification is stated against projections rather than the concrete
  workflow transition relation. This keeps the requirement independent of how
  a project records revisions or performs each development step.
 -/

namespace FormalSpec.Spec

/--
The proved-test implementation gate.

For a state observed through the four supplied projections, an implementation
at the current specification revision is permitted only when both a proof and
model-derived tests record that same revision.

Boundary:
* Included are the current specification revision and the optional proof,
  generated-test, and implementation revisions.
* An accepted case has `implementationRevision state`, `proofRevision state`,
  and `testsRevision state` equal to `some (specRevision state)`.
* A rejected case has an implementation at the current revision while its
  proof or generated-test revision is absent or names another revision.

Assumptions:
* Revision numbers identify normative specification intent.
* `some revision` means that the corresponding proof, generated tests, or
  implementation claim to address exactly that revision.

Exclusions:
* This predicate does not define how revisions, proofs, tests, or
  implementations are stored or produced.
* It does not establish that the adapter used by tests observes every relevant
  production effect.
-/
def controlledLoopInvariant {State : Type} (specRevision : State → Nat)
    (proofRevision testsRevision implementationRevision : State → Option Nat)
    (state : State) : Prop :=
  implementationRevision state = some (specRevision state) →
    proofRevision state = some (specRevision state) ∧
      testsRevision state = some (specRevision state)

end FormalSpec.Spec
