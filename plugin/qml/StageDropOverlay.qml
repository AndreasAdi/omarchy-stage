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

  readonly property bool active: !!stage && !!stage.dragToplevel && stage.dragScreen === screen
  // Reserved by both side columns, so this surface covers exactly the middle
  // and starts at the left column's edge, level with both columns.
  readonly property int columnWidth: Math.round((screen ? screen.width : 1920) * (stage ? stage.columnWidth : 0.16))

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
    color: overlay.active && stage.dragOverCenter ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12) : "transparent"
    radius: stage ? stage.cornerRadius : 0
    border.width: Style.hoverBorderWidth + 1
    border.color: overlay.active && stage.dragOverCenter ? Color.accent : Color.muted

    Behavior on color { ColorAnimation { duration: 120 } }
  }

  // The dragged preview, moved from column coordinates into this surface's.
  Rectangle {
    visible: overlay.active
    x: !overlay.active ? 0 : stage.dragSide === "left" ? stage.dragRect.x - overlay.columnWidth : stage.dragRect.x + overlay.width
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
