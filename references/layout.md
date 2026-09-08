# Project layout

Use this project structure. Create only the files required by the current proof.

```text
project/
├── <source directories>/
└── formal/
    ├── lakefile.toml
    ├── lean-toolchain
    ├── provenance.yaml
    ├── model.lean             # imports the current model modules
    ├── spec.lean              # imports the current spec modules
    ├── proof.lean             # imports the current proof modules
    ├── model/                 # demand-driven models, mirroring source paths
    │   └── src/auth/token.lean
    ├── spec/                  # normative intent grouped by feature or domain
    │   └── TokenPolicy.lean
    ├── proof/                 # connections from models to specs
    │   └── TokenPolicy.lean
    └── .formal-spec/          # generated views, build state, delivered library
        ├── LibSpec/
        └── provenance.html
```

## Directory contract

`formal/model/` mirrors source-relative directories. Replace the source
extension with `.lean`. For example, `src/auth/token.ts` maps to
`formal/model/src/auth/token.lean`. If two source files differ only by extension,
append a short extension suffix such as `token_ts.lean`. Encode path components
only when Lean's module rules require it. Record the exact physical mapping in
provenance, so the mapping remains unambiguous.

Put user intent in `formal/spec/`. Organize it by the concepts users recognize,
not by source files. A spec can exist before an implementation.

Put theorems that connect a model to a spec in `formal/proof/`. Small helper
lemmas can remain beside the definition they explain. Do not copy source
behavior into the spec or restate the spec in the model.

`formal/.formal-spec/` contains replaceable support: the materialized `LibSpec`,
Lake output, and the generated provenance view. Do not put normative definitions
or proofs there.

Do not add permanent language adapters, whole-project translators, compiler
snapshots, generated semantic trees, or a general abstraction layer. A small
one-off script is acceptable when it removes mechanical work for the current
proof. Keep it only if regeneration or review will need it again.

## Lake dependency

Materialize `LibSpec` from the installed skill and reference it locally:

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

The three small root modules import the artifacts that currently exist below
their matching directories. This keeps the physical separation while giving
Lake one source root, so proofs can import both model and spec modules.

Pin the project's `lean-toolchain` to the same Lean release as the delivered
library. Run the materializer with `--check` in repeatable validation workflows.
