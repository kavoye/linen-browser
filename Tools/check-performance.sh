#!/bin/sh

set -eu

metrics_file="${1:-build/performance-metrics.json}"

if [ ! -f "$metrics_file" ]; then
  echo "error: performance metrics not found: $metrics_file" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to read performance metrics" >&2
  exit 1
fi

check_average() {
  test_id="$1"
  metric_id="$2"
  maximum="$3"
  label="$4"
  unit="$5"

  values="$(jq -r \
    --arg test "$test_id" \
    --arg metric "$metric_id" \
    '.[]
      | select(.testIdentifier == $test)
      | .testRuns[].metrics[]
      | select(.identifier == $metric)
      | .measurements[]
      | select(type == "number")' \
    "$metrics_file")"

  if [ -z "$values" ]; then
    echo "error: missing $label metric for $test_id" >&2
    exit 1
  fi

  average="$(printf '%s\n' "$values" | awk '{ total += $1; count += 1 } END { printf "%.6f", total / count }')"
  if ! awk -v value="$average" -v maximum="$maximum" 'BEGIN { exit !(value <= maximum) }'; then
    echo "error: $label averaged $average $unit; budget is $maximum $unit" >&2
    exit 1
  fi

  echo "$label: $average $unit (budget: $maximum $unit)"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s: **%s %s** (budget: %s %s)\n' \
      "$label" "$average" "$unit" "$maximum" "$unit" >> "$GITHUB_STEP_SUMMARY"
  fi
}

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '### Performance budgets\n\n' >> "$GITHUB_STEP_SUMMARY"
fi

check_average \
  'BrowserPerformanceTests/testCreatingAUsableBlankTab()' \
  'com.apple.dt.XCTMetric_Clock.time.monotonic' \
  '0.100' \
  'First usable blank tab' \
  's'
check_average \
  'BrowserPerformanceTests/testCreatingAUsableBlankTab()' \
  'com.apple.dt.XCTMetric_Memory.physical' \
  '4096' \
  'Blank tab memory growth' \
  'kB'
check_average \
  'BrowserPerformanceTests/testSwitchingTabsInACrowdedSession()' \
  'com.apple.dt.XCTMetric_Clock.time.monotonic' \
  '0.025' \
  '500 tab activations' \
  's'
check_average \
  'BrowserPerformanceTests/testSwitchingTabsInACrowdedSession()' \
  'com.apple.dt.XCTMetric_Memory.physical' \
  '8192' \
  'Tab activation memory growth' \
  'kB'
check_average \
  'BrowserPerformanceTests/testCommandPaletteHistoryRanking()' \
  'com.apple.dt.XCTMetric_Clock.time.monotonic' \
  '0.010' \
  '500-entry palette query' \
  's'
check_average \
  'BrowserPerformanceTests/testCommandPaletteHistoryRanking()' \
  'com.apple.dt.XCTMetric_Memory.physical' \
  '4096' \
  'Palette query memory growth' \
  'kB'
check_average \
  'BrowserPerformanceTests/testCommandPaletteResultProjection()' \
  'com.apple.dt.XCTMetric_Clock.time.monotonic' \
  '0.010' \
  '500-history, 100-tab palette projection' \
  's'
check_average \
  'BrowserPerformanceTests/testCommandPaletteResultProjection()' \
  'com.apple.dt.XCTMetric_Memory.physical' \
  '4096' \
  'Full palette projection memory growth' \
  'kB'
check_average \
  'BrowserPerformanceTests/testStartPageFrequentSiteProjection()' \
  'com.apple.dt.XCTMetric_Clock.time.monotonic' \
  '0.010' \
  '400-visit start page projection' \
  's'
check_average \
  'BrowserPerformanceTests/testStartPageFrequentSiteProjection()' \
  'com.apple.dt.XCTMetric_Memory.physical' \
  '4096' \
  'Start page projection memory growth' \
  'kB'
check_average \
  'BrowserPerformanceTests/testAskSurfaceResultProjection()' \
  'com.apple.dt.XCTMetric_Clock.time.monotonic' \
  '0.010' \
  '500-entry ask surface projection' \
  's'
check_average \
  'BrowserPerformanceTests/testAskSurfaceResultProjection()' \
  'com.apple.dt.XCTMetric_Memory.physical' \
  '4096' \
  'Ask surface projection memory growth' \
  'kB'
