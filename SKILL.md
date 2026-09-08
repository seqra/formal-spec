---
name: formal-spec
description: Use Lean specifications, demand-driven source models, and proofs to drive implementation and regression tests. Apply when a behavior, invariant, protocol, state transition, or correctness-sensitive change should be designed proof-first and retained as machine-checked knowledge. Do not use for cosmetic changes or requests with no meaningful behavioral claim.
---

# Formal Spec

Develop behavior proof-first. Treat the specification as the normative account
of the requested behavior. Use a source model only when a proof needs to reason
about code behavior or when a model will guide an implementation.

## Work in four artifacts

- **Source** is the code or other implementation artifact.
- **Model** is a small Lean account of the relevant source behavior. Write it
  on demand. Do not translate a whole project or build a language backend.
- **Spec** is the user's intent in Lean. Keep it independent of current source
  behavior.
- **Proof** connects the model to the spec and records the retained guarantee.

`LibSpec/` is part of this skill's delivery. Reuse its relational and transition
system primitives when they make the project proof smaller. Do not force a
project into those abstractions when direct Lean definitions are clearer.

## Establish the project layout

Read [references/layout.md](references/layout.md) before creating or relocating
formal artifacts. Preserve the source directory structure below `formal/model/`.
Keep specifications in `formal/spec/` and the connecting proofs in
`formal/proof/`. Do not create `embedding/`, `domains/`, `derived/`, adapter,
backend, or generated-semantics directories.

Materialize the delivered `LibSpec` into the project's hidden formal build area
when a portable local Lake dependency is needed:

```sh
python3 <skill-dir>/scripts/materialize_libspec.py --project <project-root>
```

## Follow the proof-first loop

Read [references/workflow.md](references/workflow.md) for the detailed loop.
For each change:

1. State the boundary, observations, exclusions, and assumptions.
2. Write the smallest non-vacuous spec, including an accepted case and a
   rejected or boundary case.
3. Write a source model only if the required proof needs one. For new code, the
   model can guide implementation. For existing code, model only the relevant
   behavior.
4. Prove that the model satisfies or refines the spec. A theorem with premises
   is conditional; report those premises.
5. Derive executable tests or checks from the proved partitions when useful.
6. Implement or change the source, then run Lean, the implementation tests, and
   the source-provenance check.

Do not change the spec merely to make the current implementation pass. Classify
a mismatch as a source defect, model defect, false assumption, missing case, or
authorized requirement change before editing normative meaning. Retain
counterexamples as a theorem, test, or modeled boundary case.

## Describe specifications for readers

Read [references/descriptions.md](references/descriptions.md) when a project
needs a human-readable view of its specifications. A Lean declaration remains
the normative artifact; its declaration docstring is explanatory metadata. The
`describe-spec` Lean executable consumes an explicit registry of public spec
declarations and writes a replaceable Markdown report under
`formal/.formal-spec/spec.md` when requested. Generate that report on demand
after the formal package builds; do not edit or treat it as a second source of
truth.

The report should show both the docstring and the exact formal statement, with
links or source locations where available. A prose description is not a proof
of the declaration and a generated report does not establish model/source
correspondence. Do not infer descriptions by scanning every definition, by
translating arbitrary Lean expressions into English, or by deriving intent
from a model or proof.

## Connect proofs to source without a backend

Read [references/provenance.md](references/provenance.md) when a model is added
or changed. Record only source-to-model and spec/model-to-proof wiring in
`formal/provenance.yaml`. The format is JSON-compatible YAML so the bundled
checker has no package dependency.

The checker reads source and Lean files directly. It verifies paths, literal
anchors, source hashes, and complete proof wiring. It must not invoke a
compiler, parser, language server, package manager, or Lean. Generate the visual
view with:

```sh
python3 <skill-dir>/scripts/check_provenance.py \
  formal/provenance.yaml --root . \
  --html formal/.formal-spec/provenance.html
```

This check establishes artifact identity and visible traceability only. It does
not establish that the model faithfully represents source semantics. The Lean
proof establishes a theorem about the model and spec; source correspondence
remains a reviewed claim unless separately proved.

## Finish with exact evidence

Report the boundary, checked theorem names, modeled source files, source hashes,
test evidence, and remaining assumptions or correspondence gaps. Call missing
evidence `unknown`. Do not promote sampled tests, successful compilation, or a
valid provenance view into a stronger correctness claim.
