/-! Small transition-system primitives for stateful source models and specs. -/

namespace LibSpec

structure TransitionSystem (State Input : Type) where
  initial : State → Prop
  step : State → Input → State → Prop

namespace TransitionSystem

inductive Reachable {State Input : Type} (system : TransitionSystem State Input) :
    State → Prop
  | initial {state} : system.initial state → Reachable system state
  | step {before input after} :
      Reachable system before → system.step before input after → Reachable system after

def Preserves {State Input : Type} (system : TransitionSystem State Input)
    (invariant : State → Prop) : Prop :=
  ∀ before input after,
    invariant before → system.step before input after → invariant after

theorem invariant_of_initial_and_preserved {State Input : Type}
    (system : TransitionSystem State Input) (invariant : State → Prop)
    (initial : ∀ state, system.initial state → invariant state)
    (preserved : system.Preserves invariant) :
    ∀ state, system.Reachable state → invariant state := by
  intro state reachable
  induction reachable with
  | initial evidence => exact initial _ evidence
  | step reachable stepEvidence inductionHypothesis =>
      exact preserved _ _ _ inductionHypothesis stepEvidence

end TransitionSystem
end LibSpec
