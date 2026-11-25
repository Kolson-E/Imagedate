#!/bin/bash
# Selects the newest release (not beta) Xcode on the runner.
# Usage: select_newest_xcode.sh [minimum major version]
set -euo pipefail
minimum=${1:-16}
version=$(ls -d /Applications/Xcode_*.app 2>/dev/null \
  | grep -viE 'beta|release_candidate|_rc' \
  | sed -nE 's#^/Applications/Xcode_([0-9]+(\.[0-9]+)*)\.app$#\1#p' \
  | sort -V | tail -1)
if [ -z "$version" ] || [ "${version%%.*}" -lt "$minimum" ]; then
  echo "::error::This runner has no release Xcode $minimum or later (newest: ${version:-none}). Change runs-on to a newer macOS runner."
  ls -d /Applications/Xcode*.app || true
  exit 1
fi
sudo xcode-select -s "/Applications/Xcode_$version.app"
xcodebuild -version
