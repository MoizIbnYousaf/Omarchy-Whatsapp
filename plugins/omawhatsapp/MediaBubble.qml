import QtQuick
import QtMultimedia
import qs.Commons
import qs.Ui as Ui
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
  // The timeline's own audio player (TimelineAudio), when there is one: it
  // outlives this bubble, which is rebuilt whenever a message arrives.
  property var sharedAudio: null
  // 1×, 1.5× or 2×; the choice is shared by every voice note.
  property real audioRate: 1
  signal audioRateRequested(real rate)
  function nextAudioRate(rate) {
    return rate < 1.25 ? 1.5 : (rate < 1.75 ? 2 : 1)
  }
  function clockText(ms) {
    var seconds = Math.max(0, Math.floor(Number(ms || 0) / 1000))
    var minutes = Math.floor(seconds / 60)
    var rest = seconds % 60
    return minutes + ":" + (rest < 10 ? "0" : "") + rest
  }
  property real decodedMediaWidth: 0
  property real decodedMediaHeight: 0
  // The bubble's color as seen on screen: rounded photo corners and inset
  // cards are painted against it.
  property color cornerColor: background
  readonly property real mediaRadius: Style.space(9)

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
  readonly property bool previewableVideo: gifVideo || video
  readonly property bool animatedImage: MediaModel.isAnimatedImage(message)
  readonly property bool sticker: mediaType === "sticker"
  readonly property bool staticImage: MediaModel.isImage(message)
  readonly property bool audio: MediaModel.isAudio(message)
  readonly property bool location: mediaType === "location"
  readonly property string mediaKind: MediaModel.kind(message)
  readonly property string messageId: String(message && message.id || "")
  // A voice note has no file name (or WhatsApp's own .ogg/.opus); a named
  // audio file is shown as a file you can also play.
  readonly property bool voiceNote: audio && (filename === "" || /\.(ogg|opus)$/i.test(filename))
  // Voice notes carry no waveform in the mirror; a stable pattern from the
  // message id gives each one its own shape.
  readonly property var waveform: {
    var bars = []
    var seed = 0
    var key = messageId || "voice"
    for (var i = 0; i < key.length; i++) seed = (seed * 31 + key.charCodeAt(i)) >>> 0
    for (var b = 0; b < 32; b++) {
      seed = (seed * 1103515245 + 12345) >>> 0
      var edge = b < 3 || b > 28 ? 0.55 : 1
      bars.push(Math.max(0.18, ((seed >>> 16) % 100) / 100 * edge))
    }
    return bars
  }
  readonly property string extension: {
    var match = /\.([A-Za-z0-9]{1,5})$/.exec(filename)
    return match ? match[1].toUpperCase() : (mimeType.indexOf("pdf") >= 0 ? "PDF" : "FILE")
  }
  // One tint per kind of file, turned from the theme accent (PDF uses the
  // theme's alert color, as on the phone).
  function kindColor(ext) {
    var value = String(ext || "")
    if (value === "PDF") return Color.urgent
    var turns = { DOC: 0, DOCX: 0, ODT: 0, TXT: 0, XLS: 0.3, XLSX: 0.3, CSV: 0.3, ODS: 0.3,
      PPT: 0.1, PPTX: 0.1, ODP: 0.1, ZIP: 0.15, RAR: 0.15, "7Z": 0.15, MP3: 0.75, M4A: 0.75, WAV: 0.75 }
    var turn = turns[value]
    if (turn === undefined) return root.dim
    var hue = root.accent.hslHue >= 0 ? root.accent.hslHue : 0.6
    return Qt.hsla((hue + turn) % 1, Math.max(0.45, root.accent.hslSaturation),
      Math.min(0.72, Math.max(0.6, root.accent.hslLightness)), 1)
  }
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
    if (path === "__demo_photo__") return Qt.resolvedUrl("assets/demo-photo.png")
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
      if (root.sticker) return stickerComponent
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

            RoundedCorners { radius: Style.space(6); color: root.cornerColor }

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
    Item {
      implicitHeight: root.previewHeight
      clip: true
      Image {
        id: imagePreview
        objectName: "imageMediaSurface"
        anchors.fill: parent
        source: root.localUrl()
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        onSourceSizeChanged: root.adoptDecodedSize(sourceSize.width, sourceSize.height)
      }
      Rectangle {
        visible: imagePreview.status !== Image.Ready
        anchors.fill: parent
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)
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
      }
      RoundedCorners { radius: root.mediaRadius; color: root.cornerColor }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openRequested(root.localPath)
      }
    }
  }

  // A sticker: transparent, about 160 px, animated while the conversation is
  // on screen (WhatsApp loops them too); no card, no label, no external viewer.
  Component {
    id: stickerComponent
    Item {
      implicitHeight: Style.space(160)
      AnimatedImage {
        id: stickerImage
        objectName: "stickerSurface"
        width: Style.space(160)
        height: Style.space(160)
        source: root.localUrl()
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true
        playing: root.surfaceActive && frameCount > 1
      }
      Text {
        textFormat: Text.PlainText
        visible: stickerImage.status === Image.Error
        anchors.centerIn: stickerImage
        text: "Sticker"
        color: root.dimmer
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Component {
    id: animatedImageComponent
    Item {
      implicitHeight: root.previewHeight
      clip: true
      AnimatedImage {
        id: animatedPreview
        objectName: "animatedMediaSurface"
        anchors.fill: parent
        source: root.localUrl()
        fillMode: Image.PreserveAspectCrop
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
        anchors.top: parent.top
        anchors.margins: Style.space(8)
        width: gifLabel.implicitWidth + Style.space(12)
        height: Style.space(20)
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.55)
        Text {
          textFormat: Text.PlainText
          id: gifLabel
          anchors.centerIn: parent
          text: root.mediaType === "sticker" ? "sticker" : "GIF"
          color: "#f2f2f2"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      RoundedCorners { radius: root.mediaRadius; color: root.cornerColor }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openRequested(root.localPath)
      }
    }
  }

  Component {
    id: videoComponent
    Item {
      implicitHeight: root.previewHeight
      VideoPlayer {
        objectName: "videoMediaSurface"
        anchors.fill: parent
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
      RoundedCorners { radius: root.mediaRadius; color: root.cornerColor }
    }
  }

  Component {
    id: audioComponent
    // A voice note: round play button, its waveform filling as it plays,
    // time and speed below. A named audio file keeps its name above.
    Item {
      id: audioCard
      implicitHeight: audioRow.implicitHeight + Style.space(12)
      AudioOutput { id: audioSink; volume: 0.8 }
      // With a shared player this one only reads the length; it never plays.
      MediaPlayer {
        id: audioPlayer
        objectName: "audioMediaPlayer"
        source: root.localUrl()
        audioOutput: audioSink
        playbackRate: root.audioRate
      }
      readonly property bool shared: !!root.sharedAudio
      readonly property bool owns: shared && String(root.sharedAudio.currentId) === root.messageId
      readonly property var livePlayer: owns ? root.sharedAudio.player : audioPlayer
      readonly property bool playing: (!shared || owns) && livePlayer.playing
      readonly property real duration: owns && livePlayer.duration > 0 ? livePlayer.duration : audioPlayer.duration
      readonly property real position: !shared || owns ? livePlayer.position : 0
      readonly property real progress: duration > 0 ? Math.min(1, position / duration) : 0
      function seek(fraction) {
        var target = livePlayer
        if ((!shared || owns) && target.duration > 0 && target.seekable)
          target.position = Math.round(target.duration * Math.max(0, Math.min(1, fraction)))
      }
      function toggle() {
        if (shared) {
          if (owns) root.sharedAudio.toggle(root.messageId)
          else root.playbackRequested(root.messageId)
          return
        }
        if (audioPlayer.playing) {
          audioPlayer.pause()
        } else if (root.activePlaybackId === root.messageId) {
          audioPlayer.play()
        } else {
          root.playbackRequested(root.messageId)
          Qt.callLater(function() {
            if (root.surfaceActive && root.activePlaybackId === root.messageId) audioPlayer.play()
          })
        }
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
      Row {
        id: audioRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(2)
        spacing: Style.space(12)
        Rectangle {
          id: audioButton
          objectName: "audioPlayButton"
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(40)
          height: width
          radius: width / 2
          color: audioCard.playing ? root.foreground : root.accent
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: audioCard.playing ? 0 : 1
            text: audioCard.playing ? "󰏤" : "󰐊"
            color: root.background
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
          }
          MouseArea {
            anchors.fill: parent
            enabled: root.surfaceActive
            cursorShape: Qt.PointingHandCursor
            onClicked: audioCard.toggle()
          }
        }
        Column {
          width: audioRow.width - audioButton.width - audioRow.spacing - Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(5)
          Text {
            textFormat: Text.PlainText
            objectName: "audioFileName"
            visible: !root.voiceNote
            width: parent.width
            text: root.label()
            color: root.foreground
            elide: Text.ElideMiddle
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Item {
            id: waveArea
            objectName: "audioWaveform"
            width: parent.width
            height: Style.space(26)
            Row {
              anchors.fill: parent
              spacing: Math.max(1, (waveArea.width - 32 * 3) / 31)
              Repeater {
                model: root.waveform
                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  anchors.verticalCenter: parent.verticalCenter
                  width: 3
                  height: Math.max(3, waveArea.height * Number(modelData))
                  radius: width / 2
                  color: (index + 0.5) / 32 <= audioCard.progress ? root.accent
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
                }
              }
            }
            MouseArea {
              anchors.fill: parent
              enabled: root.surfaceActive && (!audioCard.shared || audioCard.owns)
                && audioCard.livePlayer.duration > 0 && audioCard.livePlayer.seekable
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: function(mouse) { audioCard.seek(mouse.x / waveArea.width) }
            }
          }
          // Time and speed on the left; the message time takes the right.
          Row {
            width: parent.width
            height: rateChip.height
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              objectName: "audioTime"
              anchors.verticalCenter: parent.verticalCenter
              text: audioCard.duration > 0
                ? (audioCard.position > 0 ? root.clockText(audioCard.position) + " / " : "")
                  + root.clockText(audioCard.duration)
                : (root.voiceNote ? "Voice message" : root.humanSize(root.message.file_size))
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              id: rateChip
              objectName: "audioRate"
              anchors.verticalCenter: parent.verticalCenter
              width: rateText.implicitWidth + Style.space(12)
              height: Style.space(20)
              radius: height / 2
              color: rateHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
              Text {
                textFormat: Text.PlainText
                id: rateText
                anchors.centerIn: parent
                text: (root.audioRate === 1.5 ? "1.5" : String(root.audioRate)) + "×"
                color: root.audioRate !== 1 ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              HoverHandler { id: rateHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.audioRateRequested(root.nextAudioRate(root.audioRate)) }
              Ui.PanelToolTip { visible: rateHover.hovered; text: "Playback speed" }
            }
          }
        }
      }
    }
  }

  Component {
    id: documentComponent
    // A file: its type as a colored badge, its name and size, one click to open.
    Rectangle {
      id: documentCard
      objectName: "documentCard"
      implicitHeight: Style.space(62)
      radius: Style.space(8)
      color: documentHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
        : Qt.rgba(root.background.r, root.background.g, root.background.b, 0.38)
      Rectangle {
        id: documentBadge
        objectName: "documentBadge"
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(36)
        height: Style.space(44)
        radius: Style.space(6)
        readonly property color tint: root.kindColor(root.extension)
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.16)
        Text {
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(6)
          text: root.extension
          color: documentBadge.tint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - 1
          font.weight: Font.Bold
        }
      }
      Column {
        anchors.left: documentBadge.right
        anchors.leftMargin: Style.space(12)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Text {
          textFormat: Text.PlainText
          objectName: "documentName"
          width: parent.width
          text: root.label()
          color: root.foreground
          elide: Text.ElideMiddle
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          text: [root.humanSize(root.message.file_size), root.extension !== "FILE" ? root.extension : ""]
            .filter(function(part) { return part !== "" }).join(" · ")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      HoverHandler { id: documentHover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: root.openRequested(root.localPath) }
    }
  }

  Component {
    id: missingComponent
    // Not on this computer yet: what it is, its size, and a round download
    // button; or a quiet note when WhatsApp no longer has it.
    Rectangle {
      objectName: "missingMediaSurface"
      implicitHeight: Style.space(62)
      radius: Style.space(8)
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, root.unavailable ? 0.22 : 0.38)
      Rectangle {
        id: missingIcon
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(36)
        height: Style.space(36)
        radius: Style.space(8)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.unavailable ? "󰋫" : root.previewableVideo ? "󰕧" : root.staticImage || root.animatedImage
            ? "󰋩" : root.audio ? "󰎈" : "󰈔"
          color: root.unavailable ? root.dimmer : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }
      Column {
        anchors.left: missingIcon.right
        anchors.leftMargin: Style.space(12)
        anchors.right: downloadButton.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.label()
          color: root.unavailable ? root.dim : root.foreground
          elide: Text.ElideMiddle
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          objectName: "missingMediaAction"
          width: parent.width
          text: root.unavailable ? "No longer on WhatsApp"
            : (root.busy
              ? (root.previewableVideo ? "Downloading video…" : "Downloading…")
              : (root.previewableVideo ? "Download to preview" : "Click to download")
              + (root.humanSize(root.message.file_size) !== ""
                ? " · " + root.humanSize(root.message.file_size) : ""))
          color: root.dimmer
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Rectangle {
        id: downloadButton
        objectName: "missingMediaDownload"
        visible: !root.unavailable
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? Style.space(34) : 0
        height: Style.space(34)
        radius: height / 2
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.busy ? 0.12 : 0.18)
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.busy ? "…" : "󰇚"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
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
    // The pin as on the phone: its name, address and coordinates, and a tap
    // opens it in the browser. No map tile is fetched just to draw the card.
    Rectangle {
      id: locationCard
      objectName: "locationCard"
      readonly property real latitude: Number(root.message.latitude)
      readonly property real longitude: Number(root.message.longitude)
      readonly property bool placed: isFinite(latitude) && isFinite(longitude)
        && root.message.latitude !== undefined && root.message.latitude !== null
      readonly property string mapUrl: placed
        ? "https://www.openstreetmap.org/?mlat=" + latitude.toFixed(6) + "&mlon="
          + longitude.toFixed(6) + "#map=17/" + latitude.toFixed(6) + "/" + longitude.toFixed(6)
        : ""
      implicitHeight: mapArt.height + locationRow.implicitHeight + Style.space(16)
      radius: Style.space(9)
      color: locationHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
        : Qt.rgba(root.background.r, root.background.g, root.background.b, 0.38)
      clip: true
      // A drawn map, not a fetched tile: nothing leaves the computer until
      // the pin is opened.
      Item {
        id: mapArt
        objectName: "locationMap"
        width: parent.width
        height: Style.space(110)
        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
        }
        Repeater {
          model: [{ x: -0.1, y: 0.62, w: 1.3, a: -9, t: 9 }, { x: 0.38, y: -0.2, w: 0.08, a: 12, t: 150 },
                  { x: -0.1, y: 0.22, w: 1.3, a: 6, t: 4 }, { x: 0.12, y: -0.2, w: 0.04, a: 8, t: 150 },
                  { x: 0.8, y: -0.2, w: 0.04, a: -6, t: 150 }]
          delegate: Rectangle {
            required property var modelData
            x: mapArt.width * modelData.x
            y: mapArt.height * modelData.y
            width: modelData.t === 150 ? Style.space(modelData.w * 100) : mapArt.width * modelData.w
            height: modelData.t === 150 ? mapArt.height * 1.4 : Style.space(modelData.t)
            rotation: modelData.a
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          }
        }
        Rectangle {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: Style.space(4)
          width: Style.space(34)
          height: width
          radius: width / 2
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
        }
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -Style.space(6)
          text: root.message.location_live === true ? "󰆣" : "󰍎"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconLarge
        }
      }
      Row {
        id: locationRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: mapArt.bottom
        anchors.margins: Style.space(10)
        spacing: Style.space(10)
        Column {
          width: parent.width
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            objectName: "locationName"
            width: parent.width
            text: String(root.message.location_name || "")
              || (root.message.location_live === true ? "Live location" : "Location")
            color: root.foreground
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: String(root.message.location_address || "")
            color: root.dim
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            objectName: "locationCoordinates"
            visible: locationCard.placed
            text: locationCard.placed
              ? locationCard.latitude.toFixed(5) + ", " + locationCard.longitude.toFixed(5) + "  ·  Open map ↗"
              : ""
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
      HoverHandler {
        id: locationHover
        cursorShape: locationCard.placed ? Qt.PointingHandCursor : Qt.ArrowCursor
      }
      TapHandler { onTapped: if (locationCard.placed) Qt.openUrlExternally(locationCard.mapUrl) }
    }
  }
}
