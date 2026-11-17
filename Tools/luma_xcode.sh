#!/bin/bash
# The app is built against the iOS 26 SDK. On a runner whose default Xcode is older (GitHub's Intel
# macOS runner), this selects the newest Xcode 26 the image carries. On a runner that already
# defaults to Xcode 26 it changes nothing.
#
#   Tools/luma_xcode.sh
#
# The path of the runner's own default Xcode is exported as LUMA_DEFAULT_XCODE, so that a later step
# can go back to it: the simulators an image ships are the ones that came with its default Xcode.
set -euo pipefail
major() { xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f1; }
DEFAULT=$(xcode-select -p)
echo "default: $(xcodebuild -version | tr '\n' ' ')at $DEFAULT"
if [ -n "${GITHUB_ENV:-}" ]; then echo "LUMA_DEFAULT_XCODE=$DEFAULT" >> "$GITHUB_ENV"; fi
if [ "$(major)" -ge 26 ]; then exit 0; fi

ALL=$(ls -d /Applications/Xcode_26*.app 2>/dev/null || true)
PICK=$(echo "$ALL" | { grep -viE 'beta|candidate' || true; } | sort -V | tail -1)
if [ -z "$PICK" ]; then PICK=$(echo "$ALL" | sort -V | tail -1); fi
if [ -z "$PICK" ]; then
  echo "::error::this runner has no Xcode 26, which the app needs"
  ls /Applications | { grep -i xcode || true; }
  exit 1
fi
sudo xcode-select -s "$PICK/Contents/Developer"
sudo xcodebuild -runFirstLaunch >/dev/null 2>&1 || true
echo "selected: $(xcodebuild -version | tr '\n' ' ')at $(xcode-select -p)"
