import LibSpec

/-! A checked, deliberately small example of source semantics → model → spec. -/

namespace VerifyMax

namespace Source

inductive Program where
  | retA
  | retB
  | ifGe (yes no : Program)

inductive Exec : Program → Int → Int → Int → Prop where
  | retA (a b : Int) : Exec .retA a b a
  | retB (a b : Int) : Exec .retB a b b
  | ifTrue (a b : Int) (yes no : Program) (result : Int)
      (condition : a ≥ b) (branch : Exec yes a b result) :
      Exec (.ifGe yes no) a b result
  | ifFalse (a b : Int) (yes no : Program) (result : Int)
      (condition : ¬ a ≥ b) (branch : Exec no a b result) :
      Exec (.ifGe yes no) a b result

def maxProgram : Program := .ifGe .retA .retB

def behavior (program : Program) : LibSpec.Behavior (Int × Int) Int :=
  fun input result => Exec program input.1 input.2 result

end Source

namespace Model

def translate : Source.Program → Int → Int → Int
  | .retA, a, _ => a
  | .retB, _, b => b
  | .ifGe yes no, a, b =>
      if a ≥ b then translate yes a b else translate no a b

def behavior (program : Source.Program) : LibSpec.Behavior (Int × Int) Int :=
  LibSpec.Behavior.ofFunction (fun input => translate program input.1 input.2)

theorem translation_sound (program : Source.Program) :
    LibSpec.Refines (Source.behavior program) (behavior program) := by
  intro input result execution
  cases input with
  | mk a b =>
    change Source.Exec program a b result at execution
    induction execution with
    | retA => rfl
    | retB => rfl
    | ifTrue a b yes no result condition branch ih =>
        simp only [behavior, LibSpec.Behavior.ofFunction] at *
        simp [translate, condition, ih]
    | ifFalse a b yes no result condition branch ih =>
        simp only [behavior, LibSpec.Behavior.ofFunction] at *
        simp [translate, condition, ih]

end Model

namespace Spec

def maxSpec : LibSpec.Behavior (Int × Int) Int :=
  fun input result =>
    result ≥ input.1 ∧ result ≥ input.2 ∧
      (result = input.1 ∨ result = input.2)

end Spec

-- This statement is the user-facing functional obligation.
theorem max_model_correct :
    LibSpec.Refines (Model.behavior Source.maxProgram) Spec.maxSpec := by
  intro ⟨a, b⟩ result computed
  change result = Model.translate Source.maxProgram a b at computed
  rw [computed]
  by_cases h : a ≥ b
  · simp [Model.translate, Source.maxProgram, h, Spec.maxSpec] <;> omega
  · simp [Model.translate, Source.maxProgram, h, Spec.maxSpec] <;> omega

-- The final claim composes system translation evidence and the user proof.
theorem source_max_correct :
    LibSpec.Refines (Source.behavior Source.maxProgram) Spec.maxSpec :=
  LibSpec.Refines.trans (Model.translation_sound Source.maxProgram)
    max_model_correct

-- Refinement alone is partial correctness; this proves the toy source runs.
theorem source_max_terminates (a b : Int) :
    ∃ result, Source.Exec Source.maxProgram a b result := by
  by_cases h : a ≥ b
  · exact ⟨a, Source.Exec.ifTrue a b .retA .retB a h (.retA a b)⟩
  · exact ⟨b, Source.Exec.ifFalse a b .retA .retB b h (.retB a b)⟩

theorem source_max_total_correct (a b : Int) :
    ∃ result, Source.Exec Source.maxProgram a b result ∧
      Spec.maxSpec (a, b) result := by
  obtain ⟨result, execution⟩ := source_max_terminates a b
  exact ⟨result, execution, source_max_correct (a, b) result execution⟩

end VerifyMax
