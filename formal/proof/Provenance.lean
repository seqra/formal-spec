import model.scripts.check_provenance

/-!
Proofs connecting the executable validator model to the normative provenance
contract, together with concrete accepted and rejected cases.
-/

namespace FormalProof.Provenance

open FormalSpec.Provenance
open FormalModel.Provenance

theorem validateModel_sound {view : View} {manifest : Manifest}
    (accepted : validateModel view manifest = true) :
    Valid view manifest := by
  simpa [validateModel, Valid, List.all_eq_true] using accepted

theorem validateModel_complete {view : View} {manifest : Manifest}
    (valid : Valid view manifest) :
    validateModel view manifest = true := by
  simpa [validateModel, Valid, List.all_eq_true] using valid

theorem validateModel_correct {view : View} {manifest : Manifest} :
    validateModel view manifest = true ↔ Valid view manifest := by
  constructor
  · exact validateModel_sound
  · exact validateModel_complete

theorem accepted_ids_unique {view : View} {manifest : Manifest}
    (accepted : validateModel view manifest = true) :
    (AllIds manifest).Nodup := by
  exact (validateModel_sound accepted).1

theorem accepted_models_have_one_binding {view : View} {manifest : Manifest}
    (accepted : validateModel view manifest = true) :
    (BoundModels manifest).Nodup := by
  exact (validateModel_sound accepted).2.1

theorem accepted_proofs_use_bound_models {view : View} {manifest : Manifest}
    (accepted : validateModel view manifest = true) :
    ∀ proof, proof ∈ manifest.proofs →
      proof.model ∈ BoundModels manifest := by
  intro proof proofInManifest
  exact ((validateModel_sound accepted).2.2.2.1 proof proofInManifest).2

theorem accepted_models_are_all_proved {view : View} {manifest : Manifest}
    (accepted : validateModel view manifest = true) :
    ∀ binding, binding ∈ manifest.bindings →
      binding.model ∈ ProvedModels manifest := by
  exact (validateModel_sound accepted).2.2.2.2

theorem accepted_source_hashes_match {view : View} {manifest : Manifest}
    (accepted : validateModel view manifest = true) :
    ∀ binding, binding ∈ manifest.bindings →
      view.digest binding.source = binding.sourceSha256 := by
  intro binding bindingInManifest
  have bindingOK :=
    ((validateModel_sound accepted).2.2.1 binding bindingInManifest)
  rcases bindingOK with ⟨_, _, _, _, _, _, digestMatches⟩
  exact digestMatches

theorem accepted_anchors_exist {view : View} {manifest : Manifest}
    (accepted : validateModel view manifest = true) :
    (∀ binding, binding ∈ manifest.bindings →
      view.hasAnchor binding.source binding.sourceAnchor = true ∧
      view.hasAnchor binding.model binding.modelAnchor = true) ∧
    (∀ proof, proof ∈ manifest.proofs →
      view.hasAnchor proof.spec proof.specAnchor = true ∧
      view.hasAnchor proof.model proof.modelAnchor = true ∧
      view.hasAnchor proof.proof proof.proofAnchor = true) := by
  constructor
  · intro binding bindingInManifest
    have bindingOK := (validateModel_sound accepted).2.2.1 binding bindingInManifest
    rcases bindingOK with ⟨_, _, _, sourceAnchor, modelAnchor, _, _⟩
    exact ⟨sourceAnchor, modelAnchor⟩
  · intro proof proofInManifest
    have proofOK :=
      ((validateModel_sound accepted).2.2.2.1 proof proofInManifest).1
    rcases proofOK with ⟨_, _, _, _, specAnchor, modelAnchor, proofAnchor⟩
    exact ⟨specAnchor, modelAnchor, proofAnchor⟩

def zeroDigest : String := String.ofList (List.replicate 64 '0')

def acceptedView : View where
  isFile := fun _ => true
  hasAnchor := fun _ _ => true
  digest := fun _ => zeroDigest

def acceptedBinding : Binding where
  id := "checker-source-model"
  source := "scripts/check_provenance.py"
  sourceAnchor := "def validate"
  sourceSha256 := zeroDigest
  model := "formal/model/scripts/check_provenance.lean"
  modelAnchor := "def validateModel"

def acceptedProof : ProofLink where
  id := "checker-validation-proof"
  spec := "formal/spec/Provenance.lean"
  specAnchor := "def Valid"
  model := acceptedBinding.model
  modelAnchor := acceptedBinding.modelAnchor
  proof := "formal/proof/Provenance.lean"
  proofAnchor := "theorem validateModel_correct"

def acceptedManifest : Manifest where
  bindings := [acceptedBinding]
  proofs := [acceptedProof]

theorem accepted_example :
    validateModel acceptedView acceptedManifest = true := by
  native_decide

def unboundProof : ProofLink where
  id := "unbound-proof"
  spec := "formal/spec/Provenance.lean"
  specAnchor := "def Valid"
  model := "formal/model/ghost.lean"
  modelAnchor := "def ghostModel"
  proof := "formal/proof/Provenance.lean"
  proofAnchor := "theorem validateModel_correct"

def unboundProofManifest : Manifest where
  bindings := [acceptedBinding]
  proofs := [unboundProof]

theorem rejects_unbound_proof :
    validateModel acceptedView unboundProofManifest = false := by
  native_decide

def missingProofManifest : Manifest where
  bindings := [acceptedBinding]
  proofs := []

theorem rejects_missing_proof :
    validateModel acceptedView missingProofManifest = false := by
  native_decide

def changedHashView : View where
  isFile := fun _ => true
  hasAnchor := fun _ _ => true
  digest := fun _ => "1111111111111111111111111111111111111111111111111111111111111111"

theorem rejects_changed_source_hash :
    validateModel changedHashView acceptedManifest = false := by
  native_decide

end FormalProof.Provenance
