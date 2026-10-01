# Proof-first development loop

Use this proof-first loop when a behavior or invariant matters enough to retain
as a machine-checked contract:

```text
intent → independent spec + source model → obligations → proofs
                                      ↘ checked translation → source theorem
                                      ↘ conformance tests → runtime evidence
```

The purpose is to control one consequential claim. When translation soundness
is checked, carry the model proof through to source semantics. Otherwise,
carry it to the implementation with model-derived conformance tests and state
the narrower evidence. Read [verification-architecture.md](verification-architecture.md)
for the source-level path and its checked example.

## 1. Bound the claim

Name the behavior and why its failure matters. Record:

- inputs, states, and relevant initial conditions;
- observable outputs, errors, state changes, and external effects;
- accepted, rejected, and boundary cases;
- excluded behavior and environmental assumptions; and
- the stopping condition for the change.

Inspect existing specifications, models, proofs, and conformance tests before
adding artifacts. Reuse the weakest existing theorem that expresses the
requirement. If no consequential invariant is at stake, stop the formal loop
and use ordinary implementation tests and review.

## 2. Specify before implementation

Write a relation, predicate, algebraic data type, or transition system that
states permitted behavior. Include at least one accepted case and one rejected
or boundary case so the claim is not vacuous. Keep external facts as explicit
parameters or hypotheses.

For an existing implementation, do not initially define the specification as
the behavior currently observed. Observations are evidence until the user
makes them normative. For a changed requirement, revise the specification
explicitly and record which prior guarantee is extended, narrowed, or removed.

## 3. Model only what the proof needs

Add a model only when a proof must reason about implementation-relevant
behavior or when a model gives a new implementation a precise design target.
Model the smallest useful boundary and observations. A source-level theorem
requires formal source semantics, a translation, and a checked relation to the
shallow model. Limit any translator or verification IR to the selected typed
subset and behavior claim; do not mirror unrelated declarations.

For stateful behavior, model only the state, inputs, transitions, and
observations needed for the invariant. Make initialization, transition guards,
nondeterminism, and external assumptions explicit. A model is an abstraction,
not an assertion that the source has those semantics.

## 4. Prove the consequential invariant

State a theorem that visibly mentions both the model and the specification.
Check it with Lean. Reject `sorry`, `admit`, new axioms, and unsafe escapes
unless the user explicitly accepts the resulting assumption.

For a stateless relation, prove the required behavior relation over the model's
declared inputs and observations. For a stateful system, prove the initial
condition and preservation across every modeled transition before claiming an
invariant for every model-reachable state. Keep theorem premises visible in
the report and in the implementation test plan.

Generate obligations whose types connect the current model to the independent
specification. Separate safety, functional, and invariant or termination
obligations where those claims matter. If translation soundness is checked,
compose it with the user proof and check the final theorem about source
semantics. State whether the theorem starts from source bytes, an AST, or IR.
Without that translation evidence, the theorem's quantifiers describe the
model only. Derive finite, proof-informed cases for runtime conformance, while
stating that finite tests do not prove symbolic source/model equivalence.

## 5. Derive conformance tests when useful

When runtime comparison is useful, generate a finite set of test cases and
expected observations from proved partitions, constructors, relations, or
transition guards. Include corner,
boundary, and representative cases, retaining the accepted and rejected
distinctions used by the proof. The proof informs the cases; it does not make a
finite test run equivalent to the proof.
Read [testing.md](testing.md) for generator design, finite-domain completeness,
stateful traces, and adapter review.

When no checked translation relation exists, the conformance test adapter is
the implementation bridge. It must
be small enough to review and explicit about:

- how model inputs become implementation inputs;
- how outputs, errors, state, and effects become model observations;
- setup, cleanup, clocks, randomness, concurrency, and external services;
- unsupported or skipped cases; and
- the assumptions under which its comparison is meaningful.

Review the adapter against the formal specification. A test that never reaches
the relevant implementation path, drops an error or effect, normalizes away a
distinction, or silently skips a case is not conformance evidence. Do not use
file identity, source metadata, or a prose mapping as a substitute for running
the adapter. Adapter review establishes what the test invokes and observes,
including its assumptions; it does not establish symbolic equivalence between
the implementation and the model.

## 6. State coverage without overclaiming

Classify coverage before reporting results:

- **Finite input or state domain:** runtime tests are exhaustive only if the
  implementation domain itself is explicitly bounded, the generated case set
  is proved sound and complete, and the adapter executes every case exactly as
  specified. Otherwise they are samples, even if they look comprehensive.
- **Infinite input domain:** no finite executable suite is exhaustive. A Lean
  theorem may establish a universal property of the model for all values under
  its premises. The implementation needs only a finite, proof-informed set of
  corner, boundary, and representative cases. Those conformance tests provide
  finite evidence that the implementation behaves like that model on selected
  cases.
- **Unbounded or stateful behavior:** an inductive model proof may cover every
  reachable model state from the proved initial conditions and transitions.
  Tests cover only the finite traces and initial states executed by the
  adapter, plus the observations it exposes. They do not by themselves cover
  every production execution.

If a domain is finite but the adapter cannot execute every case, report the
formal domain as finite and the implementation evidence as partial. If state,
time, randomness, concurrency, or an external service is abstracted away,
name that assumption instead of calling the result exhaustive.

## 7. Implement, run, and reconcile

Run the model-derived conformance tests through the reviewed adapter, then run
the ordinary implementation tests and relevant operational checks. Keep the
formal theorem, conformance evidence, and ordinary test evidence distinct.

When an implementation or production observation is unexpected, feed it back
into the formal work instead of silently changing an expected result:

- **Source defect:** repair the implementation; retain the specification and
  theorem.
- **Model gap:** extend the model only to represent behavior needed by the
  consequential invariant, then repair the proof and regenerate cases.
- **Adapter defect:** repair and re-review the mapping, setup, observation, or
  skipped-case handling.
- **Missing or changed intent:** revise the specification with authorization,
  update the theorem, and regenerate the affected tests.
- **Environmental assumption:** make the assumption explicit and decide
  whether it belongs in the claim or outside its boundary.

Retain the unexpected behavior as a counterexample, formal case, conformance
test, or explicit assumption. Never delete a failing guarantee just to restore
a green build.

## 8. Report the result

Report:

- the behavior boundary and consequence of failure;
- specification declarations and checked theorem names;
- the modeled inputs, states, observations, and assumptions;
- generated conformance cases and the reviewed adapter;
- ordinary test commands and results;
- finite, infinite, or stateful coverage class; and
- unresolved gaps, skipped cases, and unknowns.

Say exactly what the theorem establishes and what implementation tests only
support. A source-level theorem requires checked translation evidence for its
stated frontend boundary. Finite conformance tests do not turn an incomplete
model into a complete specification.
