import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// The owner found the wait between Send and the message appearing too long:
// a sent text shows at once as a pending bubble and gives way to the stored
// row once the mirror has it. Texts sent while another is still going out wait
// in order, each already on screen, and one that fails stays as a bubble to
// try again or discard.
TestCase {
  id: testCase
  name: "PendingSend"
  width: 600
  height: 400
  visible: true
  when: windowShown

  readonly property var target: ({ account: "work", jid: "synthetic@s.whatsapp.net" })

  Component { id: serviceComponent; Oma.Service {} }

  function createService() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.ready = true
    service.statusReady = true
    service.statusAccount = "work"
    service.offlineMode = false
    service.readOnReply = false
    service.selectedChatAccount = "work"
    service.selectedChatJid = target.jid
    service.messages = [{ id: "older", text: "before", from_me: false, timestamp: 10 }]
    return service
  }

  function finish(service, exitCode, payload) {
    var process = findChild(service, "writeProcess")
    process.stdout.text = JSON.stringify(payload)
    process.running = false
    process.exited(exitCode)
  }

  function test_a_sent_text_shows_at_once_and_gives_way_to_the_stored_row() {
    var service = createService()
    verify(service.sendText(target, "  hello there  ", "", [], "app"))
    compare(service.selectedMessages.length, 2)
    var pending = service.selectedMessages[0]
    verify(pending.pending, "newest first: the pending bubble is at the bottom")
    compare(pending.text, "hello there")
    compare(pending.send_state, "sending")
    verify(pending.from_me)
    finish(service, 0, { ok: true, message_id: "SYNTHETIC-SENT" })
    compare(service.selectedMessages[0].send_state, "sent")
    service.messages = [{ id: "SYNTHETIC-SENT", text: "hello there", from_me: true, timestamp: 20 },
                        { id: "older", text: "before", from_me: false, timestamp: 10 }]
    compare(service.selectedMessages.length, 2, "no duplicate once the mirror has it")
    verify(service.selectedMessages[0].pending !== true)
    service.prunePendingSends()
    compare(service.pendingSends.length, 0)
  }

  function test_texts_typed_during_a_send_queue_in_order() {
    // The owner's report: type, Enter, keep typing, Enter again. Each Enter
    // must put its message on screen at once, whatever is still in flight.
    var service = createService()
    var process = findChild(service, "writeProcess")
    verify(service.sendText(target, "first", "", [], "app"))
    process.running = true
    verify(service.sendText(target, "second", "", [], "app"), "Enter during a send is accepted")
    verify(service.sendText(target, "third", "", [], "app"))
    compare(service.selectedMessages.map(function(m) { return m.text }),
      ["third", "second", "first", "before"], "all three on screen, newest first")
    compare(service.selectedMessages.map(function(m) { return String(m.send_state || "") }),
      ["queued", "queued", "sending", ""])
    compare(service.sendQueue.length, 2)
    finish(service, 0, { ok: true, message_id: "SYNTHETIC-1" })
    compare(JSON.parse(process.payload).text, "second", "the next one starts as the first ends")
    process.running = true
    compare(service.selectedMessages[1].send_state, "sending")
    finish(service, 0, { ok: true, message_id: "SYNTHETIC-2" })
    compare(JSON.parse(process.payload).text, "third")
    process.running = true
    finish(service, 0, { ok: true, message_id: "SYNTHETIC-3" })
    compare(service.sendQueue.length, 0)
    compare(service.selectedMessages.map(function(m) { return String(m.send_state || "") }),
      ["sent", "sent", "sent", ""])
  }

  function test_a_text_waits_behind_another_action_too() {
    var service = createService()
    service.writing = true
    verify(service.sendText(target, "after the read mark", "", [], "app"))
    compare(service.selectedMessages[0].send_state, "queued")
    service.writing = false
    tryVerify(function() { return service.selectedMessages[0].send_state === "sending" }, 1000)
    compare(JSON.parse(findChild(service, "writeProcess").payload).text, "after the read mark")
  }

  function test_a_failed_send_stays_on_screen_to_try_again_or_discard() {
    var service = createService()
    var failures = []
    service.writeFailed.connect(function(message, ref, details) { failures.push(details) })
    verify(service.sendText(target, "will fail", "", [], "app"))
    finish(service, 1, { ok: false, error: "Synthetic failure" })
    compare(service.selectedMessages.length, 2, "the text is not lost")
    var failed = service.selectedMessages[0]
    compare(failed.send_state, "failed")
    compare(failed.text, "will fail")
    verify(failures[0].pending_kept, "surfaces are told not to refill the composer")
    service.prunePendingSends()
    compare(service.pendingSends.length, 1, "a failed text waits for a decision")
    verify(service.resolvePendingSend(failed.id, "retry"))
    compare(JSON.parse(findChild(service, "writeProcess").payload).text, "will fail")
    compare(service.selectedMessages[0].send_state, "sending")
    finish(service, 1, { ok: false, error: "Synthetic failure" })
    verify(service.resolvePendingSend(service.selectedMessages[0].id, "discard"))
    compare(service.selectedMessages.length, 1)
    verify(!service.resolvePendingSend("pending:404", "retry"))
  }

  function test_a_queued_text_that_can_no_longer_go_is_marked_not_sent() {
    var service = createService()
    var process = findChild(service, "writeProcess")
    verify(service.sendText(target, "first", "", [], "app"))
    process.running = true
    verify(service.sendText(target, "second", "", [], "app"))
    service.offlineMode = true
    finish(service, 0, { ok: true, message_id: "SYNTHETIC-1" })
    compare(service.sendQueue.length, 0)
    compare(service.selectedMessages[0].text, "second")
    compare(service.selectedMessages[0].send_state, "failed")
  }

  function test_a_pending_bubble_stays_in_its_own_chat() {
    var service = createService()
    verify(service.sendText(target, "for this chat", "", [], "app"))
    service.selectedChatJid = "other@s.whatsapp.net"
    service.messages = []
    compare(service.selectedMessages.length, 0)
    service.selectedChatJid = target.jid
    compare(service.selectedMessages[0].text, "for this chat")
  }

  function test_files_show_a_pending_bubble_until_the_next_refresh() {
    var service = createService()
    verify(service.sendFilesReply(target, ["file:///tmp/synthetic%20report.pdf"], "see this", "", "app"))
    compare(service.selectedMessages[0].text, "📎 synthetic report.pdf\nsee this")
    finish(service, 0, { ok: true })
    compare(service.selectedMessages.length, 2, "still shown until the stored rows arrive")
    service.prunePendingSends()
    compare(service.selectedMessages.length, 1)
  }

  function test_a_picked_sticker_shows_at_once_as_itself() {
    var service = createService()
    verify(service.sendSticker(target, "/tmp/synthetic-sticker.webp", "", "app"))
    var pending = service.selectedMessages[0]
    verify(pending.pending)
    compare(pending.media_type, "sticker")
    compare(pending.local_path, "/tmp/synthetic-sticker.webp", "the bubble shows the sticker, not a label")
    finish(service, 0, { ok: true, kind: "sticker", message_id: "SYNTHETIC-STICKER" })
    compare(service.selectedMessages[0].send_state, "sent")
    service.messages = [{ id: "SYNTHETIC-STICKER", media_type: "sticker", from_me: true, timestamp: 30 }]
    compare(service.selectedMessages.length, 1)
  }

  function test_nothing_is_added_when_the_send_cannot_start() {
    var service = createService()
    service.offlineMode = true
    verify(!service.sendText(target, "offline", "", [], "app"))
    compare(service.pendingSends.length, 0)
  }

  Component {
    id: bubbleComponent
    Oma.MessageBubble {
      width: 420
      message: ({ id: "pending:1", text: "on its way", sender: "You", timestamp: 1787540100,
        from_me: true, media_type: "", reactions: [], pending: true, send_state: "sending" })
      foreground: "#eeeeee"; background: "#111111"; accent: "#66ccaa"
      dim: "#999999"; dimmer: "#777777"; fontFamily: "monospace"
    }
  }

  Component {
    id: failedBubbleComponent
    Oma.MessageBubble {
      width: 420
      message: ({ id: "pending:2", text: "did not go", sender: "You", timestamp: 1787540100,
        from_me: true, media_type: "", reactions: [], pending: true, send_state: "failed" })
      foreground: "#eeeeee"; background: "#111111"; accent: "#66ccaa"
      dim: "#999999"; dimmer: "#777777"; fontFamily: "monospace"
    }
  }

  SignalSpy { id: pendingSpy; signalName: "pendingSendRequested" }

  function test_a_failed_bubble_offers_try_again_and_discard() {
    var bubble = createTemporaryObject(failedBubbleComponent, testCase)
    verify(bubble.sendFailed)
    compare(bubble.menuActions.map(function(item) { return item.action }),
      ["retry-send", "copy", "discard-send"])
    compare(findChild(bubble, "messagePending").text, "󰀦")
    pendingSpy.target = bubble
    pendingSpy.clear()
    bubble.runMenuAction("retry-send")
    bubble.runMenuAction("discard-send")
    compare(pendingSpy.count, 2)
    compare(pendingSpy.signalArguments[0][0], "retry")
    compare(pendingSpy.signalArguments[1][0], "discard")
  }

  Component {
    id: sentBubbleComponent
    Oma.MessageBubble {
      width: 420
      message: ({ id: "stored-1", text: "went out", sender: "You", timestamp: 1787540100,
        from_me: true, media_type: "", reactions: [] })
      foreground: "#eeeeee"; background: "#111111"; accent: "#66ccaa"
      dim: "#999999"; dimmer: "#777777"; fontFamily: "monospace"
    }
  }

  function test_a_stored_message_shows_the_tick_wacli_recorded() {
    // Sent, delivered and read, as on the phone, and nothing when wacli has
    // no record for the message.
    var bubble = createTemporaryObject(sentBubbleComponent, testCase)
    var ticks = findChild(bubble, "messageTicks")
    verify(!ticks.visible, "no record, no tick")
    var cases = [["sent", "󰄬", "#777777"], ["delivered", "󰄭", "#777777"],
                 ["read", "󰄭", "#66ccaa"], ["played", "󰄭", "#66ccaa"]]
    for (var i = 0; i < cases.length; i++) {
      var next = Object.assign({}, bubble.message)
      next.status = cases[i][0]
      bubble.message = next
      verify(ticks.visible, cases[i][0])
      compare(ticks.text, cases[i][1], cases[i][0])
      compare(String(ticks.color), cases[i][2], cases[i][0])
    }
    var incoming = Object.assign({}, bubble.message)
    incoming.from_me = false
    bubble.message = incoming
    verify(!ticks.visible, "an incoming message never has ticks")
  }

  function test_a_pending_bubble_has_a_clock_and_no_message_actions() {
    var bubble = createTemporaryObject(bubbleComponent, testCase)
    verify(bubble.pending)
    verify(findChild(bubble, "messagePending").visible)
    compare(bubble.menuActions.map(function(item) { return item.action }), ["copy"])
    mouseMove(bubble, bubble.width - 20, 10)
    verify(!findChild(bubble, "messageActions").visible, "reply or react needs a stored message")
    compare(findChild(bubble, "messageBubbleSurface").opacity, 0.72)
  }
}
