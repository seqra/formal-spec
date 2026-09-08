# Proof-first development loop

## Bound the claim

Name the behavior being changed. Record included inputs and states, observable
outputs or effects, excluded cases, external assumptions, and the stopping
condition. Keep this near the spec as Lean data or a concise comment when it
affects theorem interpretation.

Inspect existing specs and proofs before inspecting implementation details.
Reuse the weakest existing theorem that expresses the requirement.

## Specify before implementation

Write a relation, predicate, algebraic data type, or transition system that
states permitted behavior. Include at least one accepted case and one rejected
or boundary case so the definition is not vacuous. Keep external facts as
parameters or explicit hypotheses.

For a change to existing code, do not initially define the spec as the observed
implementation. Observations are evidence until the user makes them normative.

## Introduce a model only on demand

A source model is justified when a proof must connect code behavior to the spec,
or when a precise model will guide new implementation. Model the smallest
relevant behavior and observations. It can be a function, relation, state
machine, or other direct Lean definition. It does not need to encode the source
language.

Do not model unrelated declarations. Do not create reusable translation
machinery in anticipation of future proofs. Factor repeated model structure
only after repetition makes the abstraction cheaper to understand and prove.

## Prove and test

State a theorem that visibly mentions both the model and the spec. Check all
proofs with Lean. Reject `sorry`, `admit`, new axioms, and unsafe escapes unless
the user explicitly accepts the resulting trust boundary.

Use the proved case split, constructors, or transition guards to derive tests.
Tests are implementation evidence. They are not a replacement for the proof,
and a proof about a model is not by itself proof about the executable source.

## Implement and reconnect

Use the spec and model as inputs to implementation. After changing source:

- update the model only when the modeled behavior changed;
- update the spec only for an authorized change of intent;
- repair the proof at the earliest false layer;
- update the source hash after reviewing source/model correspondence;
- retain new counterexamples as durable cases;
- run Lean, implementation tests, and the provenance checker.

Classify evolution as an extension, semantics-preserving refactor, correction,
or explicit guarantee break. Never delete a failing guarantee just to restore a
green build.
