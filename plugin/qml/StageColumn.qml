import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// One side column of previews on one screen. It reserves its width while the
// screen's workspace is staged, so the primary window tiles between the two.
PanelWindow {
  id: window

  property var stage: null
  property string side: "left"

  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
  readonly property bool staged: !!stage && stage.isStaged(workspaceId)
  readonly property bool hasParked: staged && stage.parked(workspaceId).length > 0

  // A lone window gets the full width: the columns go once nothing is parked.
  // They wait a moment first, since a swap empties the list for an instant
  // and the columns must not blink out mid-animation.
  property bool shown: hasParked
  onHasParkedChanged: {
    if (hasParked) {
      hideTimer.stop()
      shown = true
    } else if (!staged) {
      shown = false
    } else {
      hideTimer.restart()
    }
  }

  Timer {
    id: hideTimer
    interval: 700
    onTriggered: window.shown = window.hasParked
  }

  // Parked windows alternate sides: first left, second right, and so on.
  readonly property var windows: {
    if (!shown) return []
    var all = stage.parked(workspaceId)
    var offset = side === "left" ? 0 : 1
    return all.filter(function(toplevel, index) { return index % 2 === offset })
  }

  visible: shown
  color: "transparent"
  WlrLayershell.namespace: "andreas-stage"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusiveZone: implicitWidth

  anchors {
    top: true
    bottom: true
    left: window.side === "left"
    right: window.side === "right"
  }

  implicitWidth: Math.round((screen ? screen.width : 1920) * (stage ? stage.columnWidth : 0.16))

  // Many parked windows: the previews may shrink toward minPreviewSize (1 by
  // default, so they keep their size), titles go once they get small, and the
  // column scrolls with the wheel when they no longer fit. Parked windows all share the primary's size, so
  // one aspect ratio serves every preview.
  readonly property int pad: stage ? stage.gap : 10
  readonly property real fullWidth: Math.max(1, width - pad * 2)
  readonly property real available: Math.max(1, height - pad * 2)
  readonly property real aspect: {
    var w = (screen ? screen.width : 1920) - implicitWidth * 2 - pad * 2
    var h = height - pad * 2
    return w > 0 && h > 0 ? h / w : 10 / 16
  }
  readonly property int count: windows.length
  readonly property real titleHeight: titleMetrics.height + Style.spacing.xs

  function fitWidth(titleSpace) {
    if (count === 0) return fullWidth
    return (available - count * titleSpace - (count - 1) * pad) / (count * aspect)
  }

  function clampWidth(value) {
    return Math.round(Math.max(fullWidth * (stage ? stage.minPreviewSize : 1), Math.min(fullWidth, value)))
  }

  readonly property real titledWidth: clampWidth(fitWidth(titleHeight))
  readonly property bool showTitles: titledWidth >= fullWidth * 0.7
  readonly property real cardWidth: showTitles ? titledWidth : clampWidth(fitWidth(0))

  FontMetrics {
    id: titleMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  // The dragged preview while it is still over this column.
  readonly property bool dragFromHere: !!stage && !!stage.dragToplevel && stage.dragScreen === screen && stage.dragSide === side

  Rectangle {
    z: 10
    visible: window.dragFromHere
    x: stage ? stage.dragRect.x : 0
    y: stage ? stage.dragRect.y : 0
    width: stage ? stage.dragRect.width : 0
    height: stage ? stage.dragRect.height : 0
    color: Color.background
    radius: stage ? stage.cornerRadius : 0
    border.width: Style.hoverBorderWidth + 1
    border.color: Color.accent
    clip: true

    ScreencopyView {
      anchors.fill: parent
      anchors.margins: parent.border.width
      captureSource: window.dragFromHere ? stage.dragToplevel.wayland : null
      live: window.dragFromHere
    }
  }

  Flickable {
    anchors.fill: parent
    interactive: contentHeight > height
    contentHeight: cards.implicitHeight + window.pad * 2
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: cards
      y: window.pad
      x: Math.round((parent.width - width) / 2)
      width: window.cardWidth
      spacing: window.pad

      Repeater {
        model: window.windows

        delegate: Item {
          id: card
          required property var modelData

          width: parent.width
          height: frame.height + (title.visible ? window.titleHeight : 0)

          Rectangle {
            id: frame
            width: parent.width
            // Same shape as the primary window, which every parked window shares.
            height: Math.round(width * window.aspect)
            color: Color.background
            radius: stage ? stage.cornerRadius : 0
            opacity: mouse.dragging ? 0.35 : 1
            border.width: mouse.containsMouse ? Style.hoverBorderWidth + 1 : Style.normalBorderWidth
            border.color: mouse.containsMouse ? Color.accent : Color.muted
            clip: true

            ScreencopyView {
              id: preview
              anchors.fill: parent
              anchors.margins: frame.border.width
              captureSource: card.modelData.wayland
              live: true
            }
          }

          Text {
            id: title
            visible: window.showTitles
            anchors.top: frame.bottom
            anchors.topMargin: Style.spacing.xs
            width: parent.width
            text: card.modelData.title || (card.modelData.wayland ? card.modelData.wayland.appId : "")
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: mouse.containsMouse ? Color.accent : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          // Right-click closes the window. Click to promote, or drag onto the
          // middle of the screen: past a few
          // pixels the press becomes a drag. The pointer stays with this
          // surface while the button is held, so its position keeps arriving
          // even over the middle, where the drop overlay draws the preview.
          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            // Dragging a card moves the card, never scrolls the column.
            preventStealing: true
            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

            property point pressPoint
            property bool dragging: false

            function ghostRect(m) {
              var origin = card.mapToItem(window.contentItem, m.x - pressPoint.x, m.y - pressPoint.y)
              return Qt.rect(origin.x, origin.y, frame.width, frame.height)
            }

            function overCenter(m) {
              var point = card.mapToItem(window.contentItem, m.x, m.y)
              return window.side === "left" ? point.x > window.width : point.x < 0
            }

            onPressed: function(m) {
              if (m.button !== Qt.LeftButton) return
              pressPoint = Qt.point(m.x, m.y)
              dragging = false
            }

            onPositionChanged: function(m) {
              if (!(pressedButtons & Qt.LeftButton) || !window.stage) return
              if (!dragging && Math.abs(m.x - pressPoint.x) + Math.abs(m.y - pressPoint.y) > 8) {
                dragging = true
                window.stage.dragToplevel = card.modelData
                window.stage.dragScreen = window.screen
                window.stage.dragSide = window.side
              }
              if (!dragging) return
              window.stage.dragRect = ghostRect(m)
              window.stage.dragOverCenter = overCenter(m)
            }

            onReleased: function(m) {
              if (!dragging || !window.stage) return
              var drop = overCenter(m)
              var rect = ghostRect(m)
              window.stage.endDrag()
              dragging = false
              // Dropped on the middle: it grows into place from where it was let go.
              if (drop) window.stage.promote(card.modelData, window.side, rect)
            }

            onCanceled: {
              dragging = false
              if (window.stage) window.stage.endDrag()
            }

            onClicked: function(m) {
              if (m.button === Qt.RightButton) {
                if (card.modelData.wayland) card.modelData.wayland.close()
                return
              }
              if (!window.stage || dragging) return
              var origin = frame.mapToItem(window.contentItem, 0, 0)
              window.stage.promote(card.modelData, window.side, Qt.rect(origin.x, origin.y, frame.width, frame.height))
            }
          }
        }
      }
    }
  }
}
