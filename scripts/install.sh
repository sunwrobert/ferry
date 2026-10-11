#!/usr/bin/env bash
# One-step install on a new Mac:
#   curl -fsSL https://raw.githubusercontent.com/sunwrobert/ferry/main/scripts/install.sh | bash
# Options: --rules <file> (import an exported config), --no-setup (just build and install).
set -euo pipefail

REPO_DIR="${FERRY_DIR:-$HOME/Repositories/ferry}"
RULES=""
SETUP=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rules) RULES="$2"; shift 2 ;;
    --no-setup) SETUP=0; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

command -v swift >/dev/null || { echo "Swift is missing. Install Xcode or run: xcode-select --install" >&2; exit 1; }

if [[ -d "$REPO_DIR/.git" ]]; then
  git -C "$REPO_DIR" pull --ff-only
else
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone https://github.com/sunwrobert/ferry.git "$REPO_DIR"
fi

"$REPO_DIR/scripts/build.sh" --install
FERRY="$HOME/.local/bin/ferry"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Note: add ~/.local/bin to your PATH to use \`ferry\` directly." ;;
esac

[[ -n "$RULES" ]] && "$FERRY" import "$RULES"

if [[ "$SETUP" == 1 ]]; then
  echo
  echo "Setting up. Click Grant Access when Ferry asks for Chrome's folder, then confirm the browser dialog."
  "$FERRY" setup
  "$FERRY" skills add
fi

echo
echo "Done. Check with: ferry status"
