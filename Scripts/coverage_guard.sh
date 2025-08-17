#!/usr/bin/env bash
set -euo pipefail

SCHEME="TestRig"
DESTINATION="platform=macOS"
RESULT_BUNDLE="build/TestResults.xcresult"
MIN_COVERAGE=5  # % threshold for Step 1; will be raised in later steps

rm -rf build
xcodebuild \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -enableCodeCoverage YES \
  clean test \
  -resultBundlePath "$RESULT_BUNDLE" | xcpretty || true

if ! command -v xcrun >/dev/null; then
  echo "xcrun not found. Install Xcode command line tools."
  exit 1
fi

TOTAL=$(xcrun xccov view --report --json "$RESULT_BUNDLE" | python3 - <<'PY'
import json,sys
data=json.load(sys.stdin)
targets=data.get("targets",[])
cov=[t.get("lineCoverage",0.0) for t in targets]
print(int(round(100*sum(cov)/len(cov))) if cov else 0)
PY
)

echo "Total coverage: ${TOTAL}%"
if [ "$TOTAL" -lt "$MIN_COVERAGE" ]; then
  echo "Coverage ${TOTAL}% is below threshold ${MIN_COVERAGE}%"
  exit 2
fi

echo "Coverage guard OK."