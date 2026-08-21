#!/bin/bash

# Install the sunset night light: the CLI, the daily timer, the post-boot hook,
# and the bar widget. Safe to re-run; every step is idempotent.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="contra.nightlight"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
UNIT_DIR="$HOME/.config/systemd/user"
BIN_DIR="$HOME/.local/bin"

echo "Installing from $REPO"

# 1. The CLI, so `nightlight-auto` works from a shell. The plugin calls the
#    copy in the repo by absolute path and does not depend on this.
mkdir -p "$BIN_DIR"
ln -sfn "$REPO/bin/nightlight-auto" "$BIN_DIR/nightlight-auto"
echo "  cli       $BIN_DIR/nightlight-auto"

# 2. The bar widget. A symlink keeps one checkout; a clone works equally well.
if [[ -e $PLUGIN_DIR && ! -L $PLUGIN_DIR ]]; then
  echo "  plugin    $PLUGIN_DIR already exists and is not a symlink, leaving it"
else
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  ln -sfn "$REPO" "$PLUGIN_DIR"
  echo "  plugin    $PLUGIN_DIR"
fi

# 3. hyprsunset itself. It runs from the unit its own package ships rather than
#    from autostart.lua: the daily rebuild has to restart it from a systemd
#    timer, and a uwsm-launched process does not survive that.
systemctl --user enable --now hyprsunset.service >/dev/null 2>&1 || true
echo "  hyprsunset $(systemctl --user is-enabled hyprsunset.service 2>/dev/null || echo unknown)"

# 4. Daily regeneration, because sunset moves.
mkdir -p "$UNIT_DIR"
install -m 644 "$REPO/systemd/nightlight-auto.service" "$UNIT_DIR/"
install -m 644 "$REPO/systemd/nightlight-auto.timer" "$UNIT_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now nightlight-auto.timer >/dev/null
echo "  timer     $(systemctl --user is-enabled nightlight-auto.timer)"

# 5. Rebuild when the desktop starts, so a machine that was off overnight still
#    gets tonight's ramp rather than yesterday's.
if omarchy-cmd-present omarchy-hook-install; then
  omarchy hook install post-boot "$REPO/hooks/nightlight-auto.sh" >/dev/null
  echo "  hook      post-boot.d/nightlight-auto.sh"
fi

# 6. A config file to edit, and tonight's schedule.
"$REPO/bin/nightlight-auto" init
"$REPO/bin/nightlight-auto" generate --force

# 7. The widget in the bar. Skipped silently if it is already placed.
if ! grep -q "$PLUGIN_ID" "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
  omarchy bar put "$PLUGIN_ID" --section center
  echo "  bar       added to the centre section"
fi

echo
"$REPO/bin/nightlight-auto" status
