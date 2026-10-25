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

  // The addresses of the windows this column shows, from the stage's
  // placement. The cards follow them in a ListModel, changed in place, so a
  // card outlives a reorder and slides to its new place, and the others keep
  // capturing instead of starting over.
  readonly property var windows: shown ? stage.column(workspaceId, side) : []
  onWindowsChanged: syncCards()

  ListModel { id: cardModel }

  function syncCards() {
    for (var i = 0; i < windows.length; i++) {
      if (i < cardModel.count && cardModel.get(i).address === windows[i]) continue
      var from = -1
      for (var j = i + 1; j < cardModel.count; j++) {
        if (cardModel.get(j).address === windows[i]) { from = j; break }
      }
      if (from !== -1) cardModel.move(from, i, 1)
      else cardModel.insert(i, { address: windows[i] })
    }
    if (cardModel.count > windows.length) cardModel.remove(windows.length, cardModel.count - windows.length)
  }

  // The rectangle of a window's preview in this column, for a promote from
  // the keyboard to grow out of.
  function rectOf(address) {
    for (var i = 0; i < repeater.count; i++) {
      var item = repeater.itemAt(i)
      if (item && item.address === address) return item.frameRect()
    }
    return null
  }

  Component.onCompleted: {
    syncCards()
    if (stage) stage.columns = stage.columns.concat([window])
  }
  Component.onDestruction: {
    if (stage) stage.columns = stage.columns.filter(function(column) { return column !== window })
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
  // Where this column starts on its screen: drag geometry is kept relative to
  // the screen so that every surface on it can draw the dragged preview.
  readonly property real screenWidth: screen ? screen.width : 1920
  readonly property real originX: side === "left" ? 0 : screenWidth - width

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

  // A preview is being dragged on this screen, and whether it would drop into
  // this column and before which of its previews.
  readonly property bool dragging: !!stage && !!stage.dragToplevel && stage.dragScreen === screen
  readonly property bool dropHere: dragging && stage.dragTarget === side
  readonly property int dropIndex: dropHere ? indexAt(stage.dragRect.y + stage.dragRect.height / 2) : -1
  onDropIndexChanged: if (dropHere) stage.dropIndex = dropIndex

  // The place in this column for a preview dropped with its middle at y.
  function indexAt(y) {
    var contentY = y + flick.contentY - cards.y
    for (var i = 0; i < repeater.count; i++) {
      var item = repeater.itemAt(i)
      if (item && contentY < item.y + item.height / 2) return i
    }
    return repeater.count
  }

  // The dragged preview while any of it is over this column.
  readonly property bool ghostHere: dragging && stage.dragRect.x + stage.dragRect.width > originX
                                    && stage.dragRect.x < originX + width

  // The column a preview would drop into is tinted.
  Rectangle {
    anchors.fill: parent
    visible: window.dropHere && stage.dragSide !== window.side
    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
  }

  Rectangle {
    z: 10
    visible: window.ghostHere
    x: stage ? stage.dragRect.x - window.originX : 0
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
      captureSource: window.ghostHere ? stage.dragToplevel.wayland : null
      live: window.ghostHere
    }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    interactive: contentHeight > height
    contentHeight: cards.implicitHeight + window.pad * 2
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    // Where a dropped preview would land: a line in the gap above the preview
    // at dropIndex, or below the last one.
    Rectangle {
      readonly property var before: window.dropHere ? repeater.itemAt(window.dropIndex) : null
      readonly property var last: window.dropHere && repeater.count > 0 ? repeater.itemAt(repeater.count - 1) : null
      visible: window.dropHere
      z: 5
      x: cards.x
      width: cards.width
      height: 3
      radius: 1.5
      color: Color.accent
      y: cards.y - height / 2 + (before ? before.y - window.pad / 2 : last ? last.y + last.height + window.pad / 2 : 0)
    }

    Column {
      id: cards
      y: window.pad
      x: Math.round((parent.width - width) / 2)
      width: window.cardWidth
      spacing: window.pad

      // Previews slide to their new place when one is moved, added or closed.
      move: Transition {
        NumberAnimation { properties: "x,y"; duration: 200; easing.type: Easing.OutCubic }
      }

      Repeater {
        id: repeater
        model: cardModel

        delegate: Item {
          id: card
          required property string address
          readonly property var toplevel: window.stage ? window.stage.parkedByAddress[address] || null : null

          width: parent.width
          height: frame.height + (title.visible ? window.titleHeight : 0)

          // A new preview fades in where it lands.
          NumberAnimation on opacity { from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }

          function frameRect() {
            var origin = frame.mapToItem(window.contentItem, 0, 0)
            return Qt.rect(origin.x, origin.y, frame.width, frame.height)
          }

          // Only a preview in view keeps capturing; one scrolled out of the
          // column, or faded out while it is dragged, keeps its last frame.
          readonly property bool inView: cards.y + y + height > flick.contentY
                                         && cards.y + y < flick.contentY + flick.height

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
              captureSource: card.toplevel ? card.toplevel.wayland : null
              live: card.inView && !mouse.dragging
            }
          }

          Text {
            id: title
            visible: window.showTitles
            anchors.top: frame.bottom
            anchors.topMargin: Style.spacing.xs
            width: parent.width
            text: !card.toplevel ? "" : card.toplevel.title || (card.toplevel.wayland ? card.toplevel.wayland.appId : "")
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: mouse.containsMouse ? Color.accent : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          // Middle- or right-click closes the window. Click to promote, or drag: onto the
          // middle of the screen to promote, onto the other column to move it
          // there, or up and down this one to reorder. Past a few pixels the
          // press becomes a drag. The pointer stays with this surface while
          // the button is held, so its position keeps arriving even over the
          // middle and the other column, which draw the preview there.
          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            // Dragging a card moves the card, never scrolls the column.
            preventStealing: true
            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

            property point pressPoint
            property bool dragging: false
            // Qt still sends clicked after a drag let go over a card; this
            // keeps that click from promoting the window.
            property bool dropped: false

            // The dragged preview's rectangle, relative to the screen.
            function ghostRect(m) {
              var origin = card.mapToItem(window.contentItem, m.x - pressPoint.x, m.y - pressPoint.y)
              return Qt.rect(origin.x + window.originX, origin.y, frame.width, frame.height)
            }

            // Where the pointer would drop the preview: a column or the middle.
            function zoneAt(m) {
              var x = card.mapToItem(window.contentItem, m.x, m.y).x + window.originX
              return x < window.width ? "left" : x >= window.screenWidth - window.width ? "right" : "center"
            }

            onPressed: function(m) {
              if (m.button !== Qt.LeftButton) return
              pressPoint = Qt.point(m.x, m.y)
              dragging = false
              dropped = false
            }

            onPositionChanged: function(m) {
              if (!(pressedButtons & Qt.LeftButton) || !window.stage || !card.toplevel) return
              if (!dragging && Math.abs(m.x - pressPoint.x) + Math.abs(m.y - pressPoint.y) > 8) {
                dragging = true
                window.stage.dragToplevel = card.toplevel
                window.stage.dragScreen = window.screen
                window.stage.dragSide = window.side
              }
              if (!dragging) return
              window.stage.dragRect = ghostRect(m)
              window.stage.dragTarget = zoneAt(m)
            }

            onReleased: function(m) {
              if (!dragging || !window.stage) return
              var stage = window.stage
              // The target the drag showed last, which dropIndex belongs to.
              var target = stage.dragTarget || zoneAt(m)
              var rect = ghostRect(m)
              var index = stage.dropIndex
              stage.endDrag()
              dragging = false
              dropped = true
              if (!card.toplevel) return
              if (target === "center") {
                // Dropped on the middle: it grows into place from where it was
                // let go, given in this column's coordinates.
                stage.promote(card.toplevel, window.side, Qt.rect(rect.x - window.originX, rect.y, rect.width, rect.height))
              } else {
                stage.moveTo(card.toplevel, window.workspaceId, target, index)
              }
            }

            onCanceled: {
              dragging = false
              if (window.stage) window.stage.endDrag()
            }

            onClicked: function(m) {
              if (!card.toplevel) return
              if (m.button === Qt.MiddleButton || m.button === Qt.RightButton) {
                if (card.toplevel.wayland) card.toplevel.wayland.close()
                return
              }
              if (!window.stage || dragging || dropped) return
              window.stage.promote(card.toplevel, window.side, card.frameRect())
            }
          }
        }
      }
    }
  }
}
