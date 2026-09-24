#!/usr/bin/env python3

"""Run CI tests and stop xcodebuild if it hangs after the test summary."""

from __future__ import annotations

import os
import queue
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path


SUITE_SUMMARY = re.compile(r"Test run with \d+ tests? in \d+ suites? (?:passed|failed)")
TOTAL_LIMIT_SECONDS = int(os.getenv("LINEN_CI_TEST_LIMIT_SECONDS", 20 * 60))
FINALIZATION_LIMIT_SECONDS = int(os.getenv("LINEN_CI_FINALIZATION_LIMIT_SECONDS", 2 * 60))


def capture_diagnostics(process_id: int) -> None:
    directory = Path("build/ci-diagnostics")
    directory.mkdir(parents=True, exist_ok=True)
    processes = subprocess.run(
        ["ps", "-axo", "pid,ppid,stat,etime,command"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    (directory / "processes.txt").write_text(processes)
    targets = [("xcodebuild", process_id)]
    for line in processes.splitlines():
        if "/Linen.app/Contents/MacOS/Linen" in line:
            targets.append(("Linen", int(line.split()[0])))
            break
    for name, pid in targets:
        try:
            subprocess.run(
                ["sample", str(pid), "5", "-file", str(directory / f"{name}.txt")],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=15,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass


def stop(process: subprocess.Popen[str]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def main() -> int:
    command = sys.argv[1:]
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        print("usage: run-xcodebuild-with-watchdog.py -- xcodebuild test ...", file=sys.stderr)
        return 2

    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        start_new_session=True,
    )
    lines: queue.Queue[str | None] = queue.Queue()

    def read_output() -> None:
        assert process.stdout is not None
        try:
            for line in process.stdout:
                lines.put(line)
        finally:
            lines.put(None)

    threading.Thread(target=read_output, daemon=True).start()
    deadline = time.monotonic() + TOTAL_LIMIT_SECONDS
    saw_summary = False
    output_closed = False
    while True:
        try:
            line = lines.get(timeout=0.5)
        except queue.Empty:
            line = ""
        if line is None:
            output_closed = True
        if line:
            print(line, end="", flush=True)
            if not saw_summary and SUITE_SUMMARY.search(line):
                saw_summary = True
                deadline = min(deadline, time.monotonic() + FINALIZATION_LIMIT_SECONDS)
        if output_closed and process.poll() is not None:
            return process.wait()
        if time.monotonic() >= deadline:
            reason = "test result finalization" if saw_summary else "test command"
            print(f"::error::{reason} exceeded its time limit; saving process diagnostics", flush=True)
            try:
                capture_diagnostics(process.pid)
            except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                print(f"::warning::could not save all process diagnostics: {error}", flush=True)
            finally:
                stop(process)
            return 124


if __name__ == "__main__":
    sys.exit(main())
