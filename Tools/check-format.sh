#!/bin/sh

set -eu

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "error: swiftlint is not installed. Run: brew install swiftlint" >&2
  exit 1
fi

swiftlint lint --strict --quiet

echo "swiftlint: no violations"
