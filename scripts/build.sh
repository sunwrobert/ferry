#!/usr/bin/env bash
# Build Ferry.app into build/. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/Ferry.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Ferry" "$APP/Contents/MacOS/Ferry"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Ferry || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/Ferry.app
  cp -R "$APP" ~/Applications/Ferry.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/Ferry.app
  mkdir -p ~/.local/bin
  ln -sf ~/Applications/Ferry.app/Contents/MacOS/Ferry ~/.local/bin/ferry
  open ~/Applications/Ferry.app
  echo "Installed ~/Applications/Ferry.app and ~/.local/bin/ferry"
fi
