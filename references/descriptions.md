# Readable specification descriptions

The Lean declaration in `formal/spec/` is the normative account of behavior.
Readable descriptions help people inspect that account; they do not replace
the declaration, its proofs, or source correspondence.

## Authoring contract

Give each public specification declaration an adjacent Lean declaration
docstring (`/-- ... -/`). Describe the intent, boundary, assumptions, and
important accepted or rejected cases in prose. Keep the formal predicate or
relation in Lean; do not duplicate its expression in Markdown, YAML, or a
second definition.

Register public specifications explicitly for description generation. A
registry entry should identify the qualified Lean declaration and its source
module (and, when the surrounding tooling uses anchors, its source anchor).
Do not scan an entire environment for `def` declarations: that includes
helpers and imported library declarations and makes the public specification
surface implicit.

## Generation

The optional `describe-spec` Lean executable reads that registry and emits a
Markdown report. Run it only when a readable view is needed:

```sh
(cd formal && lake exe describe-spec) > formal/.formal-spec/spec.md
```

The report is generated output and belongs under `formal/.formal-spec/`; it is
safe to delete and regenerate. It should include, for every registered
declaration:

- the qualified declaration name and source location;
- the declaration docstring; and
- an exact rendering of the formal statement.

The exact rendering is useful for checking what Lean actually elaborated. It
is not a promise that arbitrary Lean expressions can be translated faithfully
to natural language. Generation should fail for an unknown declaration,
duplicate registry entry, or missing/non-empty docstring rather than silently
producing an incomplete report.

The report may carry a source fingerprint or generator version so stale output
is visible, but it should not be used as a semantic cache. If a declaration
changes while its docstring does not, a human review is still required.

## Boundaries and limits

Descriptions are documentation, not evidence that a model refines a spec. The
proof modules retain that guarantee, and the provenance checker retains only
the artifact-identity and wiring checks it documents. Keep description
generation separate from the dependency-free provenance validator: the latter
must not invoke Lean, a parser, a language server, or an external service.

Do not build a general Lean-to-English translator, infer intent from models or
proofs, or use LLM-generated prose as a checked artifact. Such approaches can
omit quantifier scope, conjunction clauses, assumptions, or boundary cases.
When repeated projects need machine-readable fields beyond prose, add a small
typed metadata shape to the explicit registry and keep the Lean declaration
as the only normative statement.
