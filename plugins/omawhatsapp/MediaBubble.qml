import QtQuick
import QtMultimedia
import qs.Commons
import "MediaModel.js" as MediaModel

// Typed media renderer. WhatsApp GIFs are usually looping MP4 files, while
// uploaded .gif documents and stickers are image formats, so MIME alone is not
// enough to choose the correct QML primitive.
Item {
  id: root

  required property var message
  required property color foreground
  required property color background
  required property color accent
  required property color dim
  required property color dimmer
  required property string fontFamily
  property bool busy: false
  property bool surfaceActive: true
  property string activePlaybackId: ""
  property real decodedMediaWidth: 0
  property real decodedMediaHeight: 0

  signal openRequested(string path)
  signal downloadRequested()
  signal playbackRequested(string messageId)

  readonly property string mediaType: MediaModel.mediaType(message)
  readonly property string mimeType: MediaModel.mimeType(message)
  readonly property string filename: String(message.filename || "")
  readonly property string localPath: String(message.local_path || "")
  readonly property var albumItems: message && message.album_items
    && typeof message.album_items.length === "number" ? message.album_items : []
  readonly property bool album: mediaType === "album" && albumItems.length > 1
  readonly property bool hasLocal: localPath !== ""
  readonly property bool unavailable: message.media_unavailable === true
  readonly property bool gifVideo: MediaModel.isGifVideo(message)
  readonly property bool video: !gifVideo && MediaModel.isVideo(message)
  readonly property bool animatedImage: MediaModel.isAnimatedImage(message)
  readonly property bool staticImage: MediaModel.isImage(message)
  readonly property bool audio: MediaModel.isAudio(message)
  readonly property bool location: mediaType === "location"
  readonly property string mediaKind: MediaModel.kind(message)
  readonly property string messageId: String(message && message.id || "")
  // Media dimensions are visual content, not typography. Keep them responsive
  // without multiplying large previews by the shell's accessibility font scale.
  readonly property real previewHeight: MediaModel.previewHeight(width, message,
    140, 315, decodedMediaWidth, decodedMediaHeight)

  width: parent ? parent.width : implicitWidth
  implicitWidth: 560
  implicitHeight: renderer.item ? renderer.item.implicitHeight : 0
  height: implicitHeight

  onMessageChanged: {
    decodedMediaWidth = 0
    decodedMediaHeight = 0
  }

  function adoptDecodedSize(width, height) {
    var nextWidth = Number(width || 0)
    var nextHeight = Number(height || 0)
    if (!(nextWidth > 0 && nextHeight > 0)) return
    decodedMediaWidth = nextWidth
    decodedMediaHeight = nextHeight
  }

  function localUrl() {
    return localUrlFor(message)
  }

  function localUrlFor(item) {
    var path = String(item && item.local_path || "")
    if (path === "__demo__") return Qt.resolvedUrl("assets/demo-capture.svg")
    if (path === "__demo_photo__") return Qt.resolvedUrl("assets/demo-photo.svg")
    if (path === "__demo_video__") return ""
    if (path === "") return ""
    return MediaModel.encodedFileUrl(path)
  }

  function albumItemIsImage(item) {
    return MediaModel.isImage(item) || MediaModel.isAnimatedImage(item)
  }

  function albumItemIsVideo(item) {
    return MediaModel.isVideo(item)
  }

  function humanSize(bytes) {
    var value = Number(bytes || 0)
    if (value <= 0) return ""
    if (value < 1024) return value + " B"
    if (value < 1024 * 1024) return (value / 1024).toFixed(value < 10240 ? 1 : 0) + " KB"
    return (value / (1024 * 1024)).toFixed(value < 10 * 1024 * 1024 ? 1 : 0) + " MB"
  }

  function label() {
    if (filename !== "") return filename
    if (gifVideo || mimeType === "image/gif") return "GIF"
    if (mediaType === "sticker") return "Sticker"
    if (video) return "Video"
    if (audio) return "Voice message"
    if (staticImage || animatedImage) return "Image"
    if (location) return "Location"
    return mediaType !== "" ? mediaType.charAt(0).toUpperCase() + mediaType.slice(1) : "Attachment"
  }

  Loader {
    id: renderer
    anchors.left: parent.left
    anchors.right: parent.right
    sourceComponent: {
      if (root.album) return albumComponent
      if (root.location) return locationComponent
      if (!root.hasLocal) return missingComponent
      if (root.gifVideo || root.video) return videoComponent
      if (root.animatedImage) return animatedImageComponent
      if (root.staticImage) return imageComponent
      if (root.audio) return audioComponent
      return documentComponent
    }
  }

  Component {
    id: albumComponent
    Item {
      id: albumSurface
      readonly property var tiles: root.albumItems.slice(0, 4)
      readonly property int tileCount: tiles.length
      readonly property int columns: tileCount === 1 ? 1 : 2
      readonly property real gap: Style.space(4)
      readonly property real tileWidth: columns === 1 ? root.width
        : Math.max(0, (root.width - gap) / 2)
      readonly property real tileHeight: MediaModel.previewHeight(tileWidth,
        tiles.length > 0 ? tiles[0] : null, 110, 190)
      implicitHeight: albumGrid.implicitHeight

      Grid {
        id: albumGrid
        width: parent.width
        columns: albumSurface.columns
        columnSpacing: albumSurface.gap
        rowSpacing: albumSurface.gap

        Repeater {
          model: albumSurface.tiles
          delegate: Rectangle {
            id: albumTile
            required property var modelData
            required property int index
            width: albumSurface.columns === 1 ? albumGrid.width
              : (albumGrid.width - albumSurface.gap) / 2
            height: albumSurface.tileHeight
            radius: Style.cornerRadius
            color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.72)
            clip: true

            AnimatedImage {
              id: albumImage
              visible: root.albumItemIsImage(albumTile.modelData)
                && String(albumTile.modelData.local_path || "") !== ""
              anchors.fill: parent
              source: visible ? root.localUrlFor(albumTile.modelData) : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
              // Timeline albums are posters. Playing several animated tiles
              // would violate the single resident playback lease.
              playing: false
              smooth: true
            }

            Text {
              textFormat: Text.PlainText
              visible: !albumImage.visible || albumImage.status === Image.Error
              anchors.centerIn: parent
              width: parent.width - Style.space(18)
              text: root.albumItemIsVideo(albumTile.modelData) ? "▶  video" : "Image unavailable"
              color: root.dim
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              visible: root.albumItemIsVideo(albumTile.modelData)
              anchors.centerIn: parent
              width: Style.space(42)
              height: width
              radius: width / 2
              color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.82)
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "▶"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Rectangle {
              visible: albumTile.index === 3
                && Number(root.message.album_count || root.albumItems.length) > 4
              anchors.fill: parent
              color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.66)
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "+" + String(Number(root.message.album_count) - 3)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.weight: Font.DemiBold
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: String(albumTile.modelData.local_path || "") !== ""
                ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                var path = String(albumTile.modelData.local_path || "")
                if (path !== "") root.openRequested(path)
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: imageComponent
    Rectangle {
      implicitHeight: root.previewHeight
      radius: Style.cornerRadius
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)
      clip: true
      Image {
        id: imagePreview
        objectName: "imageMediaSurface"
        anchors.fill: parent
        anchors.margins: Style.space(3)
        source: root.localUrl()
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        smooth: true
        onSourceSizeChanged: root.adoptDecodedSize(sourceSize.width, sourceSize.height)
      }
      Text {
        textFormat: Text.PlainText
        visible: imagePreview.status === Image.Error
        anchors.centerIn: parent
        width: parent.width - Style.space(24)
        text: "Preview unavailable · click to open"
        color: root.dimmer
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openRequested(root.localPath)
      }
    }
  }

  Component {
    id: animatedImageComponent
    Rectangle {
      implicitHeight: root.previewHeight
      radius: Style.cornerRadius
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)
      clip: true
      AnimatedImage {
        id: animatedPreview
        objectName: "animatedMediaSurface"
        anchors.fill: parent
        anchors.margins: Style.space(3)
        source: root.localUrl()
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        // Timeline animations stay on their first frame; opening the viewer
        // acquires the shared playback lease before animation begins.
        playing: false
        smooth: true
        onSourceSizeChanged: root.adoptDecodedSize(sourceSize.width, sourceSize.height)
      }
      Text {
        textFormat: Text.PlainText
        visible: animatedPreview.status === Image.Error
        anchors.centerIn: parent
        width: parent.width - Style.space(24)
        text: "Preview unavailable · click to open"
        color: root.dimmer
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(8)
        width: gifLabel.implicitWidth + Style.space(10)
        height: Style.space(22)
        radius: height / 2
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.82)
        Text {
          textFormat: Text.PlainText
          id: gifLabel
          anchors.centerIn: parent
          text: root.mediaType === "sticker" ? "sticker" : "GIF"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openRequested(root.localPath)
      }
    }
  }

  Component {
    id: videoComponent
    VideoPlayer {
      objectName: "videoMediaSurface"
      implicitHeight: root.previewHeight
      source: root.localUrl()
      title: root.label()
      active: root.surfaceActive
      gifMode: root.gifVideo
      autoPlay: false
      playbackGranted: root.activePlaybackId === root.messageId
      compact: true
      allowOpen: true
      foreground: root.foreground
      background: root.background
      accent: root.accent
      dim: root.dim
      dimmer: root.dimmer
      fontFamily: root.fontFamily
      onIntrinsicWidthChanged: root.adoptDecodedSize(intrinsicWidth, intrinsicHeight)
      onIntrinsicHeightChanged: root.adoptDecodedSize(intrinsicWidth, intrinsicHeight)
      onPlayRequested: root.playbackRequested(root.messageId)
      onOpenRequested: root.openRequested(root.localPath)
    }
  }

  Component {
    id: audioComponent
    Rectangle {
      implicitHeight: Style.space(58)
      radius: Style.cornerRadius
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)
      AudioOutput { id: audioSink; volume: 0.8 }
      MediaPlayer {
        id: audioPlayer
        objectName: "audioMediaPlayer"
        source: root.localUrl()
        audioOutput: audioSink
      }
      Connections {
        target: root
        function onSurfaceActiveChanged() {
          if (!root.surfaceActive) audioPlayer.stop()
        }
        function onActivePlaybackIdChanged() {
          if (root.activePlaybackId !== root.messageId) audioPlayer.stop()
        }
      }
      Rectangle {
        id: audioButton
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(34)
        height: width
        radius: width / 2
        color: root.accent
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: audioPlayer.playing ? "Ⅱ" : "▶"
          color: root.background
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          anchors.fill: parent
          enabled: root.surfaceActive
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (audioPlayer.playing) {
              audioPlayer.pause()
            } else if (root.activePlaybackId === root.messageId) {
              audioPlayer.play()
            } else {
              root.playbackRequested(root.messageId)
              Qt.callLater(function() {
                if (root.surfaceActive
                    && root.activePlaybackId === root.messageId) audioPlayer.play()
              })
            }
          }
        }
      }
      Column {
        anchors.left: audioButton.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(5)
        Text {
          textFormat: Text.PlainText
          text: root.label()
          color: root.foreground
          elide: Text.ElideRight
          width: parent.width
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          width: parent.width
          height: Style.space(3)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
          Rectangle {
            width: audioPlayer.duration > 0
              ? parent.width * Math.min(1, audioPlayer.position / audioPlayer.duration) : 0
            height: parent.height
            radius: height / 2
            color: root.accent
          }
        }
      }
    }
  }

  Component {
    id: documentComponent
    Rectangle {
      implicitHeight: Style.space(58)
      radius: Style.cornerRadius
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)
      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(9)
        Text {
          textFormat: Text.PlainText
          text: "󰈔"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
        Column {
          width: parent.width - Style.space(36)
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.label()
            color: root.foreground
            elide: Text.ElideMiddle
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            text: root.humanSize(root.message.file_size)
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openRequested(root.localPath)
      }
    }
  }

  Component {
    id: missingComponent
    Rectangle {
      objectName: "missingMediaSurface"
      implicitHeight: Style.space(68)
      radius: Style.cornerRadius
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.45)
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.13)
      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(11)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)
        Text {
          textFormat: Text.PlainText
          text: root.unavailable ? "󰚌" : (root.busy ? "…" : "󰇚")
          color: root.unavailable ? root.dimmer : root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
        Column {
          width: parent.width - Style.space(40)
          spacing: Style.space(3)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.label()
            color: root.foreground
            elide: Text.ElideMiddle
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            text: root.unavailable ? "No longer available from WhatsApp"
              : (root.busy ? "Downloading…" : "Click to download"
                + (root.humanSize(root.message.file_size) !== ""
                  ? " · " + root.humanSize(root.message.file_size) : ""))
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.unavailable && !root.busy
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.downloadRequested()
      }
    }
  }

  Component {
    id: locationComponent
    Rectangle {
      implicitHeight: Style.space(58)
      radius: Style.cornerRadius
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.45)
      Row {
        anchors.centerIn: parent
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          text: "󰍎"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
        Text {
          textFormat: Text.PlainText
          text: "Location"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
