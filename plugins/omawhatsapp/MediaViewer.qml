import QtQuick
import QtQuick.Controls
import qs.Commons
import "MediaViewerLogic.js" as MediaLogic
import "MediaModel.js" as MediaModel

// Native, full-window media viewing keeps photos, GIFs, and videos inside the
// client. The chat timeline stays mounted underneath, so closing is instant.
FocusScope {
  id: root

  required property color foreground
  required property color background
  required property color accent
  required property color dim
  required property string fontFamily
  property var items: []
  property int currentIndex: -1
  property real zoom: 1
  property bool opened: false
  property bool surfaceActive: true
  property var playback: null
  property var chatRef: ({ account: "", jid: "", key: "" })
  property string playbackSurface: "app-viewer"

  signal openExternalRequested(string path)

  readonly property var currentItem: currentIndex >= 0 && currentIndex < items.length
    ? items[currentIndex] : null
  readonly property string mediaType: MediaModel.mediaType(currentItem)
  readonly property string mimeType: MediaModel.mimeType(currentItem)
  readonly property string localPath: currentItem
    ? String(currentItem.local_path || "") : ""
  readonly property bool gifVideo: MediaModel.isGifVideo(currentItem)
  readonly property bool video: MediaModel.isVideo(currentItem)
  readonly property bool animatedImage: MediaModel.isAnimatedImage(currentItem)
  readonly property string playbackMessageId: currentItem
    ? String(currentItem.id || "viewer-" + currentIndex) : ""
  readonly property bool playbackGranted: !playback || playback.owns(
    playbackSurface, chatRef, playbackMessageId)

  visible: opened
  focus: opened
  z: 1000

  function localUrl(path) {
    var value = String(path || "")
    if (value === "__demo__") return Qt.resolvedUrl("assets/demo-capture.svg")
    if (value === "__demo_photo__") return Qt.resolvedUrl("assets/demo-photo.svg")
    return MediaModel.encodedFileUrl(value)
  }

  function openAt(index) {
    var bounded = MediaLogic.boundedIndex(items, index)
    if (bounded < 0) return
    currentIndex = bounded
    zoom = 1
    opened = true
    if (animatedImage || video)
      Qt.callLater(function() { root.requestPlayback() })
    Qt.callLater(function() { root.forceActiveFocus() })
  }

  function closeViewer() {
    if (playback) playback.releaseSurface(playbackSurface)
    opened = false
    currentIndex = -1
    zoom = 1
  }

  function navigate(delta) {
    if (playback) playback.releaseSurface(playbackSurface)
    currentIndex = MediaLogic.nextIndex(items, currentIndex, delta)
    zoom = 1
    if (animatedImage || video)
      Qt.callLater(function() { root.requestPlayback() })
    Qt.callLater(function() { root.forceActiveFocus() })
  }

  function setZoom(value) {
    zoom = MediaLogic.boundedZoom(value)
  }

  function togglePlayback() {
    if (viewerLoader.item && viewerLoader.item.togglePlayback)
      viewerLoader.item.togglePlayback()
  }

  function requestPlayback() {
    return !playback || playback.acquire(
      playbackSurface, chatRef, playbackMessageId)
  }

  onOpenedChanged: {
    if (!opened && playback) playback.releaseSurface(playbackSurface)
  }
  onCurrentIndexChanged: {
    if (playback) playback.releaseSurface(playbackSurface)
  }
  onSurfaceActiveChanged: if (!surfaceActive && playback)
    playback.releaseSurface(playbackSurface)

  Keys.onPressed: function(event) {
    if (!root.opened) return
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
      root.closeViewer()
      event.accepted = true
    } else if (event.key === Qt.Key_Left) {
      root.navigate(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right) {
      root.navigate(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
      root.setZoom(root.zoom + 0.25)
      event.accepted = true
    } else if (event.key === Qt.Key_Minus) {
      root.setZoom(root.zoom - 0.25)
      event.accepted = true
    } else if (event.key === Qt.Key_0) {
      root.setZoom(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Space) {
      root.togglePlayback()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(root.background.r * 0.34, root.background.g * 0.34,
      root.background.b * 0.34, 0.98)
  }

  Item {
    id: viewerHeader
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(root.width < Style.space(520) ? 52 : 60)
    z: 3

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.92)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(36)
      height: width
      radius: Style.cornerRadius
      color: closeHover.hovered
        ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "×"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }
      HoverHandler { id: closeHover }
      TapHandler { onTapped: root.closeViewer() }
    }

    Column {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(56)
      anchors.right: headerActions.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.currentItem ? String(root.currentItem.sender || "WhatsApp media") : "Media"
        color: root.foreground
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.currentItem && root.currentItem.timestamp
          ? Qt.formatDateTime(new Date(Number(root.currentItem.timestamp) * 1000), "ddd, MMM d · h:mm AP") : ""
        color: root.dim
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: headerActions
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Repeater {
        model: root.width < Style.space(520)
          ? [{ icon: "󰏫", action: "external", tip: "Open externally" }]
          : [
              { icon: "−", action: "out", tip: "Zoom out" },
              { icon: "󰁌", action: "reset", tip: "Fit" },
              { icon: "+", action: "in", tip: "Zoom in" },
              { icon: "󰏫", action: "external", tip: "Open externally" }
            ]
        delegate: Rectangle {
          required property var modelData
          width: Style.space(34)
          height: width
          radius: Style.cornerRadius
          color: actionHover.hovered
            ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
          opacity: root.video && modelData.action !== "external" ? 0.35 : 1
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: modelData.icon
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          HoverHandler { id: actionHover }
          ToolTip.visible: actionHover.hovered
          ToolTip.text: modelData.tip
          TapHandler {
            enabled: !root.video || modelData.action === "external"
            onTapped: {
              if (modelData.action === "out") root.setZoom(root.zoom - 0.25)
              else if (modelData.action === "reset") root.setZoom(1)
              else if (modelData.action === "in") root.setZoom(root.zoom + 0.25)
              else if (modelData.action === "external" && root.localPath !== "")
                root.openExternalRequested(root.localPath)
              root.forceActiveFocus()
            }
          }
        }
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    }
  }

  Loader {
    id: viewerLoader
    anchors.top: viewerHeader.bottom
    anchors.bottom: viewerFooter.top
    anchors.left: parent.left
    anchors.right: parent.right
    sourceComponent: root.video ? videoComponent
      : (root.animatedImage ? animatedImageComponent : imageComponent)
  }

  Component {
    id: imageComponent
    Item {
      function togglePlayback() {}
      clip: true
      Item {
        id: photoFrame
        width: parent.width
        height: parent.height
        transformOrigin: Item.Center
        scale: root.zoom
        Image {
          anchors.fill: parent
          anchors.margins: Style.space(18)
          source: root.localUrl(root.localPath)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          cache: true
          smooth: true
          mipmap: true
        }
      }
      Connections {
        target: root
        function onZoomChanged() {
          if (root.zoom === 1) { photoFrame.x = 0; photoFrame.y = 0 }
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: root.zoom > 1 ? Qt.OpenHandCursor : Qt.ArrowCursor
        drag.target: root.zoom > 1 ? photoFrame : null
        onDoubleClicked: {
          root.setZoom(root.zoom === 1 ? 2 : 1)
          if (root.zoom === 1) { photoFrame.x = 0; photoFrame.y = 0 }
        }
        onWheel: function(wheel) {
          root.setZoom(root.zoom + (wheel.angleDelta.y > 0 ? 0.25 : -0.25))
          wheel.accepted = true
        }
      }
    }
  }

  Component {
    id: animatedImageComponent
    Item {
      property bool userPaused: false
      property string mediaIdentity: root.localPath
      function togglePlayback() {
        if (!root.playbackGranted) {
          userPaused = false
          root.requestPlayback()
        } else userPaused = !userPaused
      }
      onMediaIdentityChanged: userPaused = false
      AnimatedImage {
        id: animation
        objectName: "viewerAnimatedMediaSurface"
        anchors.fill: parent
        anchors.margins: Style.space(18)
        source: root.localUrl(root.localPath)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        smooth: true
        playing: root.surfaceActive && root.opened && root.playbackGranted
          && !parent.userPaused
      }
      Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(16)
        width: animationState.implicitWidth + Style.space(14)
        height: Style.space(26)
        radius: height / 2
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.78)
        Text {
          textFormat: Text.PlainText
          id: animationState
          anchors.centerIn: parent
          text: animation.playing ? "GIF · playing" : "GIF · paused"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      TapHandler { onTapped: parent.togglePlayback() }
    }
  }

  Component {
    id: videoComponent
    VideoPlayer {
      source: root.localUrl(root.localPath)
      title: root.gifVideo ? "GIF paused" : "Video ready"
      active: root.surfaceActive && root.opened
      gifMode: root.gifVideo
      autoPlay: root.gifVideo
      playbackGranted: root.playbackGranted
      compact: false
      placeholderObjectName: "viewerVideoPlaceholder"
      controlsObjectName: "viewerVideoControls"
      foreground: root.foreground
      background: root.background
      accent: root.accent
      dim: root.dim
      dimmer: root.dim
      fontFamily: root.fontFamily
      onPlayRequested: root.requestPlayback()
    }
  }

  Rectangle {
    id: previousButton
    visible: root.items.length > 1 && root.width >= Style.space(460)
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(42)
    height: width
    radius: width / 2
    color: previousHover.hovered
      ? Style.hoverFillFor(root.foreground, root.accent)
      : Qt.rgba(root.background.r, root.background.g, root.background.b, 0.72)
    z: 3
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: "‹"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }
    HoverHandler { id: previousHover }
    TapHandler { onTapped: root.navigate(-1) }
  }

  Rectangle {
    visible: root.items.length > 1 && root.width >= Style.space(460)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(42)
    height: width
    radius: width / 2
    color: nextHover.hovered
      ? Style.hoverFillFor(root.foreground, root.accent)
      : Qt.rgba(root.background.r, root.background.g, root.background.b, 0.72)
    z: 3
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: "›"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }
    HoverHandler { id: nextHover }
    TapHandler { onTapped: root.navigate(1) }
  }

  Item {
    id: viewerFooter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.space(root.width < Style.space(520) ? 48 : 58)
    z: 3
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.90)
    }
    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(14)
      anchors.right: itemCounter.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: root.currentItem
        ? String(root.currentItem.text || root.currentItem.filename || root.mediaType || "Media") : ""
      color: root.foreground
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      textFormat: Text.PlainText
      id: itemCounter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      text: root.items.length > 1 ? (root.currentIndex + 1) + " / " + root.items.length
        : (root.video ? "Space: play/pause" : (Math.round(root.zoom * 100) + "%"))
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
