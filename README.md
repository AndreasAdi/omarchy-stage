# Omarchy Stage

A stage-manager layout for [Omarchy](https://omarchy.org/). One window sits in the middle of the screen, and the workspace's other windows show as live, scaled-down previews in columns on the left and right.

```
┌──────┬──────────────────────────┬──────┐
│ ▢    │                          │ ▢    │
│ ▢    │     focused / primary    │ ▢    │
│ ▢    │                          │      │
└──────┴──────────────────────────┴──────┘
```

## Features

- **Live previews** that keep the window's aspect ratio, stacked from the top and alternating left and right.
- **Click** a preview to bring that window to the center. It grows out of its preview while the old center window shrinks back into it.
- **Drag** a preview onto the middle of the screen to bring it to the center from where you drop it.
- **Right-click** a preview to close that window. Apps with unsaved work can still ask first.
- **New windows** open in the center, and the previous center window becomes a preview.
- **A lone window takes the full width.** The side columns appear once a second window opens.
- **Lots of windows:** previews keep their size and the columns scroll with the mouse wheel.
- **Per workspace.** It's a fourth layout in Omarchy's Super + L cycle, so other workspaces keep tiling, scrolling or floating.
- **Follows your Omarchy theme.**

## Requirements

- Omarchy with its Lua Hyprland config (`~/.config/hypr/*.lua`), tested on Hyprland 0.56.
- The Omarchy shell (Quickshell 0.3+), which draws the previews.
- `jq`, which ships with Omarchy.

## Install

```bash
git clone https://github.com/AndreasAdi/omarchy-stage.git
cd omarchy-stage
./install.sh
```

The installer:

- copies the shell plugin to `~/.config/omarchy/plugins/andreas.stage`
- installs `hypr-stage-sync` and `hypr-workspace-layout-cycle` to `~/.local/bin`
- adds a marked block to `~/.config/hypr/bindings.lua` (Super + L) and to `looknfeel.lua` (a layout rule for the hidden workspaces)
- registers the plugin in `~/.config/omarchy/shell.json`
- backs up every file it changes, then restarts the shell

To update, run `git pull && ./install.sh`.

## Usage

Press **Super + L** to cycle the current workspace through **tiling → stage → scrolling → floating**. **Super + Alt + L** goes the other way.

## Settings

The plugin's entry in `~/.config/omarchy/shell.json` holds these settings. Changes apply when you save the file.

| Key | Default | Meaning |
|---|---|---|
| `columnWidth` | `0.16` | Width of each side column, as a share of the screen width |
| `gap` | `10` | Space around and between previews, in pixels |
| `cornerRadius` | `0` | Corner rounding of the previews |
| `minPreviewSize` | `1` | Smallest share of the column width a preview may shrink to before the column scrolls. `1` never shrinks. |

## How it works

- A staged workspace keeps one tiled window. The others are parked on a hidden special workspace, `special:stage-<n>`, by `hypr-stage-sync`.
- `hypr-stage-sync` runs after every window open, close or move on a staged workspace.
- The shell plugin reserves the side columns and draws the parked windows with Quickshell's `ScreencopyView`.
- Which workspaces are staged is kept as marker files in `~/.local/state/omarchy/stage/`.

## Known limitations

- **Previews may lag.** Parked windows are hidden, and some apps stop drawing while hidden, so a preview may update slowly or look frozen until the window comes back.
- **The Super + L cycle replaces Omarchy's.** `hypr-workspace-layout-cycle` is a copy of Omarchy's `omarchy-hyprland-workspace-layout-toggle` with stage added, so changes Omarchy makes to its own cycle won't reach it.

## Uninstall

```bash
./uninstall.sh
```

This brings every parked window back to its workspace, then removes the plugin, the scripts, the config blocks and the `shell.json` entry.

## License

MIT
