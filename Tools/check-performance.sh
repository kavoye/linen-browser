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

warn() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::warning title=Performance budget::$1"
  else
    echo "warning: $1" >&2
  fi
}

summary() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
}

check_fastest() {
  test_id="$1"
  maximum="$2"
  label="$3"

  values="$(jq -r \
    --arg test "$test_id" \
    '.[]
      | select(.testIdentifier == $test)
      | .testRuns[].metrics[]
      | select(.identifier == "com.apple.dt.XCTMetric_Clock.time.monotonic")
      | .measurements[]
      | select(type == "number")' \
    "$metrics_file")"

  if [ -z "$values" ]; then
    warn "missing $label metric for $test_id"
    summary "- $label: **missing**"
    return
  fi

  fastest="$(printf '%s\n' "$values" | awk 'NR == 1 || $1 < min { min = $1 } END { printf "%.6f", min }')"
  if awk -v value="$fastest" -v maximum="$maximum" 'BEGIN { exit !(value <= maximum) }'; then
    echo "$label: $fastest s (budget: $maximum s)"
    summary "- $label: **$fastest s** (budget: $maximum s)"
  else
    warn "$label took $fastest s at its fastest; budget is $maximum s"
    summary "- $label: **$fastest s, over budget** (budget: $maximum s)"
  fi
}

summary '### Performance budgets'
summary ''

check_fastest \
  'BrowserPerformanceTests/testCreatingAUsableStartPageTab()' \
  '0.010' \
  'First usable start page tab'
check_fastest \
  'BrowserPerformanceTests/testSwitchingTabsInACrowdedSession()' \
  '0.035' \
  '500 tab activations'
check_fastest \
  'BrowserPerformanceTests/testCommandPaletteHistoryRanking()' \
  '0.010' \
  '500-entry palette query'
check_fastest \
  'BrowserPerformanceTests/testCommandPaletteResultProjection()' \
  '0.020' \
  '500-history, 100-tab palette projection'
check_fastest \
  'BrowserPerformanceTests/testStartPageFrequentSiteProjection()' \
  '0.015' \
  '400-visit start page projection'
check_fastest \
  'BrowserPerformanceTests/testAskSurfaceResultProjection()' \
  '0.010' \
  '500-entry ask surface projection'
