import LibSpec.Transition

/-!
  A small model of the proof-first development gate described by the skill.

  This is deliberately a workflow model, not a model of Lean, Python, a
  filesystem, or a source-language compiler.  A revision number stands for
  the normative specification currently under development.  A proof records
  the revision it establishes, and an implementation records the revision it
  was allowed to implement.
 -/

namespace FormalSpec.Model

structure WorkflowState where
  specRevision : Nat
  proofRevision : Option Nat
  implementationRevision : Option Nat
deriving DecidableEq, Repr

inductive WorkflowEvent
  | reviseSpec
  | prove
  | implement
deriving DecidableEq, Repr

def initialState : WorkflowState :=
  { specRevision := 0
    proofRevision := none
    implementationRevision := none }

def workflowModel : LibSpec.TransitionSystem WorkflowState WorkflowEvent where
  initial state := state = initialState
  step before event after :=
    match event with
    | .reviseSpec =>
        after =
          { specRevision := before.specRevision + 1
            proofRevision := none
            implementationRevision := none }
    | .prove =>
        after =
          { specRevision := before.specRevision
            proofRevision := some before.specRevision
            implementationRevision := before.implementationRevision }
    | .implement =>
        before.proofRevision = some before.specRevision ∧
          after =
            { specRevision := before.specRevision
              proofRevision := before.proofRevision
              implementationRevision := some before.specRevision }

end FormalSpec.Model
