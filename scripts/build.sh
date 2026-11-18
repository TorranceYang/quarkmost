#!/bin/zsh
# Compile-check for the simulator; prints only errors and the result.
#   scripts/build.sh            # first 40 error lines
#   scripts/build.sh 100
cd "$(dirname "$0")/.."
xcodebuild -project Quarkmost.xcodeproj -scheme Quarkmost -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sed "s|$PWD/||" | sort -u | head -${1:-40}
