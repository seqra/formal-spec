/-! Primitives for deriving complete implementation checks from finite models. -/

namespace LibSpec

/-- A finite list proven to cover exactly the declared part of an input type. -/
structure FiniteDomain (Input : Type) where
  cases : List Input
  contains : Input → Prop
  sound : ∀ input, input ∈ cases → contains input
  complete : ∀ input, contains input → input ∈ cases
  nodup : cases.Nodup

structure TestVector (Input Output : Type) where
  input : Input
  expected : Output

def testVectors {Input Output : Type} (domain : FiniteDomain Input)
    (oracle : Input → Output) : List (TestVector Input Output) :=
  domain.cases.map fun input => { input, expected := oracle input }

def ConformsOn {Input Output : Type} (domain : FiniteDomain Input)
    (candidate oracle : Input → Output) : Prop :=
  ∀ input, domain.contains input → candidate input = oracle input

theorem conformsOn_of_all_cases {Input Output : Type}
    (domain : FiniteDomain Input) (candidate oracle : Input → Output)
    (checked : ∀ input, input ∈ domain.cases → candidate input = oracle input) :
    ConformsOn domain candidate oracle := by
  intro input included
  exact checked input (domain.complete input included)

/-- Every input inside the declared domain appears in the generated vectors. -/
theorem testVectors_complete {Input Output : Type}
    (domain : FiniteDomain Input) (oracle : Input → Output) :
    ∀ input, domain.contains input →
      ∃ vector ∈ testVectors domain oracle,
        vector.input = input ∧ vector.expected = oracle input := by
  intro input included
  refine ⟨{ input, expected := oracle input }, ?_, rfl, rfl⟩
  exact List.mem_map.mpr ⟨input, domain.complete input included, rfl⟩

@[simp]
theorem testVectors_length {Input Output : Type} (domain : FiniteDomain Input)
    (oracle : Input → Output) :
    (testVectors domain oracle).length = domain.cases.length := by
  simp [testVectors]

end LibSpec
