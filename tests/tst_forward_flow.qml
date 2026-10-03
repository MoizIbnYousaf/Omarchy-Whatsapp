import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// The forward flow the owner asked to redo (L218, with L195): pick messages
// in the conversation, choose several chats and an optional note, and see
// where they went, with a way to open that chat.
TestCase {
  id: testCase
  name: "ForwardFlow"
  width: 1100
  height: 760
  visible: true
  when: windowShown

  Component { id: appComponent; Oma.App { width: 1100; height: 760; demoMode: true; opened: true } }
  Component { id: serviceComponent; Oma.Service {} }

  readonly property var origin: ({ account: "work", jid: "origin@s.whatsapp.net" })

  function createService() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.ready = true
    service.statusReady = true
    service.statusAccount = "work"
    service.offlineMode = false
    service.readOnReply = false
    service.selectedChatAccount = "work"
    service.selectedChatJid = origin.jid
    return service
  }

  function finish(service, exitCode, payload) {
    var process = findChild(service, "writeProcess")
    process.stdout.text = JSON.stringify(payload)
    process.running = false
    process.exited(exitCode)
  }

  function test_forward_starts_a_selection_that_can_grow() {
    var app = createTemporaryObject(appComponent, testCase)
    var first = app.demoItems[0]
    verify(app.startForward(first))
    verify(app.selectingMessages)
    var bar = findChild(app, "selectionBar")
    verify(bar.visible)
    compare(findChild(app, "selectionCount").text, "1 selected")
    verify(app.toggleMessageSelection(app.demoItems[3]))
    compare(findChild(app, "selectionCount").text, "2 selected")
    verify(app.toggleMessageSelection(app.demoItems[3]), "a second click unpicks")
    compare(app.selectedMessageIds.length, 1)
    // An album row stands for every photo in it.
    var album = app.visibleMessages.filter(function(item) { return item.album_items })[0]
    verify(album !== undefined)
    verify(app.toggleMessageSelection(album))
    compare(app.selectedMessageIds.length, 3)
    verify(app.isMessageSelected(album))
    app.cancelSelection()
    verify(!bar.visible)
    compare(app.selectedMessageIds.length, 0)
  }

  function test_rows_show_check_circles_while_picking() {
    var app = createTemporaryObject(appComponent, testCase)
    verify(app.startForward(app.demoItems[0]))
    var circles = []
    function walk(item) {
      if (item.objectName === "messageSelectCircle" && item.visible) circles.push(item)
      for (var i = 0; i < item.children.length; i++) walk(item.children[i])
    }
    tryVerify(function() { circles = []; walk(app); return circles.length > 1 }, 2000)
    verify(circles.some(function(circle) { return String(circle.color) === String(app.accent) }),
      "the picked message is filled")
  }

  function test_the_dialog_takes_several_chats_and_a_note() {
    var app = createTemporaryObject(appComponent, testCase)
    app.demoChats = app.demoChats.concat([{ jid: "demo-extra", name: "Synthetic Extra", kind: "dm",
      account: "work", account_label: "work", avatar_path: "", preview: "", timestamp: 1, unread: 0 }])
    verify(app.startForward(app.demoItems[0]))
    verify(app.toggleMessageSelection(app.demoItems[3]))
    verify(app.openForwardDialog())
    var dialog = findChild(app, "forwardPicker")
    verify(dialog.opened)
    compare(findChild(app, "forwardTitle").text, "Forward 2 messages")
    compare(app.forwardItems.map(function(item) { return item.id }), ["demo-3", "demo-5"],
      "oldest first, the order they are sent in")
    var targets = app.forwardCandidates
    verify(targets.length >= 2)
    verify(app.toggleForwardTarget(targets[0]))
    verify(app.toggleForwardTarget(targets[1]))
    compare(app.forwardChosen.length, 2)
    compare(findChild(app, "forwardSend").ready, true)
    verify(app.sendForward())
    verify(!dialog.opened)
    verify(!app.selectingMessages, "sending ends the selection")
    verify(findChild(app, "toastAction").visible, "the toast offers to open the chat")
    verify(app.runToastAction())
    compare(app.demoSelectedJid, String(targets[0].jid), "the first chat it went to opens")
  }

  function test_copy_takes_the_words_in_order() {
    var app = createTemporaryObject(appComponent, testCase)
    verify(app.startForward(app.demoItems[0]))
    verify(app.toggleMessageSelection(app.demoItems[1]))
    verify(app.copySelection())
    verify(!app.selectingMessages)
  }

  function test_the_service_forwards_each_message_to_each_chat_then_the_note() {
    var service = createService()
    var finished = null
    service.forwardBatchFinished.connect(function(summary) { finished = summary })
    var process = findChild(service, "writeProcess")
    var items = [{ id: "M1", text: "one", timestamp: 1 }, { id: "M2", text: "two", timestamp: 2 }]
    var targets = [{ account: "work", jid: "a@s.whatsapp.net", name: "Synthetic A" },
                   { account: "work", jid: "b@s.whatsapp.net", name: "Synthetic B" }]
    verify(service.forwardMany(origin, items, targets, "  see these  ", "app"))
    verify(!service.forwardMany(origin, items, targets, "", "app"), "one batch at a time")
    var seen = []
    for (var step = 0; step < 6; step++) {
      var request = JSON.parse(process.payload)
      seen.push((request.to_jid || request.jid) + ":" + (request.id || request.text))
      process.running = true
      finish(service, 0, { ok: true, kind: request.to_jid ? "forward" : "send", message_id: "OUT" + step })
    }
    compare(seen, ["a@s.whatsapp.net:M1", "a@s.whatsapp.net:M2", "a@s.whatsapp.net:see these",
                   "b@s.whatsapp.net:M1", "b@s.whatsapp.net:M2", "b@s.whatsapp.net:see these"])
    verify(finished !== null, "the batch reports when it ends")
    compare(finished.failed, 0)
    compare(finished.targets.length, 2)
    compare(service.writeBatch, null)
  }

  function test_a_failed_forward_is_counted_and_the_rest_go_on() {
    var service = createService()
    var finished = null
    service.forwardBatchFinished.connect(function(summary) { finished = summary })
    var process = findChild(service, "writeProcess")
    var items = [{ id: "M1", text: "one", timestamp: 1 }]
    var targets = [{ account: "work", jid: "a@s.whatsapp.net", name: "Synthetic A" },
                   { account: "work", jid: "b@s.whatsapp.net", name: "Synthetic B" }]
    verify(service.forwardMany(origin, items, targets, "", "app"))
    process.running = true
    finish(service, 1, { ok: false, error: "WhatsApp refused that one." })
    compare(JSON.parse(process.payload).to_jid, "b@s.whatsapp.net", "the next chat still gets it")
    process.running = true
    finish(service, 0, { ok: true, kind: "forward", message_id: "OUT" })
    verify(finished !== null)
    compare(finished.failed, 1)
    compare(finished.errors, ["WhatsApp refused that one."])
  }

  function test_chats_of_another_account_are_left_out() {
    var service = createService()
    verify(!service.forwardMany(origin, [{ id: "M1" }],
      [{ account: "home", jid: "a@s.whatsapp.net" }], "", "app"))
  }

  // L224: the selection bar also deletes, one WhatsApp action at a time.
  function test_the_service_deletes_picked_messages_one_by_one() {
    var service = createService()
    var finished = null
    service.deleteBatchFinished.connect(function(summary) { finished = summary })
    var process = findChild(service, "writeProcess")
    var mine = [{ id: "M1", from_me: true, timestamp: 1 }, { id: "M2", from_me: true, timestamp: 2 }]
    verify(service.deleteMany(origin, mine, false, "app"))
    var first = JSON.parse(process.payload)
    compare(first.id, "M1")
    compare(first.for_me, false)
    process.running = true
    finish(service, 1, { ok: false, error: "Too old to delete for everyone." })
    compare(JSON.parse(process.payload).id, "M2", "the rest still go")
    process.running = true
    finish(service, 0, { ok: true, kind: "delete" })
    verify(finished !== null)
    compare(finished.total, 2)
    compare(finished.failed, 1)
    compare(finished.errors, ["Too old to delete for everyone."])
    compare(service.writeBatch, null)
  }

  function test_only_your_own_messages_go_for_everyone() {
    var service = createService()
    var mixed = [{ id: "M1", from_me: true }, { id: "T1", from_me: false }]
    verify(!service.deleteMany(origin, mixed, false, "app"), "not all yours: not for everyone")
    verify(service.deleteMany(origin, mixed, true, "app"), "for you is always possible")
    compare(JSON.parse(findChild(service, "writeProcess").payload).for_me, true)
  }

  function test_the_bar_deletes_the_picked_messages_after_asking() {
    var app = createTemporaryObject(appComponent, testCase)
    verify(app.startForward(app.demoItems[1]))       // yours
    verify(app.toggleMessageSelection(app.demoItems[0])) // theirs
    verify(app.requestDeleteSelection())
    var dialog = findChild(app, "batchDeleteConfirm")
    verify(dialog.opened)
    compare(findChild(dialog.contentItem, "batchDeleteTitle").text, "Delete 2 messages?")
    verify(!findChild(dialog.contentItem, "batchDelete-all").visible, "someone else's message: for you only")
    verify(app.deleteSelection(true))
    verify(!dialog.opened)
    verify(!app.selectingMessages)
    verify(app.demoItems.every(function(item) { return item.id !== "demo-5" && item.id !== "demo-1" }))
    // All yours: for everyone leaves the placeholder.
    verify(app.startForward(app.demoItems[0]))
    compare(app.demoItems[0].from_me, true)
    verify(app.requestDeleteSelection())
    verify(findChild(dialog.contentItem, "batchDelete-all").visible)
    verify(app.deleteSelection(false))
    verify(app.demoItems[0].revoked)
  }

  // L225: a number with no chat yet, checked once, joins as a chip.
  function test_a_typed_number_is_checked_then_added() {
    var app = createTemporaryObject(appComponent, testCase)
    verify(app.startForward(app.demoItems[0]))
    verify(app.openForwardDialog())
    var dialog = findChild(app, "forwardPicker")
    var search = findChild(dialog.contentItem, "forwardSearch")
    search.text = "+1 555 000 7777"
    compare(app.forwardDigits, "15550007777")
    var row = findChild(dialog.contentItem, "forwardNumberRow")
    verify(row.visible)
    compare(app.forwardNumberState, "registered", "demo answers at once")
    verify(findChild(dialog.contentItem, "forwardNumberLabel").text.indexOf("Add +15550007777") === 0)
    verify(app.useForwardNumber())
    compare(app.forwardChosen.length, 1)
    compare(app.forwardChosen[0].phone, "15550007777")
    compare(search.text, "", "the search clears for the next one")
    search.text = "12"
    compare(app.forwardDigits, "", "too short to be a number")
    verify(!row.visible)
    search.text = "+1 555 000 7777"
    verify(app.useForwardNumber(), "a second press takes it out again")
    compare(app.forwardChosen.length, 0)
  }

  function test_the_service_forwards_to_a_new_number_and_starts_its_chat_with_the_note() {
    var service = createService()
    var process = findChild(service, "writeProcess")
    var target = { account: "work", jid: "", phone: "15550007777", name: "+15550007777" }
    verify(service.forwardMany(origin, [{ id: "M1", timestamp: 1 }], [target], "hello", "app"))
    var forward = JSON.parse(process.payload)
    compare(forward.to_phone, "15550007777")
    compare(forward.to_jid, "")
    process.running = true
    finish(service, 0, { ok: true, kind: "forward", message_id: "OUT1" })
    compare(service.activeWriteKind, "send-new", "the note is the chat's first message")
    var note = JSON.parse(process.payload)
    compare(note.target.phone, "+15550007777")
    compare(note.text, "hello")
    var finished = null
    service.forwardBatchFinished.connect(function(summary) { finished = summary })
    process.running = true
    finish(service, 0, { ok: true, kind: "send-new", chat_jid: "15550007777@s.whatsapp.net" })
    verify(finished !== null)
    compare(finished.failed, 0)
    compare(finished.targets[0].jid, "15550007777@s.whatsapp.net")
  }

  // L223: star from the selection bar, one WhatsApp action at a time.
  function test_the_service_stars_picked_messages_one_by_one() {
    var service = createService()
    var finished = null
    service.starBatchFinished.connect(function(summary) { finished = summary })
    var process = findChild(service, "writeProcess")
    verify(service.starMany(origin, [{ id: "M1" }, { id: "M2" }], true, "app"))
    compare(service.activeWriteKind, "star")
    compare(JSON.parse(process.payload).id, "M1")
    compare(JSON.parse(process.payload).starred, true)
    process.running = true
    finish(service, 0, { ok: true, kind: "star", starred: true })
    compare(JSON.parse(process.payload).id, "M2")
    process.running = true
    finish(service, 0, { ok: true, kind: "star", starred: true })
    verify(finished !== null)
    compare(finished.failed, 0)
    compare(finished.starred, true)
  }

  function test_a_wacli_that_cannot_star_hides_the_option() {
    var service = createService()
    verify(service.starSupported)
    verify(service.starMany(origin, [{ id: "M1" }, { id: "M2" }], true, "app"))
    var process = findChild(service, "writeProcess")
    process.running = true
    finish(service, 1, { ok: false, error: "This wacli build cannot star messages; install one that can." })
    verify(!service.starSupported, "no more offers to star")
    compare(service.writeBatch, null, "the rest of the batch is dropped")
    verify(!service.starMessage(origin, { id: "M3" }, true, "app"))
  }

  function test_the_bar_stars_and_unstars_the_picked_messages() {
    var app = createTemporaryObject(appComponent, testCase)
    var plain = app.demoItems.filter(function(item) { return item.starred !== true && !item.album_items })[0]
    verify(app.startForward(plain))
    verify(!app.selectionAllStarred)
    verify(app.starSelection(true))
    verify(app.demoItems.filter(function(item) { return item.id === plain.id })[0].starred)
    verify(app.startForward(app.demoItems.filter(function(item) { return item.id === plain.id })[0]))
    verify(app.selectionAllStarred, "all starred: the bar offers Unstar")
    verify(app.starSelection(false))
    verify(!app.demoItems.filter(function(item) { return item.id === plain.id })[0].starred)
  }

  function test_a_star_shows_at_once_and_goes_back_if_refused() {
    var service = createService()
    service.messages = [{ id: "M1", text: "one", timestamp: 1, starred: false }]
    var process = findChild(service, "writeProcess")
    verify(service.starMessage(origin, service.messages[0], true, "app"))
    verify(service.selectedMessages[0].starred, "shown before WhatsApp answers")
    process.running = true
    finish(service, 1, { ok: false, error: "WhatsApp did not answer." })
    verify(!service.selectedMessages[0].starred, "refused: back as it was")
    verify(service.starMessage(origin, service.messages[0], true, "app"))
    process.running = true
    finish(service, 0, { ok: true, kind: "star", starred: true })
    service.messages = [{ id: "M1", text: "one", timestamp: 1, starred: true }]
    compare(Object.keys(service.starOverrides).length, 0, "the mirror has it now")
    verify(service.selectedMessages[0].starred)
  }
}
