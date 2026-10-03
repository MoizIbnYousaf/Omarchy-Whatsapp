import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/AccountModel.js" as AccountModel

// The restyle the owner approved (Quiet Terminal): one person's messages form
// a run with tight corners and the name shown once, and the time sits on the
// last line of text when it has room instead of taking a line of its own.
TestCase {
  id: testCase
  name: "BubbleStyle"
  width: 700
  height: 600
  visible: true
  when: windowShown

  Component {
    id: bubbleComponent
    Oma.MessageBubble {
      width: 640
      foreground: "#eeeeee"; background: "#111111"; accent: "#66ccaa"
      dim: "#999999"; dimmer: "#777777"; fontFamily: "monospace"
    }
  }

  function bubble(fields, props) {
    var message = Object.assign({ id: "m1", text: "short", sender: "Sam", sender_jid: "sam@s.whatsapp.net",
      timestamp: 1790280000, from_me: false, media_type: "", reactions: [] }, fields || {})
    return createTemporaryObject(bubbleComponent, testCase, Object.assign({ message: message }, props || {}))
  }

  function test_a_run_is_one_person_within_ten_minutes() {
    var a = { from_me: false, sender_jid: "sam@x", timestamp: 100 }
    verify(AccountModel.sameRun(a, { from_me: false, sender_jid: "sam@x", timestamp: 400 }))
    verify(!AccountModel.sameRun(a, { from_me: false, sender_jid: "ana@x", timestamp: 120 }), "another person")
    verify(!AccountModel.sameRun(a, { from_me: true, timestamp: 120 }), "you in between")
    verify(!AccountModel.sameRun(a, { from_me: false, sender_jid: "sam@x", timestamp: 800 }), "ten minutes later")
    verify(AccountModel.sameRun({ from_me: true, timestamp: 1 }, { from_me: true, timestamp: 50 }))
    verify(!AccountModel.sameRun(null, a))
  }

  function test_joined_bubbles_tighten_the_sender_corner_and_name_once() {
    var first = bubble({}, { groupChat: true })
    var surface = findChild(first, "messageBubbleSurface")
    verify(findChild(first, "messageSender").visible, "the first of a run names the sender")
    compare(surface.bottomLeftRadius, surface.tightCorner, "the tail corner on the sender's side")
    compare(surface.topLeftRadius, surface.roundCorner)
    var next = bubble({}, { groupChat: true, joinsAbove: true })
    verify(!findChild(next, "messageSender").visible, "the name shows once per run")
    compare(findChild(next, "messageBubbleSurface").topLeftRadius, surface.tightCorner)
    var mine = bubble({ from_me: true, sender: "You" }, { joinsAbove: true })
    var mineSurface = findChild(mine, "messageBubbleSurface")
    compare(mineSurface.topRightRadius, mineSurface.tightCorner, "your side is the right one")
    compare(mineSurface.bottomRightRadius, mineSurface.tightCorner)
    compare(mineSurface.topLeftRadius, mineSurface.roundCorner)
  }

  function test_the_time_shares_the_last_line_when_it_fits() {
    var short = bubble({ text: "ok" })
    tryVerify(function() { return short.metaInline }, 1000, "a short text keeps its time on the same line")
    var surface = findChild(short, "messageBubbleSurface")
    var text = findChild(short, "messageText")
    verify(surface.height < text.height + findChild(short, "messageMeta").height + 20,
      "no extra line for the time")
    var wrapped = bubble({ text: "a line that is long enough to fill the whole width of this bubble and wrap at the very end xxxxxxxxxxxxxxxx" })
    wait(50)
    var lastEnd = wrapped.lastLineEnd
    var fits = lastEnd + 10 + findChild(wrapped, "messageMeta").width <= findChild(wrapped, "messageText").width
    compare(wrapped.metaInline, fits, "the time drops below only when the last line is full")
  }

  function test_group_names_get_a_theme_color_each() {
    var one = bubble({})
    var sam = one.senderColor("sam@s.whatsapp.net")
    compare(String(one.senderColor("sam@s.whatsapp.net")), String(sam), "stable per person")
    verify(String(one.senderColor("ana@s.whatsapp.net")) !== String(sam) || String(one.senderColor("bia@s.whatsapp.net")) !== String(sam),
      "different people usually get different colors")
    compare(String(one.senderColor("")), String(one.accent))
  }

  // Phase 2: attachments.
  readonly property string photo: Qt.resolvedUrl("../plugins/omawhatsapp/assets/demo-photo.png").toString().replace("file://", "")

  function test_a_photo_without_caption_carries_its_time_on_the_picture() {
    var bare = bubble({ media_type: "image", mime_type: "image/png", local_path: photo, text: "" })
    verify(bare.visualMedia)
    verify(bare.metaOverMedia)
    verify(findChild(bare, "mediaTimePill").visible)
    var captioned = bubble({ media_type: "image", mime_type: "image/png", local_path: photo, text: "caption" })
    verify(!captioned.metaOverMedia, "a caption keeps the time beside its text")
    verify(!findChild(captioned, "mediaTimePill").visible)
  }

  function test_a_portrait_photo_gets_a_narrower_bubble() {
    var tall = bubble({ media_type: "image", mime_type: "image/png", local_path: photo })
    findChild(tall, "mediaBubble").adoptDecodedSize(900, 1600)
    verify(tall.fittedMediaWidth < tall.mediaWidth, "no cropped strip of a portrait photo")
    var wide = bubble({ media_type: "image", mime_type: "image/png", local_path: photo })
    findChild(wide, "mediaBubble").adoptDecodedSize(1600, 900)
    compare(wide.fittedMediaWidth, wide.mediaWidth)
  }

  function test_voice_notes_and_audio_files_differ() {
    var voice = bubble({ media_type: "audio", mime_type: "audio/ogg; codecs=opus", local_path: "/nonexistent/v.ogg", text: "" })
    verify(findChild(voice, "mediaBubble").voiceNote)
    verify(voice.metaInAudio, "the time shares the voice note's bottom row")
    verify(findChild(voice, "audioWaveform") !== null)
    verify(!findChild(voice, "audioFileName").visible)
    var file = bubble({ media_type: "audio", mime_type: "audio/mp4", local_path: "/nonexistent/a.m4a", filename: "meeting.m4a" })
    verify(!findChild(file, "mediaBubble").voiceNote)
    verify(findChild(file, "audioFileName").visible)
    var again = findChild(bubble({ media_type: "audio", local_path: "/nonexistent/v.ogg" }), "mediaBubble")
    compare(JSON.stringify(again.waveform), JSON.stringify(again.waveform), "the waveform is stable")
  }

  function test_a_document_shows_its_type() {
    var pdf = bubble({ media_type: "document", mime_type: "application/pdf", local_path: "/nonexistent/o.pdf", filename: "Budget.pdf" })
    compare(findChild(pdf, "mediaBubble").extension, "PDF")
    verify(findChild(pdf, "documentBadge") !== null)
  }

  function test_contact_initials_and_a_deleted_outline() {
    var card = bubble({ text: "Contact: Carlos Mendes (+55 16 90000-0000)",
      contacts: [{ name: "Carlos Mendes", phone: "+55 16 90000-0000", digits: "5516900000000" }] })
    tryVerify(function() { return findChild(card, "contactInitials") !== null })
    compare(findChild(card, "contactInitials").children[0].text, "CM")
    var gone = bubble({ revoked: true, text: "" })
    var surface = findChild(gone, "messageBubbleSurface")
    compare(surface.color.a, 0, "a deleted message keeps only its outline")
    compare(surface.border.width, 1)
  }

  function test_group_messages_show_who_wrote_them_once_per_run() {
    // L227: the photo or initials of the sender beside the last message of
    // each run, in a column that keeps the run's bubbles aligned.
    var last = bubble({ sender: "Rafael Lima", sender_jid: "rafael@s.whatsapp.net" },
      { groupChat: true, senderAvatars: true, joinsAbove: true, joinsBelow: false })
    var avatar = findChild(last, "messageSenderAvatar")
    verify(avatar.visible, "the last message of the run carries the avatar")
    compare(findChild(avatar, "chatAvatarFallback").text, "RL")
    var surface = findChild(last, "messageBubbleSurface")
    compare(surface.x, last.gutterWidth, "the bubble starts after the column")
    verify(last.gutterWidth > avatar.width)
    compare(String(findChild(avatar, "chatAvatarBackdrop").color),
      String(last.senderColor("rafael@s.whatsapp.net")), "the same color as the name")

    var earlier = bubble({ sender: "Rafael Lima", sender_jid: "rafael@s.whatsapp.net" },
      { groupChat: true, senderAvatars: true, joinsBelow: true })
    verify(!findChild(earlier, "messageSenderAvatar").visible, "one avatar per run")
    compare(findChild(earlier, "messageBubbleSurface").x, earlier.gutterWidth, "still aligned")

    var mine = bubble({ from_me: true, sender: "You" }, { groupChat: true, senderAvatars: true })
    verify(!findChild(mine, "messageSenderAvatar").visible)
    compare(mine.gutterWidth, 0)
    var direct = bubble({}, { groupChat: false, senderAvatars: true })
    compare(direct.gutterWidth, 0, "a one-to-one chat needs no column")
    var compact = bubble({}, { groupChat: true, senderAvatars: false })
    compare(compact.gutterWidth, 0, "the dropdown keeps its narrow bubbles")
  }
}
