import QtQuick
import QtMultimedia
import OmaWhatsApp.Inputs as Native

// Only a regenerated, metadata-free preview enters QtMultimedia in the shell.
Item {
  id: root
  property url source
  property string kind: "audio"
  property bool wantsPlayback: false
  property alias audioOutput: player.audioOutput
  property alias videoOutput: player.videoOutput
  property alias playbackRate: player.playbackRate
  property alias loops: player.loops
  property alias position: player.position
  readonly property alias duration: player.duration
  readonly property alias seekable: player.seekable
  readonly property alias metaData: player.metaData
  readonly property bool playing: player.playing
  readonly property int playbackState: player.playbackState
  readonly property int mediaStatus: prepared.status === 2 ? MediaPlayer.LoadingMedia
    : prepared.status === 3 ? MediaPlayer.InvalidMedia : player.mediaStatus
  readonly property int error: prepared.status === 3 ? MediaPlayer.ResourceError : player.error
  readonly property string errorString: prepared.status === 3
    ? "This media could not be previewed safely. You can still save the original."
    : player.errorString
  signal errorOccurred(int error, string message)
  function prepare() {
    if (prepared.kind !== kind) { prepared.source = ""; prepared.kind = kind }
    prepared.source = source
  }
  function play() { wantsPlayback = true; prepare(); if (prepared.status === 1) player.play() }
  function pause() { wantsPlayback = false; player.pause() }
  function stop() { wantsPlayback = false; player.stop(); prepared.source = "" }
  onSourceChanged: { wantsPlayback = false; if (kind === "video") prepare(); else prepared.source = "" }
  onKindChanged: if (kind === "video") prepare(); else prepared.source = ""
  Component.onCompleted: if (kind === "video") prepare()
  Native.MediaSource {
    id: prepared
    onStatusChanged: {
      if (status === 1 && root.wantsPlayback) player.play()
      if (status === 3) root.errorOccurred(MediaPlayer.ResourceError, root.errorString)
    }
  }
  MediaPlayer {
    id: player
    source: prepared.safeSource
    onErrorOccurred: function(error, message) { root.errorOccurred(error, message) }
  }
}
