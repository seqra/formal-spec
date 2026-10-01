# Model-derived conformance testing

Use model-derived tests when a specification has concrete observations that
can be executed. The model supplies an oracle, a declared domain supplies the
denominator, and a small adapter runs the real implementation. This is useful
finite evidence about the executable. When a checked translation theorem also
exists, report its source-semantic guarantee separately from runtime results.

## Start with the observed behavior

Define the input, output, and effects that the claim actually observes. A pure
operation can use an executable oracle of the form `Input → Output`. A stateful
operation can use a state/action case and an expected next state or observed
result. Keep the oracle independent of the candidate implementation. If it
reuses the same helper or branch, it can repeat the same bug.

For an operation that is only a proposition, a proof can still establish a
symbolic guarantee, but it cannot by itself emit executable input/output
vectors. Add a computable observation when runtime conformance is part of the
claim.

## Finite domains need three proofs

`LibSpec.FiniteDomain` represents a finite portion of an input type with three
obligations:

```lean
structure FiniteDomain (Input : Type) where
  cases : List Input
  contains : Input → Prop
  sound : ∀ input, input ∈ cases → contains input
  complete : ∀ input, contains input → input ∈ cases
  nodup : cases.Nodup
```

These obligations mean different things:

- `sound` says every listed case belongs to the declared domain;
- `complete` says every case in the declared domain appears in the list; and
- `nodup` says the denominator is not inflated by duplicate vectors.

Only after all three are proved may a report call the enumeration exhaustive
for `contains`. `LibSpec.testVectors` maps an executable oracle over that list,
and `conformsOn_of_all_cases` turns successful checks of every listed case into
conformance over the declared domain.

A finite domain can contain state/action pairs rather than just function
inputs. For example, the inventory demo declares `stock` from `0` through `5`,
`reserved` from `0` through `stock`, and `quantity` from `0` through `5`. That
is 126 unique state/action cases. It is exhaustive for that declaration, not
for arbitrary natural numbers.

## Let the proof choose the corner cases

Do not enumerate a few natural numbers and call the result exhaustive over
`Nat`. Prove the property symbolically, then read a finite implementation suite
from the proof's structure. Good cases include:

- both sides of every guard;
- the exact equality point and one value on either side;
- every constructor and modeled transition;
- empty, zero, initial, and terminal states when they change behavior; and
- every counterexample found while refining the specification or model.

For an infinite input type, a finite behavior partition can make this choice
systematic. The model-side partition should establish that:

1. every input belongs to one of the declared classes;
2. the classes do not overlap, or the overlap is handled explicitly; and
3. the expected model behavior is characterized within each class.

For a timeout, a useful partition might be `age < limit`, `age = limit`, and
`age > limit`. For a guarded quantity, it might be `quantity ≤ available` and
`quantity > available`. Generate representatives at and around each boundary,
including values on which the expected observation depends.

Report the result as proof-derived corner cases, such as `5/5 proof-derived
boundary cases`, rather than `100% of inputs`. A representative from every
model class does not prove that an arbitrary implementation behaves uniformly
throughout each class. The symbolic theorem remains the exhaustive claim about
the model; the finite suite checks the implementation at the proof's semantic
boundaries.

## Symbolic proofs are not runtime enumeration

A theorem such as

```lean
∀ state action, Safe state → step state action = next → Safe next
```

can cover an infinite type symbolically. Lean checks the proof term and its
assumptions; it does not execute a test vector for every natural number. Report
this as a symbolic preservation theorem over the modeled relation, not as an
exhaustive runtime test.

The same distinction applies to a theorem with premises. State the premises,
the quantified types, and the effects excluded from the model. A theorem about
the model does not automatically establish that production source follows the
model.

## Finite pairs do not mean finite traces

Even when states and actions are finite, a transition system can have
infinitely many traces because it can loop. Enumerating every finite
state/action pair can establish one-step conformance for the declared graph;
it does not enumerate every length of execution.

Use `LibSpec.TransitionSystem.Reachable` and an invariant-preservation theorem
when the claim is about every reachable trace. Prove the invariant for initial
states, prove that every permitted step preserves it, and then use induction on
reachability. If the claim is intentionally bounded by a trace length, state
that bound and include it in the denominator.

## The oracle and adapter must be executable

Generated vectors require a computable oracle and a representation that can
cross the test boundary. A practical vector therefore needs:

- concrete input fields that can be serialized and parsed;
- an expected observation produced by the model, not by the candidate;
- a stable encoding for values, errors, and relevant effects; and
- an adapter that maps the vector into the implementation and normalizes its
  observed result.

The adapter is a reviewed boundary. Check that it does not change units,
default missing fields, discard errors, or observe less than the specification
claims. Keep it small and project-owned. A successful comparison proves that
the adapted implementation agrees with the executable oracle on the declared
vectors. It does not prove unobserved effects or source/model equivalence.

If values contain functions, proofs, open handles, or other non-serializable
objects, either define a concrete observation or keep the claim symbolic. Do
not silently replace an unexecutable oracle with a copy of the implementation.

## Report a denominator every time

Use precise scope in command output and documentation:

- `126/126 declared state/action vectors`;
- `5/5 proof-derived boundary cases from 3 complete model classes`;
- `all reachable states of the modeled transition system, by invariant
  induction`; or
- `42/50 sampled vectors in the bounded domain`.

Never write only `100% tested`. The reader must be able to tell what was
enumerated, what was proved symbolically, what was sampled, and which adapter
and effects were outside the claim.

## Generate on demand

Vectors are replaceable build output. Generate them when a review or
conformance run needs them, usually under `formal/.formal-spec/` or a temporary
directory, and regenerate them after the model changes. Do not check in a
large permanent vector corpus or grow a general-purpose language backend to
produce one.

The inventory storyboard uses this shape visually: a symbolic preservation
theorem exposes the guard `reserved + ship ≤ stock`; equality and one step past
equality become implementation cases; the failing case is retained after the
guard is corrected. The symbolic theorem remains the evidence for arbitrary
modeled natural-number transitions, while the finite cases supply concrete
implementation feedback.
