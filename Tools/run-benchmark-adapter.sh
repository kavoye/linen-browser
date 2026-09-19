#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
linen_benchmark_dd="${LINEN_BENCHMARK_DERIVED_DATA:-build/BenchmarkDD}"
: "${BAB_CONTROL_URL:?Missing benchmark control URL}"
: "${BAB_CONTROL_TOKEN:?Missing benchmark control token}"
export TEST_RUNNER_BAB_CONTROL_URL="$BAB_CONTROL_URL"
export TEST_RUNNER_BAB_CONTROL_TOKEN="$BAB_CONTROL_TOKEN"
export TEST_RUNNER_BAB_PROVIDER_KEY="${BAB_PROVIDER_KEY:?Missing selected provider key}"
python3 Tools/benchmark-provenance.py verify
export TEST_RUNNER_BAB_LINEN_REVISION="$(git rev-parse HEAD)"
export TEST_RUNNER_BAB_LINEN_SOURCE_SHA256="$(python3 Tools/benchmark-provenance.py hash)"
exec xcodebuild test-without-building -project Linen.xcodeproj -scheme Linen \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$linen_benchmark_dd" \
  -only-testing:LinenTests/BrowserAgentBenchWorker -parallel-testing-enabled NO \
  -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 300 \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=
