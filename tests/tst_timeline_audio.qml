import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// The owner's report: a voice note stopped when another message arrived, and
// the next voice note did not play after it ended. The timeline keeps one
// player outside the rows a new message rebuilds, and plays the next audio.
// The files do not exist, so nothing sounds.
TestCase {
  id: testCase
  name: "TimelineAudio"
  width: 1100
  height: 760
  visible: true
  when: windowShown

  Component { id: audioComponent; Oma.TimelineAudio { muted: true } }
  Component { id: appComponent; Oma.App { width: 1100; height: 760; demoMode: true; opened: true } }

  function voice(id, timestamp, fields) {
    return Object.assign({ id: id, text: "", sender: "Sam Rivera", sender_jid: "sam@s.whatsapp.net",
      timestamp: timestamp, from_me: false, media_type: "audio", mime_type: "audio/ogg; codecs=opus",
      local_path: "/nonexistent/omaw-" + id + ".ogg", reactions: [] }, fields || {})
  }

  function test_the_next_message_plays_only_when_it_is_audio_here() {
    var audio = createTemporaryObject(audioComponent, testCase)
    // Newest first, as the timeline.
    audio.messages = [
      { id: "text", text: "after", timestamp: 40, media_type: "" },
      voice("v3", 30), voice("v2", 20), voice("v1", 10),
      voice("gone", 5, { local_path: "" })
    ]
    compare(audio.nextAudioAfter("v1").id, "v2")
    compare(audio.nextAudioAfter("v2").id, "v3")
    compare(audio.nextAudioAfter("v3"), null, "a text in between ends the run")
    verify(!audio.playable(audio.itemFor("gone")), "not on this computer yet")
    var asked = []
    audio.advanceRequested.connect(function(id) { asked.push(id) })
    audio.activeId = "v1"
    verify(audio.play("v1"))
    compare(audio.currentId, "v1")
    verify(audio.finishCurrent())
    compare(asked, ["v2"])
    compare(audio.currentId, "", "the surface starts the next one")
  }

  function test_losing_the_lease_or_the_surface_stops_it() {
    var audio = createTemporaryObject(audioComponent, testCase)
    audio.messages = [voice("v1", 10)]
    audio.activeId = "v1"
    verify(audio.play("v1"))
    audio.activeId = "other"
    compare(audio.currentId, "", "another message or surface took the player")
    audio.activeId = "v1"
    verify(audio.play("v1"))
    audio.active = false
    compare(audio.currentId, "")
    verify(!audio.play("v1"), "a hidden surface plays nothing")
  }

  function test_a_message_arriving_does_not_stop_the_voice_note() {
    var app = createTemporaryObject(appComponent, testCase)
    app.demoItems = [voice("v2", 1787540060), voice("v1", 1787540000)]
    wait(100)
    var audio = findChild(app, "timelineAudio")
    verify(app.requestTimelinePlayback("v1"))
    compare(audio.currentId, "v1")
    // Another voice note arrives: the rows are rebuilt, the player is not.
    app.demoItems = [voice("v3", 1787540120)].concat(app.demoItems)
    wait(100)
    compare(audio.currentId, "v1", "still playing the same voice note")
    compare(app.activeTimelinePlaybackId, "v1")
  }

  function test_when_a_voice_note_ends_the_next_one_plays() {
    var app = createTemporaryObject(appComponent, testCase)
    app.demoItems = [{ id: "t", text: "later", sender: "Sam", timestamp: 1787540200, from_me: false,
      media_type: "", reactions: [] }, voice("v2", 1787540060), voice("v1", 1787540000)]
    wait(100)
    var audio = findChild(app, "timelineAudio")
    verify(app.requestTimelinePlayback("v1"))
    verify(audio.finishCurrent())
    compare(audio.currentId, "v2", "the next voice note")
    compare(app.activeTimelinePlaybackId, "v2")
    verify(!audio.finishCurrent(), "a text message ends the run")
    compare(audio.currentId, "")
  }

  function test_the_bubble_shows_the_shared_player() {
    var app = createTemporaryObject(appComponent, testCase)
    app.demoItems = [voice("v1", 1787540000)]
    wait(100)
    verify(app.requestTimelinePlayback("v1"))
    var cards = []
    function walk(item) {
      if (item.owns !== undefined && item.livePlayer !== undefined) cards.push(item)
      for (var i = 0; i < item.children.length; i++) walk(item.children[i])
    }
    tryVerify(function() { cards = []; walk(app); return cards.length > 0 }, 2000)
    verify(cards[0].owns, "the voice note's card follows the timeline player")
    compare(cards[0].livePlayer, findChild(app, "timelineAudio").player)
  }
}
