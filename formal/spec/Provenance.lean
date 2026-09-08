/-!
The normative contract for the source/model/spec/proof provenance checker.

This file starts at the boundary after JSON parsing.  `Manifest` therefore
contains the typed records that `load_manifest` promises to produce.  The
filesystem, text, and digest observations are kept behind `View`; proving the
Python and operating-system implementations of those observations is outside
this small slice.
-/

namespace FormalSpec.Provenance

structure Binding where
  id : String
  source : String
  sourceAnchor : String
  sourceSha256 : String
  model : String
  modelAnchor : String
deriving DecidableEq

structure ProofLink where
  id : String
  spec : String
  specAnchor : String
  model : String
  modelAnchor : String
  proof : String
  proofAnchor : String
deriving DecidableEq

structure Manifest where
  bindings : List Binding
  proofs : List ProofLink
deriving DecidableEq

/-!
`isFile` stands for a successful `resolve_project_file` call.  In particular,
the observation includes the relative-path and project-root checks.  `hasAnchor`
stands for successful UTF-8 reading followed by literal substring search.
-/
structure View where
  isFile : String → Bool
  hasAnchor : String → String → Bool
  digest : String → String

def Nonempty (value : String) : Prop := value ≠ ""

instance nonemptyDecidable (value : String) : Decidable (Nonempty value) := by
  unfold Nonempty
  infer_instance

def BindingFieldsNonempty (binding : Binding) : Prop :=
  Nonempty binding.id ∧
  Nonempty binding.source ∧
  Nonempty binding.sourceAnchor ∧
  Nonempty binding.sourceSha256 ∧
  Nonempty binding.model ∧
  Nonempty binding.modelAnchor

instance bindingFieldsNonemptyDecidable (binding : Binding) :
    Decidable (BindingFieldsNonempty binding) := by
  unfold BindingFieldsNonempty
  infer_instance

def ProofFieldsNonempty (proof : ProofLink) : Prop :=
  Nonempty proof.id ∧
  Nonempty proof.spec ∧
  Nonempty proof.specAnchor ∧
  Nonempty proof.model ∧
  Nonempty proof.modelAnchor ∧
  Nonempty proof.proof ∧
  Nonempty proof.proofAnchor

instance proofFieldsNonemptyDecidable (proof : ProofLink) :
    Decidable (ProofFieldsNonempty proof) := by
  unfold ProofFieldsNonempty
  infer_instance

def LowerHex (character : Char) : Bool :=
  (('0' ≤ character) && (character ≤ '9')) ||
  (('a' ≤ character) && (character ≤ 'f'))

def Sha256Shape (value : String) : Prop :=
  value.length = 64 ∧ value.toList.all LowerHex = true

instance sha256ShapeDecidable (value : String) : Decidable (Sha256Shape value) := by
  unfold Sha256Shape
  infer_instance

def BindingOK (view : View) (binding : Binding) : Prop :=
  BindingFieldsNonempty binding ∧
  view.isFile binding.source = true ∧
  view.isFile binding.model = true ∧
  view.hasAnchor binding.source binding.sourceAnchor = true ∧
  view.hasAnchor binding.model binding.modelAnchor = true ∧
  Sha256Shape binding.sourceSha256 ∧
  view.digest binding.source = binding.sourceSha256

instance bindingOKDecidable (view : View) (binding : Binding) :
    Decidable (BindingOK view binding) := by
  unfold BindingOK
  infer_instance

def ProofOK (view : View) (proof : ProofLink) : Prop :=
  ProofFieldsNonempty proof ∧
  view.isFile proof.spec = true ∧
  view.isFile proof.model = true ∧
  view.isFile proof.proof = true ∧
  view.hasAnchor proof.spec proof.specAnchor = true ∧
  view.hasAnchor proof.model proof.modelAnchor = true ∧
  view.hasAnchor proof.proof proof.proofAnchor = true

instance proofOKDecidable (view : View) (proof : ProofLink) :
    Decidable (ProofOK view proof) := by
  unfold ProofOK
  infer_instance

def AllIds (manifest : Manifest) : List String :=
  manifest.bindings.map (fun binding => binding.id) ++
  manifest.proofs.map (fun proof => proof.id)

def BoundModels (manifest : Manifest) : List String :=
  manifest.bindings.map (fun binding => binding.model)

def ProvedModels (manifest : Manifest) : List String :=
  manifest.proofs.map (fun proof => proof.model)

/-!
The checker contract is deliberately stated as a conjunction of independently
auditable obligations.  The final two clauses are the graph-coverage rules:
every proof uses a registered model and every registered model has a proof.
-/
/--
The predicate below is the readable provenance contract for one manifest and
one abstract filesystem/text/digest view.

Boundary:
* Included are manifest identity uniqueness, source/model/spec/proof file and
  anchor observations, source digest equality, and complete model/proof graph
  coverage.
* An accepted case has unique IDs and model bindings, valid anchored records,
  proofs that use bound models, and at least one proof for every bound model.
* A rejected case includes a duplicate ID or model binding, a missing file or
  anchor, a malformed or stale source digest, an unbound proof model, or a
  bound model without a proof.

Assumptions:
* `View` faithfully reports the results of project-root path resolution,
  UTF-8 text reads, literal anchor search, and SHA-256 computation.
* `Manifest` is already typed and has passed the JSON-compatible parsing
  boundary represented by the Python loader.

Exclusions:
* This contract does not prove the operating system, Python implementation, or
  source-language semantics behind those observations.
* A matching source hash and existing anchors establish identity and
  traceability only; they do not prove source/model semantic correspondence.
-/
def Valid (view : View) (manifest : Manifest) : Prop :=
  (AllIds manifest).Nodup ∧
  (BoundModels manifest).Nodup ∧
  (∀ binding, binding ∈ manifest.bindings → BindingOK view binding) ∧
  (∀ proof, proof ∈ manifest.proofs →
    ProofOK view proof ∧ proof.model ∈ BoundModels manifest) ∧
  (∀ binding, binding ∈ manifest.bindings →
    binding.model ∈ ProvedModels manifest)

instance validDecidable (view : View) (manifest : Manifest) :
    Decidable (Valid view manifest) := by
  unfold Valid
  infer_instance

end FormalSpec.Provenance
