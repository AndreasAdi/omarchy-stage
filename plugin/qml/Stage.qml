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

  // Parked windows by workspace id, in Hyprland's window order, built once per
  // change for every column on every screen to read. A hidden one (a terminal
  // swallowed by an app it launched) has nothing to show.
  readonly property var parkedByWorkspace: {
    var map = {}
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      var name = toplevel.workspace ? toplevel.workspace.name : ""
      if (name.indexOf("special:stage-") !== 0 || !toplevel.wayland) continue
      var ipc = toplevel.lastIpcObject
      if (ipc && ipc.hidden) continue
      var id = name.slice("special:stage-".length)
      if (!map[id]) map[id] = []
      map[id].push(toplevel)
    }
    return map
  }

  readonly property var noWindows: []

  function parked(workspaceId) {
    return root.parkedByWorkspace[String(workspaceId)] || root.noWindows
  }

  // ------------------------------------------------------------- columns
  // Which column each parked window shows in, and in what order: per
  // workspace id, { left: [address...], right: [address...] }. A window keeps
  // its place until it leaves. A newly parked one takes the slot of the window
  // just promoted (it shrinks into that preview), or else goes to the end of
  // the shorter column. Promotes clicked faster than a swap queue up, so their
  // slots do too: each window parked takes the oldest slot still waiting.
  property var placement: ({})
  property var pendingSlots: []

  function key(toplevel) { return String(toplevel.address || "") }

  // Parked windows by address, for the columns' cards to find theirs.
  readonly property var parkedByAddress: {
    var map = {}
    for (var ws in root.parkedByWorkspace)
      root.parkedByWorkspace[ws].forEach(function(toplevel) { map[root.key(toplevel)] = toplevel })
    return map
  }

  // The placement as saved by the last shell, so a restart keeps every
  // preview where it was. A workspace's entry seeds its placement once its
  // windows show up, and is written back until then.
  readonly property string placementPath: root.stateDir + "/placement.json"
  property var restored: ({})
  property bool placementLoaded: false

  function validColumns(cols) {
    return !!cols && Array.isArray(cols.left) && Array.isArray(cols.right)
  }

  FileView {
    id: placementFile
    path: root.placementPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var saved = {}
      try { saved = JSON.parse(text()) } catch (e) { saved = {} }
      var restored = {}
      for (var ws in saved) {
        if (root.validColumns(saved[ws]))
          restored[ws] = { left: saved[ws].left.map(String), right: saved[ws].right.map(String) }
      }
      root.restored = restored
      root.placementLoaded = true
      root.reconcile()
    }
    onLoadFailed: root.placementLoaded = true
  }

  Timer {
    id: saveTimer
    interval: 500
    onTriggered: placementFile.setText(JSON.stringify(Object.assign({}, root.restored, root.placement)) + "\n")
  }

  onPlacementChanged: if (placementLoaded) saveTimer.restart()

  function slotOf(workspaceId, address) {
    var cols = root.placement[String(workspaceId)]
    if (!cols) return null
    var side = cols.left.indexOf(address) !== -1 ? "left" : "right"
    var index = cols[side].indexOf(address)
    return index === -1 ? null : { side: side, index: index }
  }

  function reconcile() {
    var next = {}
    var parked = root.parkedByWorkspace
    var restored = root.restored
    var now = Date.now()
    var slots = root.pendingSlots.filter(function(slot) { return now - slot.time < 5000 })
    for (var ws in parked) {
      var present = {}
      parked[ws].forEach(function(toplevel) { present[root.key(toplevel)] = true })
      var old = root.placement[ws] || restored[ws] || { left: [], right: [] }
      if (restored[ws]) {
        restored = Object.assign({}, restored)
        delete restored[ws]
      }
      var cols = {
        left: old.left.filter(function(address) { return present[address] }),
        right: old.right.filter(function(address) { return present[address] })
      }
      parked[ws].forEach(function(toplevel) {
        var address = root.key(toplevel)
        if (cols.left.indexOf(address) !== -1 || cols.right.indexOf(address) !== -1) return
        var waiting = -1
        for (var i = 0; i < slots.length && waiting === -1; i++) {
          if (slots[i].ws === ws) waiting = i
        }
        if (waiting !== -1) {
          var slot = slots.splice(waiting, 1)[0]
          cols[slot.side].splice(Math.min(slot.index, cols[slot.side].length), 0, address)
        } else {
          (cols.left.length <= cols.right.length ? cols.left : cols.right).push(address)
        }
      })
      next[ws] = cols
    }
    root.restored = restored
    root.pendingSlots = slots
    root.placement = next
  }

  onParkedByWorkspaceChanged: reconcile()

  // The addresses of the parked windows one column shows, top to bottom.
  function column(workspaceId, side) {
    var cols = root.placement[String(workspaceId)]
    if (!cols) return root.noWindows
    var byAddress = root.parkedByAddress
    return cols[side].filter(function(address) { return !!byAddress[address] })
  }

  // Moves a preview to a column, before the preview now at index there.
  function moveTo(toplevel, workspaceId, side, index) {
    var ws = String(workspaceId)
    var address = root.key(toplevel)
    var from = root.slotOf(ws, address)
    if (!from) return
    index = Math.max(0, Math.min(index, root.placement[ws][side].length))
    // Dropped back where it was: nothing to rebuild.
    if (from.side === side && (index === from.index || index === from.index + 1)) return
    var cols = { left: root.placement[ws].left.slice(), right: root.placement[ws].right.slice() }
    cols[from.side].splice(from.index, 1)
    if (from.side === side && from.index < index) index--
    cols[side].splice(index, 0, address)
    var next = Object.assign({}, root.placement)
    next[ws] = cols
    root.placement = next
  }

  // The preview's place (side column and rectangle inside it) lets the window
  // grow out of its preview instead of popping up in the center.
  function promote(toplevel, side, rect) {
    var address = String(toplevel.address || "")
    if (!address) return
    // The old primary is parked into this preview's slot.
    var ws = toplevel.workspace ? toplevel.workspace.name.replace("special:stage-", "") : ""
    var slot = root.slotOf(ws, root.key(toplevel))
    var queued = root.pendingSlots.some(function(pending) {
      return pending.address === root.key(toplevel) && Date.now() - pending.time < 5000
    })
    if (slot && !queued) {
      root.pendingSlots = root.pendingSlots.concat([{ ws: ws, side: slot.side, index: slot.index, address: root.key(toplevel), time: Date.now() }])
      root.setCursor(ws, slot.side === "left" ? slot.index : root.placement[ws].left.length + slot.index)
    }
    if (address.indexOf("0x") !== 0) address = "0x" + address
    var args = [root.syncCommand, "promote", address]
    if (rect) args = args.concat([side, Math.round(rect.x), Math.round(rect.y), Math.round(rect.width), Math.round(rect.height)])
    Quickshell.execDetached(args)
  }

  // ------------------------------------------------------------- keyboard
  // Super + ] and Super + [ step through the previews in reading order, left
  // column then right. The old primary takes each promoted preview's slot, so
  // stepping on from the last promoted slot visits every window in turn.
  // cursor holds that slot per workspace, as an index into left + right.
  property var cursor: ({})

  function setCursor(ws, index) {
    var next = Object.assign({}, root.cursor)
    next[ws] = index
    root.cursor = next
  }

  // The side columns on the focused monitor register here so the promoted
  // window can grow out of its preview.
  property var columns: []

  function cycle(step) {
    var monitor = Hyprland.focusedMonitor
    var ws = monitor && monitor.activeWorkspace ? String(monitor.activeWorkspace.id) : ""
    var cols = root.placement[ws]
    if (!root.isStaged(ws) || !cols) return
    var slots = cols.left.concat(cols.right)
    if (slots.length === 0) return
    var cur = root.cursor[ws]
    if (cur === undefined || cur >= slots.length) cur = -1
    var index = step > 0 ? (cur + 1) % slots.length : (cur < 0 ? slots.length - 1 : cur)
    var toplevel = root.parkedByAddress[slots[index]]
    if (!toplevel) return
    var side = index < cols.left.length ? "left" : "right"
    var rect = null
    for (var i = 0; i < root.columns.length; i++) {
      var column = root.columns[i]
      if (column.monitor === monitor && column.side === side) rect = column.rectOf(slots[index])
    }
    root.promote(toplevel, side, rect)
    // Back again from here next time: the slot before this one.
    if (step < 0) root.setCursor(ws, index - 1)
  }

  // A preview being dragged: which window, on which screen and from which
  // side, and its rectangle relative to the screen. Both columns and the drop
  // overlay over the middle draw it from here. dragTarget is where it would
  // drop ("left", "right" or "center"); dropIndex is its place in a column.
  property var dragToplevel: null
  property var dragScreen: null
  property string dragSide: ""
  property rect dragRect: Qt.rect(0, 0, 0, 0)
  property string dragTarget: ""
  property int dropIndex: 0

  function endDrag() {
    root.dragToplevel = null
    root.dragScreen = null
    root.dragTarget = ""
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
    // Super + ] and Super + [: bring the next or previous preview to the center.
    function next(): void { root.cycle(1) }
    function previous(): void { root.cycle(-1) }
  }

  Component.onCompleted: {
    refresh()
    // parkedByWorkspace's first value sends no change signal.
    reconcile()
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      Scope {
        id: screenScope
        required property var modelData

        StageColumn { screen: screenScope.modelData; stage: root; side: "left" }
        StageColumn { screen: screenScope.modelData; stage: root; side: "right" }
        StageDropOverlay { stageScreen: screenScope.modelData; stage: root }
      }
    }
  }
}
