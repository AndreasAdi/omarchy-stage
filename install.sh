#!/bin/bash
# Install stage mode for Omarchy: the andreas.stage shell plugin, its two
# scripts in ~/.local/bin, and marked blocks in ~/.config/hypr/bindings.lua and
# looknfeel.lua. Safe to run again to update; ./uninstall.sh removes it all.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
plugin_dir="$HOME/.config/omarchy/plugins/andreas.stage"
bin_dir="$HOME/.local/bin"
hypr_dir="$HOME/.config/hypr"
shell_json="$HOME/.config/omarchy/shell.json"

for cmd in omarchy hyprctl jq; do
  command -v "$cmd" >/dev/null || { echo "install.sh: $cmd not found; this needs Omarchy" >&2; exit 1; }
done
for file in bindings.lua looknfeel.lua; do
  [[ -f $hypr_dir/$file ]] || { echo "install.sh: $hypr_dir/$file not found; this needs Omarchy's Lua Hyprland config" >&2; exit 1; }
done

# The plugin is copied, not symlinked: the shell's file watcher does not follow
# a symlinked plugin directory, so edits there would never reload.
rm -rf "$plugin_dir"
mkdir -p "$plugin_dir"
cp -r "$here/plugin/." "$plugin_dir/"

install -Dm755 "$here/bin/hypr-stage-sync" "$bin_dir/hypr-stage-sync"
install -Dm755 "$here/bin/hypr-workspace-layout-cycle" "$bin_dir/hypr-workspace-layout-cycle"

# Each config file gets one marked block, replaced whole on reinstall.
write_block() {
  local file=$1 snippet=$2
  cp "$file" "$file.bak.$(date +%s)"
  sed -i '/^-- omarchy-stage: begin/,/^-- omarchy-stage: end/d' "$file"
  {
    printf '\n-- omarchy-stage: begin. Written by omarchy-stage/install.sh; uninstall.sh removes the block whole.\n'
    cat "$snippet"
    printf -- '-- omarchy-stage: end.\n'
  } >>"$file"
}
write_block "$hypr_dir/bindings.lua" "$here/hypr/bindings.lua"
write_block "$hypr_dir/looknfeel.lua" "$here/hypr/looknfeel.lua"

# Third-party shell services only load once listed in shell.json.
if [[ -f $shell_json ]] && ! jq -e '.plugins[]? | select(.id == "andreas.stage")' "$shell_json" >/dev/null; then
  tmp=$(mktemp)
  jq '.plugins = ((.plugins // []) + [{"id": "andreas.stage", "columnWidth": 0.16, "gap": 10, "cornerRadius": 0, "minPreviewSize": 1}])' "$shell_json" >"$tmp"
  cp "$shell_json" "$shell_json.bak.$(date +%s)"
  mv "$tmp" "$shell_json"
fi

hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
if [[ -n ${errors//[[:space:]]/} ]]; then
  echo "install.sh: Hyprland reports config errors:" >&2
  echo "$errors" >&2
fi

# A new service plugin only loads on a full shell restart.
omarchy restart shell >/dev/null 2>&1 || true

echo "Stage mode installed. Press Super + L on a workspace to cycle: tiling -> stage -> scrolling -> floating."
