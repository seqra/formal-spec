import spec.Provenance

/-!
Executable Boolean model of `scripts/check_provenance.py`'s `validate`
operation.  The input is the typed manifest produced after JSON parsing; the
filesystem, anchor, and digest observations come from `View`.
-/

namespace FormalModel.Provenance

open FormalSpec.Provenance

def validateModel (view : View) (manifest : Manifest) : Bool :=
  Bool.and (decide ((AllIds manifest).Nodup))
    (Bool.and (decide ((BoundModels manifest).Nodup))
      (Bool.and
        (manifest.bindings.all (fun binding => decide (BindingOK view binding)))
        (Bool.and
          (manifest.proofs.all (fun proof =>
            decide (ProofOK view proof ∧ proof.model ∈ BoundModels manifest)))
          (manifest.bindings.all (fun binding =>
            decide (binding.model ∈ ProvedModels manifest))))))

end FormalModel.Provenance
