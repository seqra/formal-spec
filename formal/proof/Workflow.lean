import LibSpec.Transition
import model.SKILL
import spec.Workflow

/-!
  Proofs for the controlled workflow model.

  The first cases establish non-vacuity. The remaining theorems show that the
  transition model preserves the normative gate. Every reachable implementation
  therefore has a proof and model-derived tests for the current specification.
 -/

namespace FormalSpec.Proof

open FormalSpec.Model
open FormalSpec.Spec

def workflowInvariant (state : WorkflowState) : Prop :=
  controlledLoopInvariant WorkflowState.specRevision WorkflowState.proofRevision
    WorkflowState.testsRevision WorkflowState.implementationRevision state

theorem rejected_before_proof :
    ¬ workflowInvariant
      { specRevision := 0
        proofRevision := none
        testsRevision := none
        implementationRevision := some 0 } := by
  intro evidence
  have impossible : (none : Option Nat) = some 0 := (evidence rfl).1
  simp at impossible

theorem rejected_without_derived_tests :
    ¬ workflowInvariant
      { specRevision := 0
        proofRevision := some 0
        testsRevision := none
        implementationRevision := some 0 } := by
  intro evidence
  have impossible : (none : Option Nat) = some 0 := (evidence rfl).2
  simp at impossible

theorem accepted_after_proof_and_tests :
    workflowInvariant
      { specRevision := 0
        proofRevision := some 0
        testsRevision := some 0
        implementationRevision := some 0 } := by
  intro _
  exact ⟨rfl, rfl⟩

theorem initial_state_reachable : workflowModel.Reachable initialState := by
  exact .initial rfl

theorem initial_state_is_reachable_but_not_implementation_ready :
    workflowModel.Reachable initialState ∧
      initialState.implementationRevision ≠ some initialState.specRevision := by
  constructor
  · exact initial_state_reachable
  · simp [initialState]

theorem accepted_state_reachable :
    workflowModel.Reachable
      { specRevision := 0
        proofRevision := some 0
        testsRevision := some 0
        implementationRevision := some 0 } := by
  let provedState : WorkflowState :=
    { specRevision := 0
      proofRevision := some 0
      testsRevision := none
      implementationRevision := none }
  let testedState : WorkflowState :=
    { specRevision := 0
      proofRevision := some 0
      testsRevision := some 0
      implementationRevision := none }
  have provedStateReachable : workflowModel.Reachable provedState := by
    apply LibSpec.TransitionSystem.Reachable.step (system := workflowModel)
      (before := initialState) (after := provedState) (input := .prove)
    · exact initial_state_reachable
    · rfl
  have testedStateReachable : workflowModel.Reachable testedState := by
    apply LibSpec.TransitionSystem.Reachable.step (system := workflowModel)
      (before := provedState) (after := testedState) (input := .deriveTests)
    · exact provedStateReachable
    · constructor <;> rfl
  apply LibSpec.TransitionSystem.Reachable.step (system := workflowModel)
    (before := testedState) (input := .implement)
  · exact testedStateReachable
  · exact ⟨rfl, rfl, rfl⟩

theorem workflow_initial_preserves_gate : workflowInvariant initialState := by
  simp [workflowInvariant, controlledLoopInvariant, initialState]

theorem workflow_preserves_gate :
    workflowModel.Preserves workflowInvariant := by
  intro before event after _ stepEvidence
  unfold workflowInvariant controlledLoopInvariant
  cases event with
  | reviseSpec =>
      subst after
      simp
  | prove =>
      subst after
      simp
  | deriveTests =>
      rcases stepEvidence with ⟨_, rfl⟩
      simp
  | implement =>
      rcases stepEvidence with ⟨proofEvidence, testsEvidence, rfl⟩
      intro _
      exact ⟨proofEvidence, testsEvidence⟩

theorem reachable_implementation_has_current_proof_and_tests :
    ∀ state, workflowModel.Reachable state →
      state.implementationRevision = some state.specRevision →
        state.proofRevision = some state.specRevision ∧
          state.testsRevision = some state.specRevision := by
  intro state reachable
  have invariant : ∀ state, workflowModel.Reachable state → workflowInvariant state :=
    LibSpec.TransitionSystem.invariant_of_initial_and_preserved workflowModel
      workflowInvariant (fun state evidence => by
        subst state
        exact workflow_initial_preserves_gate)
        workflow_preserves_gate
  intro implementationEvidence
  exact invariant state reachable implementationEvidence

theorem rejected_state_is_not_reachable_as_an_implementation :
    ¬ (workflowModel.Reachable
        { specRevision := 0
          proofRevision := none
          testsRevision := none
          implementationRevision := some 0 }) := by
  intro reachable
  have gate := reachable_implementation_has_current_proof_and_tests _ reachable rfl
  have impossible : (none : Option Nat) = some 0 := gate.1
  simp at impossible

end FormalSpec.Proof
