import LibSpec.Transition

/-!
  A small model of the controlled development loop described by the skill.

  This is deliberately a workflow model, not a model of Lean, Python, a
  filesystem, or a source-language compiler. A revision number stands for the
  normative specification currently under development. A proof records the
  revision it establishes. Generated tests and an implementation each record
  the revision they were derived from.
 -/

namespace FormalSpec.Model

structure WorkflowState where
  specRevision : Nat
  proofRevision : Option Nat
  testsRevision : Option Nat
  implementationRevision : Option Nat
deriving DecidableEq, Repr

inductive WorkflowEvent
  | reviseSpec
  | prove
  | deriveTests
  | implement
deriving DecidableEq, Repr

def initialState : WorkflowState :=
  { specRevision := 0
    proofRevision := none
    testsRevision := none
    implementationRevision := none }

def workflowModel : LibSpec.TransitionSystem WorkflowState WorkflowEvent where
  initial state := state = initialState
  step before event after :=
    match event with
    | .reviseSpec =>
        after =
          { specRevision := before.specRevision + 1
            proofRevision := none
            testsRevision := none
            implementationRevision := none }
    | .prove =>
        after =
          { specRevision := before.specRevision
            proofRevision := some before.specRevision
            testsRevision := none
            implementationRevision := none }
    | .deriveTests =>
        before.proofRevision = some before.specRevision ∧
          after =
            { specRevision := before.specRevision
              proofRevision := before.proofRevision
              testsRevision := some before.specRevision
              implementationRevision := none }
    | .implement =>
        before.proofRevision = some before.specRevision ∧
          before.testsRevision = some before.specRevision ∧
          after =
            { specRevision := before.specRevision
              proofRevision := before.proofRevision
              testsRevision := before.testsRevision
              implementationRevision := some before.specRevision }

end FormalSpec.Model
