import QtQuick
import QtMultimedia
import "MediaModel.js" as MediaModel

// The one audio player of a timeline. It lives outside the message rows: a
// message arriving rebuilds the rows, and a player inside one stopped with
// it. When a voice note ends, the next message plays if it is audio too, as
// on the phone.
Item {
  id: root

  // Newest first, as the timeline lists them.
  property var messages: []
  // The message this surface holds the playback lease for; any other value
  // (another chat, another surface) stops the player.
  property string activeId: ""
  property real rate: 1
  property bool active: true
  // Which message is loaded in the player, "" when none.
  property string currentId: ""
  readonly property alias player: player
  // Tests keep it silent.
  property bool muted: false
  // Asks the surface to take the lease for the next audio, then play it.
  signal advanceRequested(string messageId)

  AudioOutput { id: sink; volume: 0.8; muted: root.muted }
  MediaPlayer {
    id: player
    objectName: "timelineAudioPlayer"
    audioOutput: sink
    playbackRate: root.rate
    onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) root.finishCurrent()
  }

  // The loaded voice note played to its end: on to the next one, if any.
  function finishCurrent() {
    if (currentId === "") return false
    var next = nextAudioAfter(currentId)
    currentId = ""
    if (!next) return false
    advanceRequested(String(next.id))
    return true
  }

  onActiveIdChanged: if (activeId !== currentId) stop()
  onActiveChanged: if (!active) stop()

  function stop() {
    player.stop()
    currentId = ""
  }

  function itemFor(id) {
    var target = String(id || "")
    var list = messages || []
    for (var i = 0; i < list.length; i++)
      if (list[i] && String(list[i].id || "") === target) return list[i]
    return null
  }

  function playable(item) {
    return !!item && String(item.media_type || "").toLowerCase() === "audio"
      && String(item.local_path || "") !== "" && item.revoked !== true
  }

  // The message right after this one, when it is audio this computer has.
  function nextAudioAfter(id) {
    var list = messages || []
    for (var i = 0; i < list.length; i++) {
      if (!list[i] || String(list[i].id || "") !== String(id || "")) continue
      var next = i > 0 ? list[i - 1] : null
      return playable(next) ? next : null
    }
    return null
  }

  function play(id) {
    var item = itemFor(id)
    if (!active || !playable(item)) return false
    var url = MediaModel.encodedFileUrl(String(item.local_path))
    if (currentId !== String(item.id) || String(player.source) !== String(url)) {
      player.stop()
      player.source = url
      currentId = String(item.id)
    }
    player.play()
    return true
  }

  function toggle(id) {
    if (currentId !== String(id || "")) return false
    if (player.playbackState === MediaPlayer.PlayingState) player.pause()
    else player.play()
    return true
  }
}
