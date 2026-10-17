import QtQuick
import QtMultimedia

// Only a regenerated, metadata-free preview enters QtMultimedia in the shell.
Item {
  id: root
  property url source
  property string kind: "audio"
  property bool wantsPlayback: false
  property bool preparationRequested: false
  readonly property var prepared: sourceLoader.item
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
  readonly property int mediaStatus: prepared && prepared.status === 2 ? MediaPlayer.LoadingMedia
    : prepared && prepared.status === 3 ? MediaPlayer.InvalidMedia : player.mediaStatus
  readonly property int error: prepared && prepared.status === 3 ? MediaPlayer.ResourceError : player.error
  readonly property string errorString: prepared && prepared.status === 3
    ? "This media could not be previewed safely. You can still save the original."
    : player.errorString
  signal errorOccurred(int error, string message)
  function prepare() {
    preparationRequested = String(source) !== ""
    if (!prepared) return
    if (prepared.kind !== kind) { prepared.source = ""; prepared.kind = kind }
    prepared.source = source
  }
  function play() { wantsPlayback = true; prepare(); if (prepared && prepared.status === 1) player.play() }
  function pause() { wantsPlayback = false; player.pause() }
  function stop() { wantsPlayback = false; player.stop(); preparationRequested = false }
  onSourceChanged: { wantsPlayback = false; if (kind === "video") prepare(); else preparationRequested = false }
  onKindChanged: if (kind === "video") prepare(); else preparationRequested = false
  Component.onCompleted: if (kind === "video") prepare()
  Loader {
    id: sourceLoader
    active: root.preparationRequested
    source: Qt.resolvedUrl("SafeMediaSource.qml")
    onLoaded: root.prepare()
  }
  Connections {
    target: root.prepared
    function onStatusChanged() {
      if (root.prepared.status === 1 && root.wantsPlayback) player.play()
      if (root.prepared.status === 3) root.errorOccurred(MediaPlayer.ResourceError, root.errorString)
    }
  }
  MediaPlayer {
    id: player
    source: root.prepared ? root.prepared.safeSource : ""
    onErrorOccurred: function(error, message) { root.errorOccurred(error, message) }
  }
}
