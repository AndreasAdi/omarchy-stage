import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The middle of a staged screen while a preview is dragged out of a side
// column: it marks the drop target and carries on drawing the dragged preview
// past the column's edge. It takes no input; the column keeps the pointer.
PanelWindow {
  id: overlay

  property var stage: null
  // The screen this overlay belongs to. active compares against this, not
  // the window's own screen: showing the window re-sends screen's change
  // signal while active is being worked out, which QML reports as a loop.
  property var stageScreen: null
  screen: stageScreen

  readonly property bool active: !!stage && !!stage.dragToplevel && stage.dragScreen === stageScreen
  // Reserved by both side columns, so this surface covers exactly the middle
  // and starts at the left column's edge, level with both columns.
  readonly property int columnWidth: Math.round((stageScreen ? stageScreen.width : 1920) * (stage ? stage.columnWidth : 0.16))

  visible: active
  color: "transparent"
  WlrLayershell.namespace: "andreas-stage-drop"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  mask: Region {}

  Rectangle {
    anchors.fill: parent
    anchors.margins: stage ? stage.gap : 10
    color: overlay.active && stage.dragTarget === "center" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12) : "transparent"
    radius: stage ? stage.cornerRadius : 0
    border.width: Style.hoverBorderWidth + 1
    border.color: overlay.active && stage.dragTarget === "center" ? Color.accent : Color.muted

    Behavior on color { ColorAnimation { duration: 120 } }
  }

  // The dragged preview, moved from screen coordinates into this surface's,
  // which start past the left column.
  Rectangle {
    visible: overlay.active
    x: overlay.active ? stage.dragRect.x - overlay.columnWidth : 0
    y: overlay.active ? stage.dragRect.y : 0
    width: overlay.active ? stage.dragRect.width : 0
    height: overlay.active ? stage.dragRect.height : 0
    color: Color.background
    radius: stage ? stage.cornerRadius : 0
    border.width: Style.hoverBorderWidth + 1
    border.color: Color.accent
    clip: true

    ScreencopyView {
      anchors.fill: parent
      anchors.margins: parent.border.width
      captureSource: overlay.active ? stage.dragToplevel.wayland : null
      live: overlay.active
    }
  }
}
