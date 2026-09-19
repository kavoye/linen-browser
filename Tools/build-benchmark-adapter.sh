#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
linen_benchmark_dd="${LINEN_BENCHMARK_DERIVED_DATA:-build/BenchmarkDD}"
linen_source_before="$(python3 Tools/benchmark-provenance.py hash)"
xcodebuild build-for-testing -project Linen.xcodeproj -scheme Linen \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$linen_benchmark_dd" \
  -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=

if [[ "$linen_source_before" != "$(python3 Tools/benchmark-provenance.py hash)" ]]; then
  echo "Sources changed during the build. Rebuild before benchmarking." >&2
  exit 1
fi
python3 Tools/benchmark-provenance.py write
