#!/usr/bin/env python3
"""Summarize a paired Linen tool-search probe; never label it a browser benchmark."""

import argparse
import json
from pathlib import Path


def summarize(report):
    if report.get("mode") != "paired_tool_search" or report.get("status") != "passed":
        raise ValueError("Expected a completed paired_tool_search report")
    checks = report.get("checks", [])
    requests = report.get("requests", [])
    expected = {f"{case}_{mode}" for case in ("tabs", "checkbox", "dropdown") for mode in ("direct", "deferred")}
    if len(checks) != 6 or {item.get("name") for item in checks} != expected:
        raise ValueError("Missing or duplicate comparison checks")
    for item in checks:
        if not all(item.get(key) is True for key in ("passed", "arguments_verified", "native_continuation_passed")):
            raise ValueError("An execution contract was not verified")
    labels = {f"{name}_{phase}" for name in expected for phase in ("proposal", "continuation")}
    if len(requests) != 12 or {item.get("check") for item in requests} != labels:
        raise ValueError("Missing or duplicate measured requests")
    if any(item.get("status") != "completed" for item in requests):
        raise ValueError("A measured request did not complete")

    def metrics(rows):
        totals = {key: sum(int(row["usage"][key]) for row in rows)
                  for key in ("input_tokens", "output_tokens", "cached_tokens")}
        totals["uncached_input_tokens"] = totals["input_tokens"] - totals["cached_tokens"]
        totals["elapsed_ms_sum"] = sum(row["elapsed_ms"] for row in rows)
        totals["request_count"] = len(rows)
        return totals

    result = {
        "model": report["model"], "source_sha256": report["source_sha256"],
        "local_tool_count": report["local_tool_count"], "competitive_score": False,
        "scope": "Three paired synthetic tool-routing and continuation probes; no browser actions executed",
        "cost_measured": False, "modes": {}, "cases": {},
    }
    for mode in ("direct", "deferred"):
        result["modes"][mode] = metrics([row for row in requests if f"_{mode}_" in row["check"]])
    for case in ("tabs", "checkbox", "dropdown"):
        result["cases"][case] = {mode: metrics([row for row in requests if row["check"].startswith(f"{case}_{mode}_")])
                                  for mode in ("direct", "deferred")}
    direct, deferred = (result["modes"][mode] for mode in ("direct", "deferred"))
    result["change_percent"] = {key: round((deferred[key] / direct[key] - 1) * 100, 2)
                                for key in ("input_tokens", "output_tokens", "uncached_input_tokens", "elapsed_ms_sum")}
    result["limitations"] = [
        "One observation per case and mode; latency differences are not statistically established",
        "Prompt caching was observed, not controlled or equalized; gross token savings do not prove lower cost",
        "Synthetic tool results verify API continuation, not browser state changes or competitor parity",
    ]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(summarize(json.loads(args.report.read_text())), indent=2))
    except (KeyError, TypeError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
