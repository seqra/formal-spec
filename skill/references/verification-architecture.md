# Source-level verification architecture

Use this path when the task calls for a theorem about a source program, rather
than finite evidence that an implementation agrees with a hand-built model.
Keep four artifacts explicit: a **program model**, an independent
**specification**, typed **proof obligations**, and **proofs**. Translation
correctness is separate system evidence that lets the final theorem refer to
source semantics.

```text
source artifact ──frontend──▶ source AST ──translation──▶ Lean model
                            │                         │
                            │ source semantics        │ model behavior
                            └───────── soundness ─────┘
specification ──▶ generated obligation about model ──▶ user proof
                            soundness + user proof ──▶ source satisfies spec
```

## Core interfaces

Choose an observation type that contains every result, error, state change,
termination outcome, or effect named by the claim. For deterministic pure
programs, `Input → Output` is enough; for effects or nondeterminism, use a
behavior relation such as `LibSpec.Behavior Input Observation`.

```lean
sourceBehavior : Source.Program → Behavior Input Observation
translate      : Source.Program → Model.Program
modelBehavior  : Model.Program → Behavior Input Observation
spec           : Behavior Input Observation

translation_sound (p : Source.Program) :
  Refines (sourceBehavior p) (modelBehavior (translate p))

model_correct (p : Source.Program) :
  Refines (modelBehavior (translate p)) spec

source_correct (p : Source.Program) :
  Refines (sourceBehavior p) spec :=
  Refines.trans (translation_sound p) (model_correct p)
```

`Refines implementation allowed` means every implementation observation is
allowed by the specification. This direction proves partial correctness; it
does not prove that execution terminates or succeeds. If termination, absence
of exceptions, overflow safety, or progress matters, represent those outcomes
in `Observation` and prove the corresponding totality or safety obligation.
For stateful code, the behavior relation may range over traces, with initial
conditions and transition assumptions stated in the theorem.

The four artifact roles are:

| Artifact | Owns | Required connection |
| --- | --- | --- |
| Program model | A shallow Lean representation of the selected source behavior | A checked source-to-model theorem |
| Specification | Normative allowed behavior | No dependency on generated implementation definitions |
| Obligations | Exact proposition tying the model to the spec | Generated from the current model and spec identities |
| Proofs | Terms inhabiting those propositions | Checked by Lean; no placeholders or unapproved axioms |

Keep source AST, model, and spec identities visible in the obligation or its
imports. A proof of a similarly named or manually copied theorem type is not
enough. Regenerate when source, model, semantics, or spec changes and fail the
build if the checked obligations no longer match the current artifacts. A
source hash may detect staleness but is not a correctness certificate.

Group obligations by the property they establish:

- **Safety:** no prohibited fault or invalid observation, under explicit
  language and environment assumptions.
- **Functional:** every allowed result satisfies the independent spec.
- **Invariant or termination:** preservation across transitions, progress, or
  completion when the claim requires it.

The groups are useful diagnostics, not mandatory files or proof names.

## Establish the translation boundary

Two sound approaches are available:

1. Define and verify `translate` in Lean, then execute it to obtain the model.
2. Let an external translator emit the model and a certificate that Lean checks
   against the *specific* source AST and generated model.

The second approach leaves the translator outside the trusted base only if the
checker validates the actual translation relation. A declaration of
`Translates source model`, a hash, or `rfl` on translator-produced constants
does not establish semantics preservation by itself. Audit the certificate
checker and any axioms it relies on.

Define where the source claim starts. A theorem over a Lean `Source.Program`
value establishes behavior of that AST under its formal semantics. Claiming
the same theorem about exact `.py` or `.kt` bytes additionally requires a
checked parsing/frontend relation from those bytes to the AST or IR. Claiming
behavior of the deployed executable additionally needs justified compilation,
runtime, and environment assumptions. State the last justified boundary in
the report.

For multiple languages, a canonical verification IR can share the deep
semantics and the IR-to-shallow-model proof. Each frontend still needs its own
source-to-IR justification before a source-language claim follows. Start with
one bounded typed subset and the constructs needed for one useful property;
do not infer whole-language coverage from a subset proof.

## Checked end-to-end example

[Max.lean](../examples/Max.lean) checks a tiny source language with returns and
an `if a ≥ b` branch. Its `Source.Exec` is an inductive operational semantics.
`Model.translate` produces a shallow Lean function. The user-facing
`Spec.maxSpec` independently requires that the result be at least both inputs
and equal one of them.

The example's checked chain is:

```text
Source.maxProgram
  ├─ Model.translation_sound : Source.behavior ⊆ Model.behavior
  ├─ max_model_correct       : Model.behavior  ⊆ Spec.maxSpec
  ├─ source_max_correct      : Source.behavior ⊆ Spec.maxSpec
  ├─ source_max_terminates   : every input has a source execution
  └─ source_max_total_correct: every input has a spec-satisfying execution
```

This proves the property for every `Int` input and every behavior admitted by
the toy AST semantics. The source snippet it represents is:

```python
def max(a: int, b: int) -> int:
    if a >= b:
        return a
    return b
```

There is no Python parser or Python runtime proof in this example, so the
checked result is about `Source.maxProgram`, not those exact Python bytes. The
example demonstrates the architecture without implying such a frontend exists.
Check it with:

```sh
(cd skill/LibSpec && lake build && lake env lean ../examples/Max.lean)
```

In a project, the model and obligation can be generated while the spec and
proof remain human-owned. For example, `FooModel.lean` contains the generated
model and checked translation certificate; `FooSpec.lean` states normative
behavior; `FooObligations.lean` exports the generated theorem type; and
`FooProofs.lean` provides a term of that exact type. Choose an import structure
that avoids a cycle between obligations and proofs. CI regenerates the model
and obligations, checks the translation certificate, then runs `lake build`.
Conformance tests remain useful as independent checks of the frontend, runtime,
and deployment boundary, with their finite scope reported separately.
