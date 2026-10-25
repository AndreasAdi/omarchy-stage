#!/bin/bash
# Remove stage mode: windows parked by it go back to their workspaces first.
set -euo pipefail

plugin_dir="$HOME/.config/omarchy/plugins/andreas.stage"
bin_dir="$HOME/.local/bin"
hypr_dir="$HOME/.config/hypr"
shell_json="$HOME/.config/omarchy/shell.json"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/stage"

# With no workspace staged, a sync brings every parked window back.
rm -rf "$state_dir"
[[ -x $bin_dir/hypr-stage-sync ]] && "$bin_dir/hypr-stage-sync" || true

rm -rf "$plugin_dir"
rm -f "$bin_dir/hypr-stage-sync" "$bin_dir/hypr-workspace-layout-cycle"

for file in "$hypr_dir/bindings.lua" "$hypr_dir/looknfeel.lua"; do
  [[ -f $file ]] && sed -i '/^-- omarchy-stage: begin/,/^-- omarchy-stage: end/d' "$file"
done

if [[ -f $shell_json ]] && jq -e '.plugins[]? | select(.id == "andreas.stage")' "$shell_json" >/dev/null; then
  tmp=$(mktemp)
  jq '.plugins |= map(select(.id != "andreas.stage"))' "$shell_json" >"$tmp"
  mv "$tmp" "$shell_json"
fi

hyprctl reload >/dev/null
omarchy restart shell >/dev/null 2>&1 || true

echo "Stage mode removed. Super + L is back to Omarchy's layout cycle."
