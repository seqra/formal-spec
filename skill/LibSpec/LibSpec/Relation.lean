/-!
Relations for connecting an implementation model to a normative specification.
-/

namespace LibSpec

/-- A possibly nondeterministic behavior from inputs to observable outputs. -/
abbrev Behavior (Input Output : Type) := Input → Output → Prop

/-- Every behavior admitted by `implementation` is permitted by `specification`. -/
def Refines {Input Output : Type}
    (implementation specification : Behavior Input Output) : Prop :=
  ∀ input output, implementation input output → specification input output

/-- A deterministic function viewed as a behavior relation. -/
def Behavior.ofFunction {Input Output : Type} (f : Input → Output) :
    Behavior Input Output :=
  fun input output => output = f input

theorem Refines.refl {Input Output : Type} (behavior : Behavior Input Output) :
    Refines behavior behavior := by
  intro _ _ evidence
  exact evidence

theorem Refines.trans {Input Output : Type}
    {first second third : Behavior Input Output}
    (firstSecond : Refines first second) (secondThird : Refines second third) :
    Refines first third := by
  intro input output evidence
  exact secondThird input output (firstSecond input output evidence)

end LibSpec
