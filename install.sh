#!/usr/bin/env bash
# Symlink sdd-init into ~/.local/bin (or the folder given as $1).
set -eo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin=${1:-$HOME/.local/bin}
mkdir -p "$bin"
chmod +x "$here/sdd-init"
ln -sf "$here/sdd-init" "$bin/sdd-init"
echo "✓ linked $bin/sdd-init → $here/sdd-init"
case ":$PATH:" in
  *":$bin:"*) ;;
  *) echo "! $bin is not on your PATH. Add to ~/.zshrc:  export PATH=\"$bin:\$PATH\"" ;;
esac
command -v specify >/dev/null 2>&1 || command -v uv >/dev/null 2>&1 || \
  echo "! Neither 'specify' nor 'uv' found. Install uv: brew install uv"
