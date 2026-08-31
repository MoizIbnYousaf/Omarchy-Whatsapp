import QtQuick
import QtMultimedia
import qs.Commons
import "MediaModel.js" as MediaModel

// One playback state machine for timeline previews and the full-window viewer.
// Ordinary videos wait for an explicit play; GIF videos may opt into autoplay.
Item {
  id: root

  required property color foreground
  required property color background
  required property color accent
  required property color dim
  required property color dimmer
  required property string fontFamily
  property url source
  property string title: "Video"
  property bool active: true
  property bool gifMode: false
  property bool autoPlay: false
  property bool compact: false
  property bool allowOpen: false
  property bool playbackGranted: true
  property bool hasStartedPlayback: false
  property string placeholderObjectName: "videoPosterOverlay"
  property string controlsObjectName: "videoPlaybackControls"

  signal openRequested()
  signal playRequested()

  readonly property bool loading: player.mediaStatus === MediaPlayer.LoadingMedia
    || player.mediaStatus === MediaPlayer.BufferingMedia
    || player.mediaStatus === MediaPlayer.StalledMedia
  readonly property bool failed: player.error !== MediaPlayer.NoError
    || player.mediaStatus === MediaPlayer.InvalidMedia
  readonly property bool playing: player.playing
  readonly property bool hasDecodedFrame: videoOutput.sourceRect.width > 0
    && videoOutput.sourceRect.height > 0
  readonly property bool posterShown: loading || failed || !hasStartedPlayback
  readonly property int duration: player.duration
  readonly property int position: player.position
  readonly property var mediaResolution: player.metaData.value(MediaMetaData.Resolution)
  readonly property real intrinsicWidth: Number(videoOutput.sourceRect.width
    || (mediaResolution ? mediaResolution.width : 0) || 0)
  readonly property real intrinsicHeight: Number(videoOutput.sourceRect.height
    || (mediaResolution ? mediaResolution.height : 0) || 0)

  clip: true

  function playIfAutomatic() {
    if (!active || !autoPlay || String(source) === "") return
    if (!playbackGranted) playRequested()
    Qt.callLater(function() {
      if (root.active && root.autoPlay && root.playbackGranted
          && String(root.source) !== "") player.play()
    })
  }

  function togglePlayback() {
    if (!active || String(source) === "" || failed || loading) return
    if (player.playing) {
      player.pause()
      return
    }
    if (!playbackGranted) {
      playRequested()
      Qt.callLater(function() {
        if (root.active && root.playbackGranted && !root.failed) player.play()
      })
      return
    }
    player.play()
  }

  function stopPlayback() {
    player.stop()
  }

  onActiveChanged: {
    if (!active) player.stop()
    else playIfAutomatic()
  }
  onSourceChanged: {
    player.stop()
    hasStartedPlayback = false
    playIfAutomatic()
  }
  onAutoPlayChanged: playIfAutomatic()
  onPlaybackGrantedChanged: if (!playbackGranted) player.stop()
  Component.onCompleted: playIfAutomatic()

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.72)
  }

  VideoOutput {
    id: videoOutput
    anchors.fill: parent
    anchors.margins: root.compact ? 0 : Style.space(12)
    fillMode: VideoOutput.PreserveAspectFit
  }

  AudioOutput {
    id: audioOutput
    muted: root.gifMode
    volume: root.compact ? 0.8 : 0.85
  }

  MediaPlayer {
    id: player
    objectName: "videoMediaPlayer"
    source: root.source
    videoOutput: videoOutput
    audioOutput: audioOutput
    loops: root.gifMode ? MediaPlayer.Infinite : MediaPlayer.Once
    onPlaybackStateChanged: {
      if (playbackState === MediaPlayer.PlayingState)
        root.hasStartedPlayback = true
    }
  }

  TapHandler { onTapped: root.togglePlayback() }

  Rectangle {
    id: poster
    objectName: root.placeholderObjectName
    visible: root.posterShown
    anchors.centerIn: parent
    width: root.compact ? parent.width
      : Math.max(0, Math.min(parent.width - Style.space(36), 460))
    height: root.compact ? parent.height
      : Math.max(0, Math.min(parent.height - Style.space(36), 210))
    radius: Style.cornerRadius
    color: root.compact
      ? Qt.rgba(root.background.r, root.background.g, root.background.b, 0.42)
      : Qt.rgba(root.background.r, root.background.g, root.background.b, 0.72)
    border.width: root.compact ? 0 : 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g,
      root.foreground.b, 0.12)

    Column {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.compact ? -Style.space(10) : 0
      width: Math.max(0, Math.min(parent.width - Style.space(24), 360))
      spacing: Style.space(8)

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(Style.space(root.compact ? 52 : 58), 72)
        height: width
        radius: width / 2
        color: root.failed ? Qt.rgba(root.foreground.r,
          root.foreground.g, root.foreground.b, 0.12) : root.accent
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          anchors.horizontalCenterOffset: root.failed ? 0 : 1
          text: root.failed ? "!" : (root.loading ? "…" : "▶")
          color: root.failed ? root.dimmer : root.background
          font.family: root.fontFamily
          font.pixelSize: root.compact ? Style.font.body : Style.font.title
          font.weight: Font.DemiBold
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.failed ? "Video preview unavailable"
          : (root.loading ? "Preparing video…"
            : (root.gifMode && !root.compact ? "GIF paused" : root.title))
        color: root.foreground
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideMiddle
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.failed ? "Try opening this file in another player"
          : (root.loading ? "" : (root.compact ? "Click to play"
            : "Click or press Space to play"))
        color: root.dimmer
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Rectangle {
    id: controls
    objectName: root.controlsObjectName
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(root.compact ? 8 : 18)
    height: Math.min(Style.space(34), 48)
    radius: Style.cornerRadius
    color: Qt.rgba(root.background.r, root.background.g, root.background.b,
      root.compact ? 0.82 : 0.78)

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: player.playing ? "Ⅱ" : "▶"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Rectangle {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(34)
      anchors.right: timeLabel.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.min(Style.space(4), 6)
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
      Rectangle {
        width: player.duration > 0
          ? parent.width * Math.min(1, player.position / player.duration) : 0
        height: parent.height
        radius: height / 2
        color: root.accent
      }
      MouseArea {
        anchors.fill: parent
        enabled: player.duration > 0 && !root.failed
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: function(mouse) {
          player.position = player.duration * mouse.x / width
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      id: timeLabel
      anchors.right: openButton.visible ? openButton.left : parent.right
      anchors.rightMargin: Style.space(openButton.visible ? 8 : 10)
      anchors.verticalCenter: parent.verticalCenter
      text: MediaModel.formatDuration(player.position) + " / "
        + MediaModel.formatDuration(player.duration)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Rectangle {
      id: openButton
      visible: root.allowOpen
      anchors.right: parent.right
      anchors.rightMargin: Style.space(5)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(Style.space(25), 32)
      height: width
      radius: Style.cornerRadius
      color: openHover.hovered
        ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
        : "transparent"
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "↗"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      HoverHandler { id: openHover }
      TapHandler {
        onTapped: {
          player.pause()
          root.openRequested()
        }
      }
    }
  }
}
