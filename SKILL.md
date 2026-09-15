---
name: formal-spec
description: Use selective Lean specifications, proofs, and model-derived conformance tests for consequential behavior, invariants, protocols, and state transitions. Do not use for cosmetic changes or requests with no meaningful behavioral claim.
---

# Formal Spec

`formal-spec` is proof-first development for consequential behavior. It
controls the loop:

```text
intent → spec → model → proof → tests → implementation → feedback
```

Use the loop to make behavior changes converge on a checked contract. The
specification states the intended behavior. A small model represents only the
behavior needed for the proof. A theorem checks the model against the
specification. Model-derived conformance tests exercise the real
implementation through a reviewed test adapter.

Do not formalize every change. Formalize an invariant when its failure would
materially affect users, data, money, access, compatibility, safety, or a
stateful protocol. Use ordinary implementation tests and review for cosmetic
changes and low-consequence work.

Read [references/workflow.md](references/workflow.md) before starting a
consequential formal change. Read
[references/testing.md](references/testing.md) when deriving, reviewing, or
describing conformance-test coverage.

## Follow the proof-first loop

1. **Bound the behavior.** State the inputs, states, observations, effects,
   exclusions, external assumptions, and consequence of failure.
2. **Specify intent before implementation.** Write the smallest non-vacuous
   Lean predicate, relation, data type, or transition system. Include an
   accepted case and a rejected or boundary case. Keep the specification
   independent of the current implementation.
3. **Model on demand.** Add the smallest model needed to reason about the
   consequential invariant or to guide a new implementation. Do not translate
   a whole project or build a source-language backend.
4. **Prove the invariant.** State a theorem that visibly mentions the model
   and specification. Keep assumptions explicit. For stateful behavior, prove
   the initial-state condition and transition preservation needed for the
   invariant.
5. **Derive conformance tests.** Generate a finite, proof-informed set of
   corner, boundary, and representative cases from proved partitions,
   constructors, relations, or transition guards. A symbolic proof can cover
   every value in the modeled domain, so the implementation does not need
   infinitely many tests. Run the finite cases against the real implementation
   through a small test adapter.
6. **Review the adapter.** Review how the adapter constructs inputs, invokes
   the implementation, observes outputs, errors, state, and effects, and
   handles setup, cleanup, nondeterminism, and external assumptions. The
   adapter review is part of the formal change.
7. **Implement and execute.** Run the model-derived conformance tests and the
   ordinary implementation test suite. Keep the formal theorem and test
   evidence separate.
8. **Reconcile surprises.** Feed unexpected production or test behavior back
   into the specification or model. Classify the issue before changing an
   expected result: source defect, model gap, adapter defect, missing
   requirement, changed intent, or environmental assumption.

The model-derived conformance tests are the only bridge from the formal work
to the implementation. A source path, hash, annotation, generated report, or
similar metadata is not implementation evidence. Adapter review checks the
mapping and its assumptions; it does not turn a finite test suite into a
symbolic proof of implementation equivalence. Do not claim that a theorem
about a model proves the executable source correct without the conformance
tests and a reviewed adapter.

## State coverage precisely

Use exact coverage language:

- **Finite domains:** call runtime tests exhaustive only when the
  implementation domain itself is explicitly finite, the case set is proved
  sound and complete for that domain, and the adapter executes every case.
- **Infinite domains:** a finite test suite is sampling, even when its cases
  are generated from a proved partition. Derive corner, boundary, and
  representative cases instead of attempting infinitely many tests. A
  symbolic theorem may quantify over every value represented by the model and
  its assumptions, but it does not establish that the implementation matches
  the model for all such values.
- **Stateful systems:** an inductive proof can cover every model-reachable
  state when initialization and transition premises are proved. Executable
  conformance tests cover only the finite traces, initial states, and effects
  that the adapter runs and observes. Do not call those tests exhaustive for
  an unbounded state space.

Never claim coverage of behavior that the model, proof, generated cases, or
adapter does not represent.

## Keep the formal artifacts small

- **Specification:** the user's normative intent, independent of current
  source behavior.
- **Model:** the smallest account of behavior needed by the proof. Add it only
  for a consequential invariant or a design where the model materially
  clarifies implementation.
- **Proof:** a checked theorem connecting that model to the specification.
  Do not use `sorry`, `admit`, unapproved axioms, or unsafe escapes.
- **Conformance tests:** cases and expected observations derived from proved
  behavior and run against the implementation through the reviewed adapter.

Reuse an existing specification, model, and theorem when they already cover
the behavior. Extend them when the invariant genuinely changes. Do not weaken
the specification merely to make the current implementation pass. Preserve a
new counterexample as a formal case, conformance test, or explicit assumption.

`LibSpec/` provides small relation and transition-system primitives, plus
helpers for finite model-derived test vectors. Use them when they make a proof
or test generator clearer; direct Lean definitions are also appropriate.

## Describe each formal source file for readers

Read [references/descriptions.md](references/descriptions.md) when a project
needs the reader-facing description of its formal package. The description
generator writes a replaceable Markdown tree under `formal/.formal-spec/` that
mirrors the public formal source tree. Every public project Lean source file
gets one corresponding Markdown document. The tree also contains
`index.md`, which links the documents, and `vocabulary.md`, which contains the
generated cross-file vocabulary.

Each per-file document is a standalone, human-readable specification of the
declarations in that source file. It must explain the terms, accepted and
rejected cases, conditions, transitions, and established properties needed to
understand the file without opening Lean. It must not contain Lean source,
formal types, proof terms, or code blocks. It may contain a visible relative
link to its source file for provenance; that link is evidence of origin, not a
requirement for understanding the document. Do not maintain a second
hand-written informal specification beside the generated document.

Treat the document as an audit interface, not a prose dump. Preserve logical
structure: conditions and guarantees become separate lists, records and states
become tables, transitions separate preconditions from effects, and theorems
show checked status, scope, assumptions, and result. The index shows file-level
completeness and formal-object counts. Read
[references/descriptions.md](references/descriptions.md) for the full rendering
contract.

Descriptions are derived from elaborated Lean objects and their dependency
graph. The generator uses every referenced term in natural language, chooses
the shortest name that remains unique in the current context, and adds
qualifiers when contexts overlap. Generated term definitions live in the
separate `vocabulary.md`, not in repeated glossary sections inside each
per-file specification.

The only agent-facing extension point is a small `describeAs` vocabulary
override when a declaration's generated name is not a useful domain term. An
override changes presentation only; it cannot change the object,
dependencies, conditions, or proof. Do not add hand-written paragraphs to the
generated output or expose a registry of descriptions that can drift.

The renderer fails visibly. Every source file still receives a document, but
an unsupported construct or unresolved name is marked as an unavailable
description in that document and in `index.md`; the generator's checking mode
must also return a failure for CI. It must never guess, silently omit a
declaration, or hide an ambiguity. The generated documents contain no Lean
types as a fallback. A readable description is not itself a proof, and a
generated document does not establish implementation conformance.

## Finish with exact evidence

Report the behavior boundary, specification declarations, checked theorem
names, modeled behavior, generated conformance tests, adapter review, test
commands and results, coverage class, and remaining assumptions. Call missing
evidence `unknown`. Do not promote a finite test sample, successful
compilation, or a theorem about an incomplete model into a stronger claim.
