# formal-spec

An agent skill for proof-first development with Lean. Agents write only the
specifications, source models, and proofs needed for the current change. There
are no language backends or compiler integrations.

Install it for any supported agent:

```sh
npx skills add <owner>/formal-spec
```

The delivery includes the reusable [`LibSpec`](LibSpec/) Lean package and a
source-only [provenance checker](scripts/check_provenance.py). See
[`SKILL.md`](SKILL.md) for the workflow and project layout.
