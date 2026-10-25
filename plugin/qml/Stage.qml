import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons

// Stage mode. A staged workspace (Super + L) shows one tiled window; the others
// are parked on the hidden special:stage-<ws> workspace by hypr-stage-sync, and
// shown here as live previews in a column on each side of the screen.
Item {
  id: root

  // Injected by the shell host when the service loads.
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string syncCommand: home + "/.local/bin/hypr-stage-sync"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/stage"

  // ------------------------------------------------------------- settings
  // Read from this plugin's entry in ~/.config/omarchy/shell.json (`plugins[]`).
  readonly property var settings: {
    var cfg = shell ? shell.shellConfig : null
    var list = cfg && Array.isArray(cfg.plugins) ? cfg.plugins : []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].id || "") === "andreas.stage") return list[i]
    }
    return ({})
  }
  function numberSetting(key, fallback, min, max) {
    var value = Number(root.settings ? root.settings[key] : undefined)
    if (isNaN(value)) value = fallback
    return Math.max(min, Math.min(max, value))
  }

  // Share of the screen width each side column takes.
  readonly property real columnWidth: numberSetting("columnWidth", 0.16, 0.08, 0.3)
  readonly property int gap: numberSetting("gap", 10, 0, 40)
  readonly property int cornerRadius: numberSetting("cornerRadius", 0, 0, 24)
  // Smallest a preview may shrink to, as a share of the column width, before
  // the column scrolls instead. 1 never shrinks.
  readonly property real minPreviewSize: numberSetting("minPreviewSize", 1, 0.3, 1)

  // ------------------------------------------------------------- state
  // Workspace ids with a marker file in stateDir, as strings.
  property var staged: []

  function isStaged(workspaceId) {
    return root.staged.indexOf(String(workspaceId)) !== -1
  }

  function refresh() {
    listProc.running = false
    listProc.running = true
  }

  Process {
    id: listProc
    command: ["bash", "-c", "ls -1 \"$1\" 2>/dev/null; true", "_", root.stateDir]
    stdout: StdioCollector {
      onStreamFinished: root.staged = text.split("\n").filter(function(line) { return /^[0-9]+$/.test(line) })
    }
  }

  // The parked windows of a workspace, in Hyprland's window order. A hidden
  // one (a terminal swallowed by an app it launched) has nothing to show.
  function parked(workspaceId) {
    var name = "special:stage-" + workspaceId
    var out = []
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      var ipc = toplevel.lastIpcObject
      if (ipc && ipc.hidden) continue
      if (toplevel.workspace && toplevel.workspace.name === name && toplevel.wayland) out.push(toplevel)
    }
    return out
  }

  // The preview's place (side column and rectangle inside it) lets the window
  // grow out of its preview instead of popping up in the center.
  function promote(toplevel, side, rect) {
    var address = String(toplevel.address || "")
    if (!address) return
    if (address.indexOf("0x") !== 0) address = "0x" + address
    var args = [root.syncCommand, "promote", address]
    if (rect) args = args.concat([side, Math.round(rect.x), Math.round(rect.y), Math.round(rect.width), Math.round(rect.height)])
    Quickshell.execDetached(args)
  }

  // A preview being dragged: which window, on which screen and side, and its
  // rectangle in that side column's coordinates. Both the column and the drop
  // overlay over the middle draw it from here.
  property var dragToplevel: null
  property var dragScreen: null
  property string dragSide: ""
  property rect dragRect: Qt.rect(0, 0, 0, 0)
  property bool dragOverCenter: false

  function endDrag() {
    root.dragToplevel = null
    root.dragScreen = null
    root.dragOverCenter = false
  }

  // Windows opening, closing or moving on a staged workspace change who is
  // primary; one sync runs after a burst of events.
  Timer {
    id: syncTimer
    interval: 120
    onTriggered: {
      Quickshell.execDetached([root.syncCommand])
      Hyprland.refreshToplevels()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") root.refresh()
      else if (root.staged.length > 0
               && (name === "openwindow" || name === "closewindow" || name === "movewindowv2" || name === "changefloatingmode"))
        syncTimer.restart()
    }
  }

  ShellIpc {
    target: "andreas.stage"

    // The layout cycle calls this after staging or unstaging a workspace.
    function refresh(): void { root.refresh() }
  }

  Component.onCompleted: refresh()

  Variants {
    model: Quickshell.screens

    delegate: Component {
      Scope {
        id: screenScope
        required property var modelData

        StageColumn { screen: screenScope.modelData; stage: root; side: "left" }
        StageColumn { screen: screenScope.modelData; stage: root; side: "right" }
        StageDropOverlay { screen: screenScope.modelData; stage: root }
      }
    }
  }
}
