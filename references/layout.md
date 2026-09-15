# Project layout

Keep the formal work beside the source it explains. Create only the files
needed for the current behavior claim.

```text
project/
├── <source directories>/
└── formal/
    ├── lakefile.toml
    ├── lean-toolchain
    ├── model.lean             # imports the current model modules
    ├── spec.lean              # imports the current specification modules
    ├── proof.lean             # imports the current proof modules
    ├── model/                 # small, demand-driven behavior models
    │   └── src/auth/token.lean
    ├── spec/                  # normative intent, grouped by feature
    │   └── TokenPolicy.lean
    ├── proof/                 # theorems connecting models to specifications
    │   └── TokenPolicy.lean
    └── .formal-spec/          # replaceable generated support
        ├── LibSpec/
        ├── index.md
        ├── vocabulary.md
        ├── spec/              # readable Markdown mirroring formal/spec/
        ├── model/             # readable Markdown mirroring formal/model/
        ├── proof/             # readable Markdown mirroring formal/proof/
        └── test-vectors/
```

## One job per directory

`formal/spec/` contains the behavior the product is meant to guarantee. Keep
these declarations independent of the current implementation. Organize them
around concepts people recognize, such as `TokenPolicy` or `Inventory`, rather
than copying the source tree.

`formal/model/` contains only the source behavior a proof or an executable
oracle needs. A model can be a function, relation, state machine, or other
small Lean definition. It is not a translation of the whole project and it is
not a language backend. When mirroring a source path makes review easier,
`src/auth/token.ts` can have a model at
`formal/model/src/auth/token.lean`. A source file does not need a model merely
because it exists.

`formal/proof/` contains the theorems that connect the model to the
specification. Keep the proof visibly dependent on both sides. Invariant
proofs also explain why the guarantee survives every modeled transition, not
just the examples chosen for a test run.

The three root files, `model.lean`, `spec.lean`, and `proof.lean`, import the
modules that currently exist below their matching directories. This gives Lake
stable build targets without requiring empty placeholder modules.

`formal/.formal-spec/` is disposable support. The materialized `LibSpec`, a
generated readable specification, and generated model-derived test vectors may
live there. Do not put normative declarations or hand-written proofs in this
directory. Delete and regenerate its contents when the formal build requires
it.

## Lake setup

Materialize the delivered library into a project's local formal build area:

```sh
python3 <skill-dir>/scripts/materialize_libspec.py --project <project-root>
```

Use a local Lake dependency and keep the Lean release aligned with the
materialized library:

```toml
name = "project-formal"
version = "0.1.0"
defaultTargets = ["ProjectFormal"]

[[require]]
name = "libspec"
path = ".formal-spec/LibSpec"

[[lean_lib]]
name = "ProjectFormal"
roots = ["model", "spec", "proof"]
```

Pin `lean-toolchain` to the release used by `LibSpec`. Build from the formal
directory:

```sh
(cd formal && lake build)
```

## Keep generated work on demand

Readable reports and finite test vectors are views of the current declarations
and model. Generate them when a review or conformance run needs them. Do not
turn generated vectors into a permanent source tree, a compiler snapshot, or a
general source-language adapter. If repeated regeneration is useful, keep the
small generator and its proof obligations close to the feature it serves.

The Lean theorem still states the guarantee. A test adapter can execute the
source implementation against generated cases, but that adapter is a reviewed
boundary and is not supplied by the directory layout itself.
