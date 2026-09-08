#!/usr/bin/env python3
"""Validate source/model/spec/proof wiring and optionally render an HTML view."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import quote


SHA256 = re.compile(r"[0-9a-f]{64}")
BINDING_FIELDS = {
    "id",
    "source",
    "source_anchor",
    "source_sha256",
    "model",
    "model_anchor",
}
PROOF_FIELDS = {
    "id",
    "spec",
    "spec_anchor",
    "model",
    "model_anchor",
    "proof",
    "proof_anchor",
}


class ProvenanceError(ValueError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path, help="JSON-compatible YAML wiring file")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="project root")
    parser.add_argument("--html", type=Path, help="write the visual provenance view")
    return parser.parse_args()


def load_manifest(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ProvenanceError(f"manifest does not exist: {path}") from error
    except json.JSONDecodeError as error:
        raise ProvenanceError(
            f"manifest must use dependency-free JSON-compatible YAML: {error}"
        ) from error
    if not isinstance(value, dict):
        raise ProvenanceError("manifest root must be an object")
    if set(value) != {"version", "bindings", "proofs"}:
        raise ProvenanceError("manifest fields must be exactly: version, bindings, proofs")
    if value["version"] != 1:
        raise ProvenanceError("manifest version must be 1")
    if not isinstance(value["bindings"], list) or not isinstance(value["proofs"], list):
        raise ProvenanceError("bindings and proofs must be arrays")
    return value


def require_record(value: object, fields: set[str], kind: str, index: int) -> dict:
    if not isinstance(value, dict):
        raise ProvenanceError(f"{kind}[{index}] must be an object")
    if set(value) != fields:
        missing = sorted(fields - set(value))
        extra = sorted(set(value) - fields)
        raise ProvenanceError(
            f"{kind}[{index}] has wrong fields; missing={missing}, extra={extra}"
        )
    for field in fields:
        if not isinstance(value[field], str) or not value[field]:
            raise ProvenanceError(f"{kind}[{index}].{field} must be a non-empty string")
    return value


def resolve_project_file(root: Path, relative: str, label: str) -> Path:
    candidate_path = Path(relative)
    if candidate_path.is_absolute():
        raise ProvenanceError(f"{label} must be relative: {relative}")
    candidate = (root / candidate_path).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise ProvenanceError(f"{label} escapes the project root: {relative}") from error
    if not candidate.is_file():
        raise ProvenanceError(f"{label} does not exist: {relative}")
    return candidate


def require_anchor(path: Path, anchor: str, label: str) -> None:
    try:
        contents = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise ProvenanceError(f"{label} is not UTF-8 text: {path}") from error
    if anchor not in contents:
        raise ProvenanceError(f"{label} anchor not found in {path}: {anchor!r}")


def validate(manifest: dict, root: Path) -> tuple[list[dict], list[dict]]:
    bindings = [
        require_record(item, BINDING_FIELDS, "bindings", index)
        for index, item in enumerate(manifest["bindings"])
    ]
    proofs = [
        require_record(item, PROOF_FIELDS, "proofs", index)
        for index, item in enumerate(manifest["proofs"])
    ]
    ids = [item["id"] for item in [*bindings, *proofs]]
    if len(ids) != len(set(ids)):
        raise ProvenanceError("binding and proof IDs must be unique")

    bound_models: set[str] = set()
    for binding in bindings:
        source = resolve_project_file(root, binding["source"], "source")
        model = resolve_project_file(root, binding["model"], "model")
        require_anchor(source, binding["source_anchor"], "source")
        require_anchor(model, binding["model_anchor"], "model")
        expected_hash = binding["source_sha256"]
        if not SHA256.fullmatch(expected_hash):
            raise ProvenanceError(
                f"binding {binding['id']} source_sha256 must be lowercase SHA-256"
            )
        actual_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        if actual_hash != expected_hash:
            raise ProvenanceError(
                f"binding {binding['id']} source hash changed: expected "
                f"{expected_hash}, got {actual_hash}"
            )
        if binding["model"] in bound_models:
            raise ProvenanceError(f"model has more than one source binding: {binding['model']}")
        bound_models.add(binding["model"])

    proved_models: set[str] = set()
    for proof_link in proofs:
        if proof_link["model"] not in bound_models:
            raise ProvenanceError(
                f"proof {proof_link['id']} uses an unbound model: {proof_link['model']}"
            )
        for role in ("spec", "model", "proof"):
            path = resolve_project_file(root, proof_link[role], role)
            require_anchor(path, proof_link[f"{role}_anchor"], role)
        proved_models.add(proof_link["model"])

    missing_proofs = sorted(bound_models - proved_models)
    if missing_proofs:
        raise ProvenanceError(f"models without a proof connection: {missing_proofs}")
    return bindings, proofs


def relative_link(report: Path, root: Path, project_path: str) -> str:
    target = root / project_path
    relative = os.path.relpath(target, report.parent)
    return quote(relative.replace(os.sep, "/"), safe="/._-")


def render_html(report: Path, root: Path, bindings: list[dict], proofs: list[dict]) -> str:
    proof_rows = []
    binding_by_model = {item["model"]: item for item in bindings}
    for proof_link in proofs:
        binding = binding_by_model[proof_link["model"]]
        cells = []
        for role, path, anchor in (
            ("Source", binding["source"], binding["source_anchor"]),
            ("Model", proof_link["model"], proof_link["model_anchor"]),
            ("Spec", proof_link["spec"], proof_link["spec_anchor"]),
            ("Proof", proof_link["proof"], proof_link["proof_anchor"]),
        ):
            cells.append(
                '<div class="artifact"><strong>{}</strong><a href="{}">{}</a>'
                '<code>{}</code></div>'.format(
                    role,
                    relative_link(report, root, path),
                    html.escape(path),
                    html.escape(anchor),
                )
            )
        proof_rows.append(
            '<section><h2>{}</h2><div class="flow">{}</div><p>Source SHA-256: '
            '<code>{}</code></p></section>'.format(
                html.escape(proof_link["id"]),
                '<span class="arrow">→</span>'.join(cells),
                html.escape(binding["source_sha256"]),
            )
        )
    document = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Formal provenance</title><style>
body{font:15px system-ui,sans-serif;max-width:1200px;margin:2rem auto;padding:0 1rem;color:#17202a}
section{border:1px solid #ccd1d1;border-radius:10px;padding:1rem;margin:1rem 0}.flow{display:flex;align-items:stretch;gap:.6rem;overflow:auto}
.artifact{display:flex;flex-direction:column;min-width:180px;background:#f7f9f9;padding:.75rem;border-radius:7px}.artifact a{margin:.4rem 0}.arrow{align-self:center;font-size:1.4rem}code{font-size:.82em;overflow-wrap:anywhere}
@media(max-width:700px){.flow{flex-direction:column}.arrow{transform:rotate(90deg)}}
</style></head><body><h1>Formal provenance</h1><p>Visual source → model → spec → proof wiring.</p>
__PROOF_ROWS__\n</body></html>\n"""
    return document.replace("__PROOF_ROWS__", "\n".join(proof_rows))


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    try:
        manifest = load_manifest(args.manifest.resolve())
        bindings, proofs = validate(manifest, root)
        if args.html:
            report = args.html if args.html.is_absolute() else root / args.html
            report = report.resolve()
            report.parent.mkdir(parents=True, exist_ok=True)
            report.write_text(render_html(report, root, bindings, proofs), encoding="utf-8")
            print(f"provenance valid; visual view written: {report}")
        else:
            print(f"provenance valid: {len(bindings)} bindings, {len(proofs)} proofs")
        return 0
    except (OSError, ProvenanceError) as error:
        print(f"provenance error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
