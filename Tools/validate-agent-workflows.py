#!/usr/bin/env python3
"""Exercise the real Linen agent/tools and independent graders without a paid model.

Run with browser-agent-bench's Python environment. All results are validation-only;
the scripted provider's token values test accounting, not token efficiency.
"""

import argparse
import base64
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid


def content(message):
    value = message.get("content", "")
    if isinstance(value, str):
        return value
    return "\n".join(p.get("text", "") for p in value or [] if isinstance(p, dict))


def call(name, **arguments):
    return {"role": "assistant", "content": None, "tool_calls": [{
        "id": "validation-" + uuid.uuid4().hex, "type": "function",
        "function": {"name": name, "arguments": json.dumps(arguments)},
    }]}


def control(text, label):
    match = re.search(r'^\[(\d+)\] [^\n]*?"' + re.escape(label) + r'"', text, re.M)
    if not match:
        raise ValueError(f"Control missing from actual observation: {label}")
    return int(match[1])


def observation(text):
    matches = re.findall(r"^observationID: (\S+)", text, re.M)
    if not matches:
        raise ValueError("Action did not return a fresh observation")
    return matches[-1]


def next_message(scenario, messages):
    outputs = [content(m) for m in messages if m["role"] == "tool"]
    if scenario == "false-completion":
        return {"role": "assistant", "content": "Done."}
    if any("browser task is paused" in content(m) for m in messages):
        return {"role": "assistant", "content": "The reads did not change the page. The task remains unfinished."}
    if not outputs or scenario == "stalled":
        return call("readPage", page="", lookingFor="")
    text = outputs[-1]
    index = len(outputs)
    identity = {"page": "", "observationID": observation(text)}

    def click(label):
        return call("clickOnPage", **identity, ref=control(text, label), label="")

    if scenario in {"fact-01", "search-01", "injection-01", "native-keyboard", "native-shortcut"}:
        if scenario in {"search-01", "native-keyboard", "native-shortcut"} and index == 1:
            return call("typeOnPage", **identity, ref=control(text, "Search catalogue"), field="",
                        text="Wrong query" if scenario == "native-shortcut" else "Aster", submit=scenario == "search-01")
        if scenario == "native-keyboard" and index == 2:
            return call("pressKey", **identity, ref=control(text, "Search catalogue"), key="Enter")
        found = re.search(r"Aster\s*\|\s*Code\s+(ASTER-\d+)\s*\|\s*\$(\d+)\s*\|\s*(\d+)\s*grams", text)
        if not found:
            raise ValueError("Required fact missing from actual page observation")
        answer = f"{found[1]}, ${found[2]}, {found[3]} grams."
        return {"role": "assistant", "content": answer}
    if scenario in {"draft-01", "publication-01"}:
        if index == 1:
            return call("fillFields", **identity, fields=[
                {"ref": control(text, label), "value": value, "select": select}
                for label, value, select in [
                    ("Title", "Trip notes", False), ("Body", "Pack the blue jacket.", False), ("Category", "Travel", True),
                ]
            ])
        if index == 2:
            return click("Save draft")
        if "Draft saved" not in text:
            raise ValueError("Saved draft was not observed")
    elif scenario == "preference-01":
        if index == 1:
            return call("selectOption", **identity, ref=control(text, "theme"), field="", option="Dark")
        if index == 2:
            return click("Save preferences")
        if index == 3:
            return click("Reload preferences")
    elif scenario == "dynamic-01":
        if index == 1:
            return click("Refresh stock")
        if index == 2:
            return call("setChecked", **identity, ref=control(text, "Select Cedar"), checked=True)
        if index == 3:
            return click("Save selection")
    else:
        raise ValueError("Unknown validation scenario")
    return {"role": "assistant", "content": "The requested changes were saved and the resulting page was inspected."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark-root", type=Path, default=Path(__file__).resolve().parents[2] / "browser-agent-bench")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seeds", type=int, nargs="+", default=[17, 31, 47])
    parser.add_argument("--provider", choices=["compatible", "openai"], default="compatible")
    parser.add_argument("--tool-search", action="store_true", help="Validate native namespace discovery with scripted Responses output")
    parser.add_argument("--computer-use", action="store_true", help="Validate native screenshots and keyboard actions through the benchmark worker")
    scenarios = ["fact-01", "search-01", "draft-01", "preference-01", "dynamic-01", "injection-01", "publication-01", "native-keyboard", "stalled", "false-completion"]
    parser.add_argument("--scenarios", nargs="+", choices=scenarios + ["native-shortcut"], help="Select validation scenarios; defaults to the full validation set")
    args = parser.parse_args()
    if args.tool_search and args.provider != "openai":
        parser.error("--tool-search requires --provider openai")
    if args.computer_use and args.provider != "openai":
        parser.error("--computer-use requires --provider openai")
    if args.scenarios and "native-shortcut" in args.scenarios and not args.computer_use:
        parser.error("native-shortcut requires --computer-use")
    sys.path.insert(0, str(args.benchmark_root.resolve() / "src"))
    from fastapi import FastAPI, Request
    from browser_agent_bench.fixtures import Fixtures
    from browser_agent_bench.runner import run_trial, source_digest
    from browser_agent_bench.schema import AgentConfig
    from browser_agent_bench.service import Server
    from browser_agent_bench.tasks import catalogue, dataset_hash

    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    os.chdir(args.benchmark_root.resolve())
    output.mkdir(parents=True, exist_ok=False)
    app = FastAPI()
    current = {}

    @app.post("/v1/chat/completions")
    async def completion(request: Request):
        value = await request.json()
        current["calls"] += 1
        message = next_message(current["scenario"], value["messages"])
        return dict(
            id="validation-" + uuid.uuid4().hex, object="chat.completion", created=0, model="validation-model",
            choices=[dict(index=0, message=message, finish_reason="tool_calls" if message.get("tool_calls") else "stop")],
            usage=dict(prompt_tokens=10, completion_tokens=10, total_tokens=20),
        )

    @app.post("/v1/responses")
    async def response(request: Request):
        value = await request.json()
        current["calls"] += 1
        messages = []
        for item in value["input"]:
            if item.get("type") == "function_call_output":
                messages.append(dict(role="tool", content=item["output"]))
            elif "role" in item:
                messages.append(item)
        message = None
        if args.computer_use:
            from PIL import Image
            assert any(tool.get("type") == "computer" for tool in value.get("tools", [])), "Native computer definition missing"
            native = [item for item in value["input"] if item.get("type") == "computer_call_output"]
            for item in native:
                image_url = item["output"]["image_url"]
                assert image_url.startswith("data:image/jpeg;base64,"), "Native screenshot missing"
                with Image.open(io.BytesIO(base64.b64decode(image_url.split(",", 1)[1], validate=True))) as image:
                    assert image.width > 0 and image.height > 0
                    image.verify()
            current["computer_outputs"] = max(current["computer_outputs"], len(native))
            outputs = [content(m) for m in messages if m["role"] == "tool"]
            if current["scenario"] in {"native-keyboard", "native-shortcut"} and len(outputs) == 2:
                phase = current["computer_phase"]
                current["computer_phase"] += 1
                if phase < 2:
                    actions = [{"type": "screenshot"}] if phase == 0 else [{"type": "keypress", "keys": ["ENTER"]}]
                    if phase == 1 and current["scenario"] == "native-shortcut":
                        actions = [{"type": "keypress", "keys": ["CTRL", "A"]}, {"type": "type", "text": "Aster"}] + actions
                    return dict(id="resp_" + uuid.uuid4().hex, object="response", status="completed", model=value["model"],
                                output=[dict(type="computer_call", id="cu_" + uuid.uuid4().hex, call_id="call_" + uuid.uuid4().hex,
                                             status="completed", actions=actions, pending_safety_checks=[])],
                                usage=dict(input_tokens=10, output_tokens=10, total_tokens=20,
                                           input_tokens_details=dict(cached_tokens=5, cache_write_tokens=0)))
                message = call("readPage", page="", lookingFor="")
        message = message or next_message(current["scenario"], messages)
        output_items = []
        for tool in message.get("tool_calls", []):
            namespace = next((item for item in value.get("tools", []) if item.get("type") == "namespace"
                              and any(member.get("name") == tool["function"]["name"] for member in item["tools"])), None)
            if namespace:
                output_items.extend([
                    dict(type="tool_search_call", id="ts_" + uuid.uuid4().hex, execution="server", status="completed", call_id=None,
                         arguments={"query": tool["function"]["name"]}),
                    dict(type="tool_search_output", id="tso_" + uuid.uuid4().hex, execution="server", status="completed", call_id=None, tools=[namespace]),
                ])
            output_items.append(dict(type="function_call", id="fc_" + uuid.uuid4().hex,
                                     call_id=tool["id"], name=tool["function"]["name"], arguments=tool["function"]["arguments"],
                                     **({"namespace": namespace["name"]} if namespace else {})))
        if message.get("content"):
            output_items.append(dict(type="message", role="assistant", status="completed", phase="final_answer",
                                     content=[dict(type="output_text", text=message["content"], annotations=[])]))
        return dict(id="resp_" + uuid.uuid4().hex, object="response", status="completed", model=value["model"],
                    output=output_items, usage=dict(input_tokens=10, output_tokens=10, total_tokens=20,
                                                   input_tokens_details=dict(cached_tokens=5, cache_write_tokens=0),
                                                   output_tokens_details=dict(reasoning_tokens=2)))

    fixtures = Fixtures()
    os.environ["BAB_VALIDATION_KEY"] = "local-validation-only"
    scenarios = args.scenarios or scenarios + (["native-shortcut"] if args.computer_use else [])
    tasks = {t.id: t for t in catalogue()}
    results = []
    with Server(app) as provider, Server(fixtures.app) as site, Server(fixtures.app) as destination:
        fixtures.destination_url = destination.url
        config = AgentConfig(
            id="linen-scripted-validation", adapter="linen", model="gpt-5.6-luna" if args.tool_search or args.computer_use else "validation-model", provider=args.provider,
            base_url=provider.url + "/v1", credential_env="BAB_VALIDATION_KEY",
            revision=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
            command=[str(root / "Tools/run-benchmark-adapter.sh")],
            settings={"reasoning_effort": "none", "headless": False, "search_mode": "disabled", "max_model_requests": 20,
                      "tool_search": args.tool_search, "computer_use": args.computer_use},
        )
        provenance = dict(source_sha256=source_digest(), dataset_sha256=dataset_hash())
        for scenario in scenarios:
            for attempt, seed in enumerate(args.seeds):
                current.update(scenario=scenario, calls=0, computer_phase=0, computer_outputs=0)
                task = tasks["search-01"] if scenario in {"native-keyboard", "native-shortcut"} else tasks.get(scenario, tasks["fact-01"])
                result = run_trial(fixtures, site.url, task, seed, attempt,
                                   config, output, provenance, mode="validation")
                negative = scenario in {"stalled", "false-completion"}
                expected_status = "budget_exceeded" if scenario == "stalled" else "completed"
                valid = (result.status == expected_status and result.success == (not negative)
                         and not result.forbidden_effect and result.usage.get("usage_complete") is True
                         and result.usage.get("model_calls") == current["calls"]
                         and result.usage.get("input_tokens") == 10 * current["calls"])
                if scenario == "stalled":
                    valid = (valid and result.usage.get("native_actions") == 6
                             and result.usage.get("recovery_attempts") == 1
                             and result.usage.get("model_calls") == 7
                             and result.usage.get("model_generations") == 7)
                if args.computer_use and scenario in {"native-keyboard", "native-shortcut"}:
                    valid = valid and current["computer_outputs"] == 2 and result.usage.get("computer_calls") == 2
                results.append(dict(scenario=scenario, seed=seed, validated=valid, trial_id=result.trial_id,
                                    status=result.status, success=result.success, elapsed_seconds=result.elapsed_seconds,
                                    usage=result.usage, computer_outputs=current["computer_outputs"]))
                print(f"{scenario} seed={seed}: {'PASS' if valid else 'FAIL'} ({result.status}, {result.elapsed_seconds:.2f}s)", flush=True)
                (output / "validation-summary.json").write_text(json.dumps(dict(
                    mode="scripted_validation", provider=args.provider, tool_search=args.tool_search, computer_use=args.computer_use,
                    synthetic_provider_usage=True, competitor_scores=False,
                    checks_passed=sum(r["validated"] for r in results), checks_total=len(results), results=results,
                ), indent=2) + "\n")
                if not valid:
                    raise SystemExit(f"Validation failed; inspect {output / 'trials' / result.trial_id}")
    print(output, flush=True)


if __name__ == "__main__":
    main()
