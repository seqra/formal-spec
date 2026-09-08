import LibSpec.Transition
import model.SKILL
import spec.Workflow

/-!
  Proofs for the proof-first workflow model.

  The first two theorems are explicit non-vacuity cases.  The remaining
  theorems show that the transition model preserves the normative gate and
  therefore every reachable implementation has a proof for the current
  specification revision.
 -/

namespace FormalSpec.Proof

open FormalSpec.Model
open FormalSpec.Spec

def workflowInvariant (state : WorkflowState) : Prop :=
  proofFirstInvariant WorkflowState.specRevision WorkflowState.proofRevision
    WorkflowState.implementationRevision state

theorem rejected_before_proof :
    ¬ workflowInvariant
      { specRevision := 0
        proofRevision := none
        implementationRevision := some 0 } := by
  intro evidence
  have impossible : (none : Option Nat) = some 0 := evidence rfl
  simp at impossible

theorem accepted_after_proof :
    workflowInvariant
      { specRevision := 0
        proofRevision := some 0
        implementationRevision := some 0 } := by
  intro _
  rfl

theorem initial_state_reachable :
    workflowModel.Reachable initialState := by
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
        implementationRevision := some 0 } := by
  let provedState : WorkflowState :=
    { specRevision := 0
      proofRevision := some 0
      implementationRevision := none }
  have provedStateReachable :
      workflowModel.Reachable provedState := by
    apply LibSpec.TransitionSystem.Reachable.step (system := workflowModel)
      (before := initialState) (after := provedState) (input := .prove)
    · exact initial_state_reachable
    · rfl
  apply LibSpec.TransitionSystem.Reachable.step (system := workflowModel)
    (before := provedState) (input := .implement)
  · exact provedStateReachable
  · constructor <;> rfl

theorem workflow_initial_preserves_gate :
    workflowInvariant initialState := by
  intro evidence
  have impossible : (none : Option Nat) = some 0 := by
    change (none : Option Nat) = some 0 at evidence
    exact evidence
  simp at impossible

theorem workflow_preserves_gate :
    workflowModel.Preserves workflowInvariant := by
  intro before event after _ stepEvidence
  unfold workflowInvariant proofFirstInvariant
  cases event with
  | reviseSpec =>
      subst after
      simp
  | prove =>
      subst after
      simp
  | implement =>
      rcases stepEvidence with ⟨proofEvidence, rfl⟩
      intro _
      exact proofEvidence

theorem reachable_implementation_has_current_proof :
    ∀ state, workflowModel.Reachable state →
      state.implementationRevision = some state.specRevision →
        state.proofRevision = some state.specRevision := by
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
          implementationRevision := some 0 }) := by
  intro reachable
  have gate := reachable_implementation_has_current_proof _ reachable rfl
  have impossible : (none : Option Nat) = some 0 := gate
  simp at impossible

end FormalSpec.Proof
