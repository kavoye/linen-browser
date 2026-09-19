#!/usr/bin/env python3
"""Compare OpenAI's published SDK contract with a reviewed snapshot. No API key is used.

New fields/events require review, not an automatic dependency upgrade. The fetched
Python is parsed as syntax and is never imported or executed.
"""

import argparse
import ast
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen


BASE = "https://raw.githubusercontent.com/openai/openai-python/main/src/openai/types/responses/"
FILES = {
    "create_fields": "response_create_params.py",
    "output_variants": "response_output_item.py",
    "event_variants": "response_stream_event.py",
}


def snapshot():
    result = {"source": BASE, "contracts": {}}
    for kind, name in FILES.items():
        with urlopen(BASE + name, timeout=30) as response:
            data = response.read(2_000_001)
        if len(data) > 2_000_000:
            raise ValueError("Unexpectedly large contract")
        tree = ast.parse(data.decode())
        if kind == "create_fields":
            values = sorted({node.target.id for group in tree.body if isinstance(group, ast.ClassDef)
                             and group.name.startswith("ResponseCreateParams") for node in group.body
                             if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name)})
        else:
            alias = "ResponseOutputItem" if kind == "output_variants" else "ResponseStreamEvent"
            definition = next(node.value for node in tree.body if isinstance(node, ast.AnnAssign)
                              and isinstance(node.target, ast.Name) and node.target.id == alias)
            values = sorted({item.id for node in ast.walk(definition) if isinstance(node, ast.Subscript)
                             and isinstance(node.value, ast.Name) and node.value.id == "Union"
                             and isinstance(node.slice, ast.Tuple) for item in node.slice.elts
                             if isinstance(item, ast.Name)})
        if not values:
            raise ValueError("Upstream contract layout changed; inspect the source")
        result["contracts"][kind] = {"url": BASE + name, "sha256": hashlib.sha256(data).hexdigest(), "values": values}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--record", action="store_true", help="Write a new snapshot for explicit review")
    args = parser.parse_args()
    current = snapshot()
    if args.record:
        args.baseline.parent.mkdir(parents=True, exist_ok=True)
        args.baseline.write_text(json.dumps(current, indent=2) + "\n")
        print("Recorded contract snapshot. This does not certify feature support.")
        return
    baseline = json.loads(args.baseline.read_text())
    changes = {}
    changed_sources = []
    for kind, contract in current["contracts"].items():
        previous = set(baseline["contracts"][kind]["values"])
        observed = set(contract["values"])
        if baseline["contracts"][kind]["sha256"] != contract["sha256"]:
            changed_sources.append(kind)
        if previous != observed:
            changes[kind] = {"added": sorted(observed - previous), "removed": sorted(previous - observed)}
    print(json.dumps({"review_required": bool(changed_sources), "changed_sources": changed_sources, "changes": changes}, indent=2))
    if changed_sources:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
