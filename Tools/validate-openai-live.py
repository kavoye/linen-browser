#!/usr/bin/env python3
"""Opt-in live acceptance through Linen's native Swift OpenAI adapter.

Defaults to a local credential preflight with no API requests. --live enables
bounded paid calls; --hosted-tools additionally enables search, code and images.
Credentials stay in the test host's Keychain or inherited process environment.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Fresh output directory")
    parser.add_argument("--derived-data", type=Path, default=ROOT / "build/OpenAILiveDD")
    parser.add_argument("--model", help="Exact model ID; otherwise use Linen's configured OpenAI model")
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--hosted-tools", action="store_true")
    parser.add_argument("--hosted-only", action="store_true", help="Validate hosted tools and artifacts without repeating core checks")
    parser.add_argument("--voice-only", action="store_true", help="Generate synthetic speech and transcribe it; never opens the microphone")
    parser.add_argument("--tool-search-only", action="store_true", help="Compare direct and deferred browser tool catalogs with synthetic results")
    parser.add_argument("--mcp-only", action="store_true", help="Validate a public read-only remote MCP tool and native approval continuation")
    parser.add_argument("--shell-only", action="store_true", help="Validate hosted shell file generation, download and container continuation")
    parser.add_argument("--conversation-only", action="store_true", help="Validate a synthetic Realtime conversation without microphone or speaker access")
    parser.add_argument("--files-only", action="store_true", help="Validate native PDF input")
    parser.add_argument("--adhoc", action="store_true", help="Use ad-hoc signing; saved app Keychain keys may be inaccessible")
    args = parser.parse_args()
    if args.shell_only and (not args.live or any((args.hosted_tools, args.hosted_only, args.voice_only, args.files_only, args.conversation_only, args.mcp_only, args.tool_search_only))):
        parser.error("--shell-only requires --live and cannot be combined with other acceptance modes")
    if (args.hosted_tools or args.hosted_only) and not args.live:
        parser.error("--hosted-tools and --hosted-only require --live")
    if args.voice_only and (not args.live or args.hosted_tools or args.hosted_only):
        parser.error("--voice-only requires --live and cannot be combined with hosted tools")
    if args.files_only and (not args.live or args.hosted_tools or args.hosted_only or args.voice_only):
        parser.error("--files-only requires --live and cannot be combined with other acceptance modes")
    if args.conversation_only and (not args.live or args.hosted_tools or args.hosted_only or args.voice_only or args.files_only):
        parser.error("--conversation-only requires --live and cannot be combined with other acceptance modes")
    if args.mcp_only and (not args.live or args.hosted_tools or args.hosted_only or args.voice_only or args.files_only or args.conversation_only):
        parser.error("--mcp-only requires --live and cannot be combined with other acceptance modes")
    if args.tool_search_only and (not args.live or args.hosted_tools or args.hosted_only or args.voice_only or args.files_only or args.conversation_only or args.mcp_only):
        parser.error("--tool-search-only requires --live and cannot be combined with other acceptance modes")
    output = args.output.resolve()
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    derived = args.derived_data.resolve()
    env = dict(os.environ)
    env["LINEN_BENCHMARK_DERIVED_DATA"] = str(derived)
    for key in list(env):
        if key.startswith(("TEST_RUNNER_BAB_", "BAB_", "TEST_RUNNER_LINEN_OPENAI_")):
            del env[key]
    base = ["xcodebuild", "-project", "Linen.xcodeproj", "-scheme", "Linen", "-destination",
            "platform=macOS,arch=arm64", "-derivedDataPath", str(derived),
            "-skipMacroValidation", "-skipPackagePluginValidation"]
    if args.adhoc:
        base += ["CODE_SIGN_STYLE=Manual", "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_ENTITLEMENTS="]

    def provenance(action):
        return subprocess.check_output([sys.executable, "Tools/benchmark-provenance.py", action],
                                       cwd=ROOT, env=env, text=True).strip()

    if args.build:
        before = provenance("hash")
        print("Building the native validation test host...", flush=True)
        with (output / "build.log").open("w") as log:
            result = subprocess.run(base + ["build-for-testing"], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise SystemExit(f"Build failed. See {output / 'build.log'}")
        if before != provenance("hash"):
            raise SystemExit("Sources changed during the build; rebuild before running live validation.")
        provenance("write")
    provenance("verify")
    config = {"report_path": str(output / "report.json"), "live": args.live,
              "hosted_tools": args.hosted_tools or args.hosted_only, "hosted_only": args.hosted_only,
              "source_sha256": provenance("hash"), "voice_only": args.voice_only, "files_only": args.files_only, "conversation_only": args.conversation_only, "mcp_only": args.mcp_only, "tool_search_only": args.tool_search_only}
    config["shell_only"] = args.shell_only
    if args.model:
        config["model"] = args.model
    (output / "config.json").write_text(json.dumps(config, indent=2) + "\n")
    env["TEST_RUNNER_LINEN_OPENAI_LIVE_CONFIG"] = str(output / "config.json")
    if env.get("OPENAI_API_KEY"):
        env["TEST_RUNNER_LINEN_OPENAI_LIVE_KEY"] = env["OPENAI_API_KEY"]
    print("Running " + ("bounded live acceptance" if args.live else "credential preflight (no API requests)") + "...", flush=True)
    timed_out = False
    with (output / "test.log").open("w") as log:
        try:
            suite = ("OpenAIHostedShellLiveTests" if args.shell_only else
                     "OpenAIToolSearchLiveTests" if args.tool_search_only else
                     "OpenAIMCPLiveTests" if args.mcp_only else
                     "OpenAIConversationLiveTests" if args.conversation_only else
                     "OpenAIFileLiveTests" if args.files_only else
                     "OpenAIVoiceLiveTests" if args.voice_only else "OpenAILiveValidationTests")
            result = subprocess.run(base + ["test-without-building", "-only-testing:LinenTests/" + suite,
                "-parallel-testing-enabled", "NO", "-resultBundlePath", str(output / "tests.xcresult")],
                cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
        except subprocess.TimeoutExpired:
            timed_out = True
    report_path = output / "report.json"
    if not report_path.exists():
        raise SystemExit(f"The test host did not write a report. See {output / 'test.log'}")
    report = json.loads(report_path.read_text())
    if timed_out or (result.returncode and report.get("status") in ("running", "ready", "passed")):
        report["status"] = "interrupted" if timed_out else "test_host_failed"
        report_path.write_text(json.dumps(report, indent=2) + "\n")
    summary = {"status": report["status"], "model": report["model"], "report": str(report_path)}
    if "requests" in report:
        summary["requests"] = len(report["requests"])
    print(json.dumps(summary, indent=2))
    if report["status"] == "blocked_missing_credential":
        raise SystemExit(2)
    if report["status"] not in ("ready", "passed"):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
