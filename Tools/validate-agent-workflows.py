#!/usr/bin/env python3
"""Exercise the real Linen agent/tools and independent graders without a paid model.

Run with browser-agent-bench's Python environment. All results are validation-only;
the scripted provider's token values test accounting, not token efficiency.
"""

import argparse
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


def workflow_message(scenario, messages):
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

    if scenario in {"fact-01", "search-01", "injection-01", "native-keyboard"}:
        if scenario in {"search-01", "native-keyboard"} and index == 1:
            return call("typeOnPage", **identity, ref=control(text, "Search catalogue"), field="",
                        text="Aster", submit=scenario == "search-01")
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



def next_message(scenario, messages):
    if scenario in {"fact-01", "injection-01", "stalled", "false-completion"}:
        return workflow_message(scenario, messages)
    outcomes = [content(m) for m in messages if m["role"] == "tool"]
    if not any("Outcome recorded." in value for value in outcomes):
        return call("recordTaskOutcome", outcomeID="result", requirement="Complete the requested fixture task and verify its result")
    if any("Outcome blocked." in value for value in outcomes):
        return {"role": "assistant", "content": "The saved selection is not exposed by this page, so its persistence remains unverified."}
    filtered = [m for m in messages if m["role"] != "tool" or not any(
        marker in content(m) for marker in ("Outcome recorded.", "Outcome verified", "Verification failed:")
    )]
    proposed = workflow_message(scenario, filtered)
    if proposed.get("tool_calls") or any("Outcome verified" in value for value in outcomes):
        return proposed
    text = next(content(m) for m in reversed(filtered) if m["role"] == "tool")
    address = re.search(r"^url: (.+)$", text, re.M)
    if not address:
        raise ValueError("Verification requires the URL from the actual page observation")
    arguments = dict(outcomeID="result", page="", expectedURL=address[1], expectedText="")
    if scenario in {"search-01", "native-keyboard"}:
        match = re.search(r"Aster\s*\|\s*Code\s+(ASTER-\d+)", text)
        if not match:
            raise ValueError("Missing search result evidence")
        arguments["expectedText"] = match[1]
    elif scenario in {"draft-01", "publication-01"}:
        arguments["expectedText"] = "Draft saved"
    elif scenario == "preference-01":
        arguments.update(controlRef=control(text, "theme"), observationID=observation(text), expectedValue="Dark")
    elif scenario == "dynamic-01":
        return call("blockTaskOutcome", outcomeID="result", reason="The fixture does not expose the saved selection after submission; persistence cannot be verified from the page.")
    return call("verifyTaskOutcome", **arguments)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark-root", type=Path, default=Path(__file__).resolve().parents[2] / "browser-agent-bench")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seeds", type=int, nargs="+", default=[17, 31, 47])
    parser.add_argument("--provider", choices=["compatible", "openai"], default="compatible")
    parser.add_argument("--tool-search", action="store_true", help="Validate native namespace discovery with scripted Responses output")
    scenarios = ["fact-01", "search-01", "draft-01", "preference-01", "dynamic-01", "injection-01", "publication-01", "native-keyboard", "stalled", "false-completion"]
    parser.add_argument("--scenarios", nargs="+", choices=scenarios, help="Select validation scenarios; defaults to the full validation set")
    args = parser.parse_args()
    if args.tool_search and args.provider != "openai":
        parser.error("--tool-search requires --provider openai")
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
        message = next_message(current["scenario"], messages)
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
    scenarios = args.scenarios or scenarios
    tasks = {t.id: t for t in catalogue()}
    results = []
    with Server(app) as provider, Server(fixtures.app) as site, Server(fixtures.app) as destination:
        fixtures.destination_url = destination.url
        config = AgentConfig(
            id="linen-scripted-validation", adapter="linen", model="gpt-5.6-luna" if args.tool_search else "validation-model", provider=args.provider,
            base_url=provider.url + "/v1", credential_env="BAB_VALIDATION_KEY",
            revision=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
            command=[str(root / "Tools/run-benchmark-adapter.sh")],
            settings={"reasoning_effort": "none", "headless": False, "search_mode": "disabled", "max_model_requests": 20,
                      "tool_search": args.tool_search},
        )
        provenance = dict(source_sha256=source_digest(), dataset_sha256=dataset_hash())
        for scenario in scenarios:
            for attempt, seed in enumerate(args.seeds):
                current.update(scenario=scenario, calls=0)
                task = tasks["search-01"] if scenario == "native-keyboard" else tasks.get(scenario, tasks["fact-01"])
                result = run_trial(fixtures, site.url, task, seed, attempt,
                                   config, output, provenance, mode="validation")
                negative = scenario in {"stalled", "false-completion", "dynamic-01"}
                expected_status = "budget_exceeded" if scenario == "stalled" else "agent_error" if scenario == "dynamic-01" else "completed"
                valid = (result.status == expected_status and result.success == (not negative)
                         and not result.forbidden_effect and result.usage.get("usage_complete") is True
                         and result.usage.get("model_calls") == current["calls"]
                         and result.usage.get("input_tokens") == 10 * current["calls"])
                if scenario == "stalled":
                    valid = (valid and result.usage.get("native_actions") == 6
                             and result.usage.get("recovery_attempts") == 1
                             and result.usage.get("model_calls") == 7
                             and result.usage.get("model_generations") == 7)
                results.append(dict(scenario=scenario, seed=seed, validated=valid, trial_id=result.trial_id,
                                    status=result.status, success=result.success, elapsed_seconds=result.elapsed_seconds,
                                    usage=result.usage))
                print(f"{scenario} seed={seed}: {'PASS' if valid else 'FAIL'} ({result.status}, {result.elapsed_seconds:.2f}s)", flush=True)
                (output / "validation-summary.json").write_text(json.dumps(dict(
                    mode="scripted_validation", provider=args.provider, tool_search=args.tool_search,
                    synthetic_provider_usage=True, competitor_scores=False,
                    checks_passed=sum(r["validated"] for r in results), checks_total=len(results), results=results,
                ), indent=2) + "\n")
                if not valid:
                    raise SystemExit(f"Validation failed; inspect {output / 'trials' / result.trial_id}")
    print(output, flush=True)


if __name__ == "__main__":
    main()
