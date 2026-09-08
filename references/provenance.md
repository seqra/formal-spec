# Source provenance

Provenance is a visual trace over real files, not another semantic layer. Store
the minimal wiring in `formal/provenance.yaml`. Use JSON syntax, which is a
portable subset of YAML and lets the checker remain dependency-free.

```json
{
  "version": 1,
  "bindings": [
    {
      "id": "token-source-model",
      "source": "src/auth/token.ts",
      "source_anchor": "function validateToken",
      "source_sha256": "<lowercase SHA-256 of the source file>",
      "model": "formal/model/src/auth/token.lean",
      "model_anchor": "def validateTokenModel"
    }
  ],
  "proofs": [
    {
      "id": "token-policy-proof",
      "spec": "formal/spec/TokenPolicy.lean",
      "spec_anchor": "def tokenPolicy",
      "model": "formal/model/src/auth/token.lean",
      "model_anchor": "def validateTokenModel",
      "proof": "formal/proof/TokenPolicy.lean",
      "proof_anchor": "theorem validateToken_satisfies_policy"
    }
  ]
}
```

All paths are relative to the project root. Anchors are literal, non-empty text
that must occur in the referenced file. IDs are stable labels for the visual
view; keep them when files move. Each modeled file needs one source binding and
at least one proof connection. Each proof connection must use a registered
model.

Compute a source hash with a local SHA-256 tool. Change it only after comparing
the changed source with its model. A matching hash proves identity of the bytes
that were reviewed; it does not prove semantic correspondence.

Run validation without writing:

```sh
python3 <skill-dir>/scripts/check_provenance.py \
  formal/provenance.yaml --root .
```

Add `--html formal/.formal-spec/provenance.html` to render the visual view. The
HTML is replaceable output. The checker performs file reads only, apart from
writing that requested output. It never runs Lean or a source-language tool.
