#!/bin/sh

set -eu

result_bundle="${1:-build/TestResults.xcresult}"
minimum="${2:-20.0}"
target="${3:-Linen.app}"

if [ ! -d "$result_bundle" ]; then
  echo "error: coverage result bundle not found: $result_bundle" >&2
  exit 1
fi

report="$(xcrun xccov view --report --only-targets "$result_bundle")"
printf '%s\n' "$report"

coverage="$(printf '%s\n' "$report" | awk -v target="$target" '$2 == target { value = $4; sub(/%.*/, "", value); print value }')"

case "$coverage" in
  ''|*[!0-9.]*)
    echo "error: could not read coverage for $target" >&2
    exit 1
    ;;
esac

if ! awk -v coverage="$coverage" -v minimum="$minimum" 'BEGIN { exit !(coverage >= minimum) }'; then
  echo "error: $target coverage is $coverage%; the minimum is $minimum%" >&2
  exit 1
fi

echo "$target coverage: $coverage% (minimum: $minimum%)"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '### Test coverage\n\n%s: **%s%%** (minimum: %s%%)\n' \
    "$target" "$coverage" "$minimum" >> "$GITHUB_STEP_SUMMARY"
fi
