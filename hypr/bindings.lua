-- SUPER+L / SUPER+ALT+L (was: Omarchy's layout cycle) also include stage mode.
o.rebind("SUPER + L", "Cycle workspace layout", "~/.local/bin/hypr-workspace-layout-cycle")
o.rebind("SUPER + ALT + L", "Cycle workspace layout back", "~/.local/bin/hypr-workspace-layout-cycle back")
-- SUPER+] / SUPER+[ bring the next or previous stage preview to the center.
o.rebind("SUPER + bracketright", "Next stage window", "omarchy-shell -q andreas.stage next")
o.rebind("SUPER + bracketleft", "Previous stage window", "omarchy-shell -q andreas.stage previous")
