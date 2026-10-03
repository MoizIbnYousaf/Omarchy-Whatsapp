import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/AccountModel.js" as AccountModel

// The window chrome follows Omarchy's own apps (Omawrite, Omacalc): no title
// bar, controls as small icon buttons with tooltips, status only when it says
// something the user can act on.
TestCase {
  id: testCase
  name: "AppChrome"
  width: 1000
  height: 700
  visible: true
  when: windowShown

  readonly property var workChat: ({
    account: "work", jid: "shared@example", name: "Synthetic work",
    kind: "dm", preview: "", unread: 0
  })
  readonly property var otherChat: ({
    account: "work", jid: "other@example", name: "Synthetic other",
    kind: "dm", preview: "", unread: 0
  })

  Component {
    id: serviceComponent
    Item {
      readonly property alias playback: playbackCoordinator
      property bool appOpen: false
      property bool writing: false
      property bool controlWriting: false
      property bool settingsWriting: false
      property bool statusReady: true
      property bool railReady: true
      property bool offlineMode: false
      property bool syncActive: true
      property bool notificationsEnabled: true
      property bool notificationsPreview: false
      property bool notifyAvailable: true
      property bool sendReadReceipts: false
      property bool showUnreadCount: true
      property bool multiAccount: true
      property int dropdownRows: 7
      property int composerMaxLines: 6
      property string timeFormat: "auto"
      property string statusAccount: "work"
      property string selectedChatAccount: "work"
      property string selectedChatJid: "shared@example"
      property string selectedChatName: "Synthetic work"
      property string selectedChatKind: "dm"
      property string activeWriteAccount: ""
      property string activeWriteChatJid: ""
      property string activeWriteKind: ""
      property string voiceDraftAccount: ""
      property string voiceDraftJid: ""
      property string voiceState: "idle"
      property int voiceDurationMs: 0
      property int voicePlaybackPosition: 0
      property bool voicePlaying: false
      property bool loadingMembers: false
      property bool loadingMessages: false
      property string mediaDownloadId: ""
      property string errorText: ""
      property var chats: []
      // Presence as a wacli without presence support reports it: nothing.
      property int presenceNow: 0
      function presenceSnapshotFor() { return null }
      function setPresenceFocus() {}
      property var accounts: []
      property var messages: []
      property var members: []
      property var accountOperations: ({
        linkBusy: false, avatarBusy: false, statusMessage: "", linkedName: "", mainLinked: false,
        linkMainAccount: function(name) { this.linkedName = name; this.mainLinked = true },
        linkAccount: function(name) { this.linkedName = name; this.mainLinked = false }
      })
      property var lastPreference: null
      property var lastDelete: null
      property var lastForward: null
      property var lastPoll: null
      property var lastChatAction: null
      property var discarded: []

      Oma.PlaybackCoordinator { id: playbackCoordinator }

      signal textPasted(string text, var chatRef, string owner)
      signal attachmentPasted(string path, var chatRef, string owner)
      signal writeCompleted(string kind, var chatRef, var request, string owner)
      signal writeFailed(string message, var chatRef, var details, string owner)
      // Number checks and first messages, as the new-chat flow uses them.
      property var numberChecks: ({})
      property var checkedNumbers: []
      property var startedChats: []
      property string lastStartedChatJid: ""
      function checkNumber(phone) {
        var digits = String(phone || "").replace(/[^0-9]/g, "")
        checkedNumbers = checkedNumbers.concat([digits])
        var next = Object.assign({}, numberChecks)
        next[digits] = { phone: digits, loading: true, registered: false, jid: "", error: "" }
        numberChecks = next
        return true
      }
      function numberCheckFor(digits) { return numberChecks[String(digits || "")] || null }
      property bool closed: false
      property int quits: 0
      property int launches: 0
      function quitApp() { quits += 1; closed = true; return true }
      function launchApp() { launches += 1; closed = false; return true }
      function startNewChat(jid, text, owner) {
        startedChats = startedChats.concat([{ jid: jid, text: text, owner: owner }])
        return true
      }
      signal controlCompleted(string kind)
      signal controlFailed(string message)
      signal settingsCompleted()
      signal settingsFailed(string message)

      function selectChat(chat) {
        selectedChatAccount = String(chat.account || "")
        selectedChatJid = String(chat.jid || "")
        selectedChatName = String(chat.name || "")
        selectedChatKind = String(chat.kind || "")
        statusAccount = selectedChatAccount
      }
      function deleteMessage(ref, item, forMe, owner) {
        lastDelete = { ref: ref, item: item, forMe: forMe, owner: owner }
        return true
      }
      function forwardMessage(ref, item, targetJid, owner) {
        lastForward = { ref: ref, item: item, targetJid: targetJid, owner: owner }
        return true
      }
      function sendPoll(ref, question, options, selectable, owner) {
        lastPoll = {
          ref: ref, question: question, options: options,
          selectable: selectable, owner: owner
        }
        return true
      }
      function discardStages(paths) { discarded = paths.slice() }
      function discardStage(path) { discarded = [path] }
      function refresh() {}
      function refreshChats() {}
      function refreshMessages() {}
      function dismissNotifications(jid, account) {}
      function stopVoiceRecording() {}
      function stopVoiceForSurfaceClose() {}
      function toggleVoice() { return false }
      function toggleVoicePlayback() {}
      function discardVoice() {}
      function sendVoiceDraft() { return false }
      property int pastes: 0
      property bool pasteAccepts: true
      signal pasteFailed(string message, var chatRef, string owner)
      function pasteClipboard(ref, owner) { pastes += 1; return pasteAccepts }
      function sendFilesReply() { return false }
      function sendSticker() { return false }
      property var downloads: []
      function downloadPending(ref, owner) { downloads = downloads.concat([ref.jid]); return true }
      property var pollVotes: []
      function votePoll(ref, item, options, owner) {
        pollVotes = pollVotes.concat([{ id: item.id, options: options, owner: owner }])
        return true
      }
      property var sentTexts: []
      property bool acceptSends: false
      function sendText(ref, text) { sentTexts = sentTexts.concat([text]); return acceptSends }
      function editMessage() { return false }
      function search() {}
      function closeApp() {}
      function selectItem() {}
      function chatAction(ref, action, owner) {
        lastChatAction = { ref: ref, action: action, owner: owner }
        return true
      }
      function downloadMedia() { return false }
      function reactTo() { return false }
      function selectOption() { return false }
      property var lastNotifications: null
      property var lastChatRead: null
      property bool showAvatars: true
      property bool appConversationVisible: false
      property string railDensity: "comfortable"
      property string syncPauseReason: ""
      property bool loadingOlder: false
      property bool hasOlderMessages: true
      property int olderRequests: 0
      function loadOlderMessages() { olderRequests += 1; return true }
      property bool chatDetailsWanted: false
      property var browserItems: []
      property bool browserLoading: false
      property var browsed: []
      function browseMedia(kind) { browsed = browsed.concat([kind]); return true }
      property bool chatDetailsLoading: false
      property var chatDetails: ({})
      function setChatRead(ref, read, owner) {
        lastChatRead = { ref: ref, read: read, owner: owner }
        return true
      }
      function setNotifications(enabled, preview) {
        lastNotifications = { enabled: enabled, preview: preview }
        return true
      }
      property var lastOnline: null
      function setOnline(online) { lastOnline = online; return true }
      function setPreference(key, value) {
        lastPreference = { key: key, value: value }
        return true
      }
      property bool zenityAvailable: true
      property int zenityInstalls: 0
      function installZenity() { zenityInstalls += 1; return true }
    }
  }

  Component {
    id: appComponent
    Oma.App { width: 1000; height: 700 }
  }

  function createHarness(overrides) {
    var service = createTemporaryObject(serviceComponent, testCase)
    verify(service !== null)
    service.chats = [workChat, otherChat]
    for (var key in (overrides || {})) service[key] = overrides[key]
    service.selectChat(workChat)
    var app = createTemporaryObject(appComponent, testCase, { service: service })
    verify(app !== null)
    app.opened = true
    return { app: app, service: service }
  }

  function chatPreviewRow(app, index) {
    var list = null
    var queue = [app]
    while (queue.length > 0 && list === null) {
      var item = queue.shift()
      if (item.objectName === "" && item.model !== undefined && item.itemAtIndex !== undefined
          && item.count >= 2 && item.itemAtIndex(0) && findChild(item.itemAtIndex(0), "chatPreview")) list = item
      for (var i = 0; i < (item.children || []).length; i++) queue.push(item.children[i])
      if (item.contentItem) queue.push(item.contentItem)
    }
    verify(list !== null, "chat list")
    tryVerify(function() { return list.itemAtIndex(index) !== null })
    return list.itemAtIndex(index)
  }

  function test_the_chat_list_shows_the_tick_of_your_last_message() {
    // As on the phone: your last message shows its tick instead of "You ·".
    var read = Object.assign({}, workChat, { last_from_me: true, last_status: "read", preview: "see you" })
    var unknown = Object.assign({}, otherChat, { last_from_me: true, last_status: "", preview: "older" })
    var h = createHarness({ chats: [read, unknown] })
    var first = chatPreviewRow(h.app, 0)
    var ticks = findChild(first, "chatPreviewTicks")
    verify(ticks.visible)
    compare(ticks.text, "󰄭")
    compare(String(ticks.color), String(h.app.accent), "read is in the accent color")
    verify(findChild(first, "chatPreview").text.indexOf("You · ") < 0)
    var second = chatPreviewRow(h.app, 1)
    verify(!findChild(second, "chatPreviewTicks").visible, "no record, no tick")
    verify(findChild(second, "chatPreview").text.indexOf("You · ") >= 0, "the words stay when no tick is known")
  }

  function test_there_is_no_title_bar_above_the_chat_list() {
    var app = createHarness().app
    var settings = findChild(app, "railSettingsButton")
    verify(settings !== null)
    verify(settings.mapToItem(app, 0, 0).y < 40,
      "the rail must start at the top of the window")
  }

  function test_rail_controls_are_icon_buttons_with_tooltips() {
    var app = createHarness().app
    var settings = findChild(app, "railSettingsButton")
    var collapse = findChild(app, "railCollapseButton")
    compare(settings.tooltipText, "Settings")
    compare(collapse.tooltipText, "Hide chat list · Ctrl+B")
    verify(collapse.visible)
    settings.clicked()
    verify(app.settingsOpen)
  }

  function test_the_oldest_visible_message_asks_for_the_page_before_it() {
    var h = createHarness({ messages: [
      { id: "m2", text: "second", sender: "Synthetic", timestamp: 1787540100, from_me: false, media_type: "", reactions: [] },
      { id: "m1", text: "first", sender: "Synthetic", timestamp: 1787540000, from_me: false, media_type: "", reactions: [] }
    ] })
    tryVerify(function() { return h.service.olderRequests > 0 }, 2000,
      "a short chat shows its oldest message at once, so the next page is requested")
    h.service.hasOlderMessages = false
    var hint = findChild(h.app, "olderMessagesHint")
    verify(hint !== null)
    compare(hint.text, "Start of this computer's copy of the chat")
  }

  function test_ctrl_k_jumps_to_a_chat_by_name() {
    var h = createHarness()
    var switcher = findChild(h.app, "quickSwitcher")
    verify(switcher !== null)
    h.app.forceActiveFocus()
    keyClick(Qt.Key_K, Qt.ControlModifier)
    tryCompare(switcher, "opened", true)
    switcher.query = "other"
    compare(switcher.results.length, 1)
    verify(switcher.accept())
    compare(h.service.selectedChatJid, "other@example")
    tryCompare(switcher, "opened", false)
  }

  function test_the_switcher_moves_with_the_arrows_and_finds_archived_chats() {
    var h = createHarness()
    h.service.chats = [workChat, otherChat,
      { account: "work", jid: "old@example", name: "Synthetic archived", kind: "dm", unread: 0, archived: true }]
    var switcher = findChild(h.app, "quickSwitcher")
    h.app.openQuickSwitcher()
    tryCompare(switcher, "opened", true)
    compare(switcher.results.length, 2, "an empty query lists the chats without archived ones")
    switcher.move(1)
    compare(switcher.cursor, 1)
    switcher.move(5)
    compare(switcher.cursor, 1, "the cursor stays inside the list")
    switcher.query = "archived"
    compare(switcher.results.map(function(c) { return c.jid }), ["old@example"])
    compare(switcher.cursor, 0)
    switcher.close()
  }

  function test_rail_views_filter_the_chat_list() {
    var h = createHarness()
    h.service.chats = [
      { account: "work", jid: "shared@example", name: "Synthetic work", kind: "dm", unread: 0 },
      { account: "work", jid: "other@example", name: "Synthetic other", kind: "group", unread: 2 },
      { account: "work", jid: "old@example", name: "Synthetic archived", kind: "dm", unread: 0, archived: true }
    ]
    compare(h.app.visibleChats.length, 2, "archived chats live in their own view")
    verify(findChild(h.app, "railView-archived") !== null)
    var unread = findChild(h.app, "railView-unread")
    tryVerify(function() { return unread.x > 0 && unread.width > 0 }, 2000, "the chips have laid out")
    mouseClick(unread, unread.width / 2, unread.height / 2)
    compare(h.app.chatView, "unread")
    compare(h.app.visibleChats.map(function(c) { return c.jid }), ["other@example"])
    mouseClick(unread, unread.width / 2, unread.height / 2)
    compare(h.app.chatView, "all", "clicking the active view goes back to all")
    h.app.chatView = "archived"
    compare(h.app.visibleChats.map(function(c) { return c.jid }), ["old@example"])
    h.app.chatView = "groups"
    h.service.chats = [workChat]
    verify(findChild(h.app, "railViewEmpty").visible)
  }

  function test_dragging_the_rail_edge_resizes_and_saves_it() {
    var h = createHarness()
    var handle = findChild(h.app, "railResizeHandle")
    verify(handle !== null)
    verify(handle.visible)
    var before = h.app.railWidth
    mousePress(handle, handle.width / 2, 100)
    mouseMove(handle, handle.width / 2 + 60, 100)
    mouseRelease(handle, handle.width / 2 + 60, 100)
    verify(Math.abs(h.app.railWidth - (before + 60)) < 8, "the list follows the pointer")
    compare(h.service.lastPreference.key, "rail_width")
    verify(Math.abs(h.service.lastPreference.value - h.app.railWidth) < 1)
    mousePress(handle, handle.width / 2, 100)
    mouseMove(handle, handle.width / 2 + 2000, 100)
    mouseRelease(handle, handle.width / 2 + 2000, 100)
    compare(h.app.railWidth, h.app.railMaxWidth, "the conversation always keeps its room")
    h.app.resetRailWidth()
    compare(h.service.lastPreference.value, 0)
    compare(h.app.railWidth, h.app.railAutoWidth)
  }

  function test_view_chips_scroll_instead_of_being_cut() {
    var h = createHarness()
    h.service.chats = [workChat,
      { account: "work", jid: "old@example", name: "Synthetic archived", kind: "dm", unread: 3, archived: true }]
    var views = findChild(h.app, "railViews")
    views.width = 120
    tryVerify(function() { return views.contentWidth > views.width }, 2000)
    verify(views.interactive, "chips wider than the rail scroll sideways")
    var archived = findChild(h.app, "railView-archived")
    verify(archived !== null, "the last chip exists even when it does not fit")
    views.contentX = views.contentWidth - views.width
    verify(archived.mapToItem(views, 0, 0).x + archived.width <= views.width + 1,
      "scrolled to the end, the last chip is fully in view")
  }

  function test_the_header_opens_chat_details_and_escape_closes_them() {
    var h = createHarness()
    h.app.selectChat(workChat)
    var title = findChild(h.app, "conversationTitle")
    verify(title !== null)
    compare(h.service.appConversationVisible, true)
    mouseClick(title, 5, title.height / 2)
    verify(h.app.chatDetailsOpen)
    verify(h.service.chatDetailsWanted, "the service loads the details while the panel is open")
    var panel = findChild(h.app, "chatDetailsPanel")
    verify(panel.visible)
    verify(!h.app.chatDetailsBeside, "a 1000 px window has no room beside the conversation")
    compare(h.service.appConversationVisible, false,
      "a panel covering the conversation does not count as reading it")
    h.app.goBack()
    verify(!h.app.chatDetailsOpen)
    verify(!h.service.chatDetailsWanted)
    compare(h.service.appConversationVisible, true)
  }

  function test_chat_details_open_a_known_person_or_hand_off_to_new_chat() {
    var h = createHarness()
    h.app.chatDetailsOpen = true
    verify(h.app.openFromChatDetails("other@example", "Synthetic other", ""))
    compare(h.service.selectedChatJid, "other@example")
    h.app.chatDetailsOpen = true
    verify(h.app.openFromChatDetails("15550009999@s.whatsapp.net", "Nobody yet", "15550009999"))
    verify(!h.app.chatDetailsOpen)
    tryCompare(findChild(h.app, "newChatDialog"), "opened", true)
  }

  function firstMessageMenu(app) {
    var row = findChild(app, "messageList").itemAtIndex(0)
    return row ? findChild(row, "messageActionMenu") : null
  }

  function firstBubbleCenter(app) {
    var bubble = findChild(findChild(app, "messageList").itemAtIndex(0), "messageBubbleSurface")
    return bubble.mapToItem(app, bubble.width / 2, bubble.height / 2)
  }

  function anyMessageMenuOpen(app) {
    var list = findChild(app, "messageList")
    for (var i = 0; i < list.count; i++) {
      var row = list.itemAtIndex(i)
      var menu = row ? findChild(row, "messageActionMenu") : null
      if (menu && menu.opened) return true
    }
    return false
  }

  function test_panels_over_the_conversation_swallow_the_pointer() {
    // The owner right-clicked a group participant and got a message menu:
    // the details panel stopped mouse areas, but tap handlers on the bubble
    // under it still saw the click.
    var h = createHarness({ messages: [
      { id: "m1", text: "under the panel", sender: "Synthetic", timestamp: 1787540100,
        from_me: false, media_type: "", reactions: [] }] })
    var list = findChild(h.app, "messageList")
    tryVerify(function() { return list.count > 0 && list.itemAtIndex(0) !== null }, 3000, "message row")
    var bubble = findChild(list.itemAtIndex(0), "messageBubbleSurface")
    tryVerify(function() { return bubble.width > 0 && bubble.height > 0 }, 3000, "bubble size")
    var point = bubble.mapToItem(h.app, bubble.width / 2, bubble.height / 2)
    mouseClick(h.app, point.x, point.y, Qt.RightButton)
    tryVerify(function() { return anyMessageMenuOpen(h.app) }, 1000, "control: the bubble answers a right click")
    firstMessageMenu(h.app).close()
    tryVerify(function() { return !anyMessageMenuOpen(h.app) })

    h.app.chatDetailsOpen = true
    var panel = findChild(h.app, "chatDetailsPanel")
    tryVerify(function() { return panel.visible && panel.width > 0 })
    wait(100)
    point = firstBubbleCenter(h.app)
    verify(panel.contains(panel.mapFromItem(h.app, point.x, point.y)), "the bubble sits under the panel")
    mouseClick(h.app, point.x, point.y, Qt.RightButton)
    wait(100)
    verify(!anyMessageMenuOpen(h.app), "a right click on the panel never reaches the bubble under it")
    var avatar = findChild(h.app, "conversationAvatar")
    var head = avatar.mapToItem(h.app, avatar.width / 2, avatar.height / 2)
    verify(panel.contains(panel.mapFromItem(h.app, head.x, head.y)))
    mouseClick(h.app, head.x, head.y)
    wait(100)
    verify(h.app.chatDetailsOpen, "a click on the panel never reaches the header under it")

    h.app.chatDetailsOpen = false
    h.app.openMediaBrowser("media")
    var browser = findChild(h.app, "mediaBrowser")
    tryVerify(function() { return browser.visible && browser.width > 0 })
    wait(100)
    point = firstBubbleCenter(h.app)
    mouseClick(h.app, point.x, point.y, Qt.RightButton)
    wait(100)
    verify(!anyMessageMenuOpen(h.app), "the media view covers the bubble the same way")

    h.app.mediaBrowserOpen = false
    tryVerify(function() { return !browser.visible })
    wait(100)
    point = firstBubbleCenter(h.app)
    mouseClick(h.app, point.x, point.y, Qt.RightButton)
    tryVerify(function() { return anyMessageMenuOpen(h.app) }, 1000, "the bubble works again once the panel closes")
    firstMessageMenu(h.app).close()
  }

  function test_a_right_click_on_a_participant_opens_only_the_participant_menu() {
    // The owner's report, exactly: right-clicking a participant opened the
    // participant menu and the menu of the message under the panel.
    var messages = []
    for (var i = 0; i < 14; i++)
      messages.push({ id: "m" + i, text: "message under the panel " + i, sender: "Synthetic",
        timestamp: 1787540100 - i * 60, from_me: i % 2 === 0, media_type: "", reactions: [] })
    var people = []
    for (var p = 0; p < 9; p++)
      people.push({ jid: (p + 1) + "@s.whatsapp.net", name: "Synthetic person " + p,
        phone: "1555000000" + p, role: p === 0 ? "superadmin" : "member", me: p === 1 })
    var h = createHarness({ messages: messages, selectedChatKind: "group", chatDetails: {
      ok: true, chat: { kind: "group", name: "Synthetic group" },
      counts: { total: 14, media: 0, documents: 0, links: 0 },
      group: { participant_count: 9, my_role: "admin" }, participants: people } })
    var list = findChild(h.app, "messageList")
    tryVerify(function() { return list.count > 0 && list.itemAtIndex(0) !== null }, 3000, "message rows")
    h.app.chatDetailsOpen = true
    var panel = findChild(h.app, "chatDetailsPanel")
    tryVerify(function() { return panel.visible && panel.width > 0 })
    var repeater = findChild(panel, "chatDetailsPeople")
    tryVerify(function() { return repeater.count === 9 }, 2000, "participants")
    var clicked = 0
    for (var r = 0; r < repeater.count; r++) {
      var row = repeater.itemAt(r)
      var center = row.mapToItem(h.app, row.width / 3, row.height / 2)
      if (center.y < 0 || center.y > h.app.height - 10 || r === 1) continue
      mouseClick(h.app, center.x, center.y, Qt.RightButton)
      wait(80)
      verify(!anyMessageMenuOpen(h.app), "row " + r + ": no message menu under the participant")
      var participantMenu = findChild(panel, "participantMenu")
      verify(participantMenu.opened, "row " + r + ": the participant menu opens")
      participantMenu.close()
      tryVerify(function() { return !participantMenu.visible })
      clicked++
    }
    verify(clicked >= 3, "enough rows were on screen to test")
  }

  function test_a_reply_while_another_action_runs_goes_out_at_once() {
    // The owner's reports: after opening a chat from a notification its read
    // mark was still running and nothing went out; and typing, Enter, typing
    // again had to wait for each send. Text now goes to the send queue at
    // once, so the composer is free for the next message.
    var h = createHarness()
    h.service.acceptSends = true
    var composer = findChild(h.app, "composerInput")
    composer.text = "on my way"
    h.service.writing = true
    h.app.sendDraft()
    compare(h.service.sentTexts, ["on my way"], "handed over while the read mark runs")
    compare(composer.text, "", "the composer is free at once")
    verify(!h.app.sendQueued)
    var button = findChild(h.app, "composerSendButton")
    compare(button.opacity, 1, "the button never looks disabled for text")
    composer.text = "be there in 5"
    h.app.sendDraft()
    compare(h.service.sentTexts, ["on my way", "be there in 5"], "in the order typed")
    compare(h.app.queuedSendKey, "", "text never waits in the window")
  }

  function test_paste_runs_while_a_send_is_in_flight() {
    var h = createHarness()
    h.service.writing = true
    h.app.pasteDraft()
    compare(h.service.pastes, 1, "Ctrl+V is never swallowed by a running send")
  }

  function test_text_pastes_by_itself_when_the_helper_cannot() {
    var h = createHarness()
    var source = createTemporaryObject(copySourceComponent, testCase)
    source.selectAll()
    source.copy()
    h.service.pasteAccepts = false
    var composer = findChild(h.app, "composerInput")
    composer.text = ""
    h.app.pasteDraft()
    compare(composer.text, "clipboard words")
    composer.text = ""
    h.service.pasteAccepts = true
    h.app.pasteDraft()
    h.app.syncComposerToSelectedChat()
    compare(h.app.composerChatKey, AccountModel.refOf(workChat).key)
    h.service.pasteFailed("wl-paste is missing", AccountModel.refOf(workChat), "app")
    compare(composer.text, "clipboard words", "a failed helper paste falls back to plain text")
  }

  Component { id: copySourceComponent; TextEdit { text: "clipboard words" } }

  function findBubble(item) {
    if (!item) return null
    if (item.votePollOption !== undefined) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = findBubble(item.children[i])
      if (found) return found
    }
    return null
  }

  function test_tapping_a_poll_option_votes_for_the_open_chat() {
    var h = createHarness({ messages: [{ id: "poll1", text: "", sender: "You", timestamp: 1790280000,
      from_me: true, media_type: "", reactions: [], poll: { question: "Which day?", selectable: 1,
      voters: 0, options: [{ text: "Monday", votes: 0, voters: [], mine: false },
                           { text: "Tuesday", votes: 0, voters: [], mine: false }] } }] })
    var list = findChild(h.app, "messageList")
    tryVerify(function() { return list.count > 0 && list.itemAtIndex(0) !== null })
    var bubble = findBubble(list.itemAtIndex(0))
    verify(bubble.votePollOption("Monday"))
    compare(h.service.pollVotes.length, 1)
    compare(h.service.pollVotes[0].id, "poll1")
    compare(h.service.pollVotes[0].options, ["Monday"])
    compare(h.service.pollVotes[0].owner, "app")
  }

  function test_the_composer_formats_like_whatsapp() {
    // The owner asked for WhatsApp's formatting options in the composer.
    var h = createHarness()
    var composer = findChild(h.app, "composerInput")
    compare(findChild(h.app, "composerFormatButton"), null,
      "no button: formatting comes with a selection or a right-click (owner's request)")
    composer.text = "see you soon"
    composer.select(4, 7)
    verify(h.app.applyFormat("bold"))
    compare(composer.text, "see *you* soon")
    compare(composer.selectedText, "you")
    verify(h.app.applyFormat("bold"), "the same kind again removes it")
    compare(composer.text, "see you soon")
    composer.text = "milk\neggs"
    composer.select(0, composer.text.length)
    verify(h.app.applyFormat("bullet"))
    compare(composer.text, "- milk\n- eggs")
    // TextEdit records the remove and the insert as two undo steps.
    composer.undo()
    composer.undo()
    compare(composer.text, "milk\neggs", "Ctrl+Z undoes a format")
  }

  function test_selecting_text_shows_the_format_bar_and_right_click_the_menu() {
    var h = createHarness()
    var composer = findChild(h.app, "composerInput")
    var bar = findChild(h.app, "formatBar")
    verify(bar !== null)
    composer.forceActiveFocus()
    composer.text = "see you soon"
    verify(!bar.opened, "no selection, no bar")
    composer.select(4, 7)
    tryVerify(function() { return bar.opened }, 1000, "the bar appears over the selection")
    bar.chosen("italic")
    compare(composer.text, "see _you_ soon")
    compare(composer.selectedText, "you", "the selection stays for another format")
    composer.deselect()
    tryVerify(function() { return !bar.opened }, 1000, "and goes with the selection")
    var menu = findChild(h.app, "formatMenu")
    h.app.openComposerMenu(5, 5)
    verify(menu.opened)
    verify(menu.editActions)
    verify(findChild(menu.contentItem, "formatEdit-paste") !== null)
    verify(findChild(menu.contentItem, "formatOption-bold") !== null)
    h.app.composerMenuAction("select-all")
    compare(composer.selectedText, "see _you_ soon")
    verify(h.app.composerMenuAction("strike"))
    compare(composer.text, "~see _you_ soon~")
    menu.close()
  }

  function test_ctrl_b_bolds_a_selection_and_otherwise_hides_the_list() {
    var h = createHarness()
    var composer = findChild(h.app, "composerInput")
    h.app.focusComposer()
    tryVerify(function() { return composer.activeFocus })
    composer.text = "bold me"
    composer.select(0, 4)
    keyClick(Qt.Key_B, Qt.ControlModifier)
    compare(composer.text, "*bold* me")
    verify(!h.app.sidebarCollapsed, "with a selection Ctrl+B only formats")
    composer.deselect()
    keyClick(Qt.Key_B, Qt.ControlModifier)
    verify(h.app.sidebarCollapsed, "without one it still hides the chat list")
    h.app.focusComposer()
    tryVerify(function() { return composer.activeFocus })
    composer.select(0, 6)
    keyClick(Qt.Key_I, Qt.ControlModifier)
    compare(composer.text, "_*bold*_ me")
  }

  function test_message_on_a_shared_contact_opens_its_chat_or_a_new_one() {
    var h = createHarness()
    verify(h.app.openContactChat({ name: "Synthetic other", digits: "15550001111",
                                   jid: "other@example", has_chat: true }))
    compare(h.service.selectedChatJid, "other@example")
    // Someone with no chat yet gets a draft chat over this one (L220), not
    // the new-chat dialog; the number is checked once, and Esc goes back.
    verify(h.app.openContactChat({ name: "Nobody Synthetic", digits: "15550009999", jid: "", has_chat: false },
      { id: "card-message", sender: "Sam Rivera", from_me: false }))
    var panel = findChild(h.app, "contactDraftPanel")
    verify(panel.visible)
    compare(h.app.contactDraft.digits, "15550009999")
    compare(h.app.contactDraft.sharedBy, "Sam")
    verify(findChild(h.app, "contactDraftExplainer").text.indexOf("Sam shared this contact") === 0)
    verify(!findChild(h.app, "newChatDialog").opened)
    h.app.closeContactDraft()
    verify(!panel.visible)
  }

  function test_new_chat_hands_new_group_to_its_dialog() {
    var h = createHarness()
    findChild(h.app, "newChatDialog").groupRequested("create")
    var dialog = findChild(h.app, "groupDialog")
    tryCompare(dialog, "opened", true)
    compare(dialog.mode, "create")
  }

  function test_details_export_asks_where_and_missing_downloads_start() {
    var h = createHarness()
    verify(h.app.runChatDetailsAction("export"))
    var picker = findChild(h.app, "exportPickerProcess")
    verify(picker.command.indexOf("--save") >= 0)
    verify(String(picker.command[picker.command.length - 1]).indexOf("/Documents/WhatsApp - ") > 0)
    verify(String(picker.command[picker.command.length - 1]).slice(-4) === ".txt")
    verify(h.app.runChatDetailsAction("download-missing"))
    compare(h.service.downloads, ["shared@example"])
  }

  function test_closing_a_covering_panel_gives_the_draft_its_focus_back() {
    var h = createHarness()
    h.app.focusComposer()
    var composer = findChild(h.app, "composerInput")
    tryVerify(function() { return composer.activeFocus })
    h.app.chatDetailsOpen = true
    tryVerify(function() { return h.app.conversationCovered })
    verify(!findChild(h.app, "messageList").enabled, "nothing under the panel answers the pointer")
    h.app.chatDetailsOpen = false
    tryVerify(function() { return composer.activeFocus }, 1000, "the draft is ready to type again")
    verify(findChild(h.app, "messageList").enabled)
  }

  function test_media_links_and_docs_open_in_their_own_view_and_esc_goes_back() {
    // The owner could filter the conversation to media and then find no way
    // back to it; the conversation is no longer filtered at all.
    var h = createHarness()
    h.service.browsed = []
    var button = findChild(h.app, "mediaBrowserButton")
    verify(button !== null)
    button.clicked()
    verify(h.app.mediaBrowserOpen)
    compare(h.service.browsed[0], "media")
    var browser = findChild(h.app, "mediaBrowser")
    verify(browser.visible)
    compare(h.service.appConversationVisible, false, "a view over the conversation is not reading it")
    h.app.openMediaBrowser("links")
    compare(h.app.mediaBrowserKind, "links")
    compare(h.service.browsed[1], "links")
    h.app.goBack()
    verify(!h.app.mediaBrowserOpen)
    compare(h.service.appConversationVisible, true)
  }

  function test_the_rail_line_says_why_this_app_paused_sync() {
    var h = createHarness({ syncActive: false })
    var status = findChild(h.app, "railSyncStatus")
    compare(status.label, "Sync stopped")
    h.service.syncPauseReason = "deleting a message"
    compare(status.label, "Sync paused · deleting a message")
    h.service.syncActive = true
    compare(status.label, "Sync paused · deleting a message")
    h.service.syncPauseReason = ""
    compare(status.label, "Connecting…")
  }

  function test_expired_link_is_visible_even_with_cached_chats() {
    var h = createHarness({ accounts: [{ account: "work", label: "work", main: true,
      connection_state: "relink-required", database_ready: true, authenticated: false }] })
    h.app.accountScope = "work"
    var status = findChild(h.app, "railSyncStatus")
    compare(status.label, "Link expired")
    compare(status.action, "Link again")
    verify(status.visible)
    verify(findChild(h.app, "railLinkAction").visible)
    status.actionRequested()
    compare(h.service.accountOperations.linkedName, "work")
    compare(h.service.accountOperations.mainLinked, true)
    h.service.accounts = [{ account: "personal", main: false, connection_state: "relink-required" }]
    h.app.accountScope = "personal"
    status.actionRequested()
    compare(h.service.accountOperations.linkedName, "personal")
    compare(h.service.accountOperations.mainLinked, false)
    h.service.accounts = [{ account: "work", connection_state: "connected" }]
    h.app.accountScope = "work"
    compare(status.label, "Linked · connected")
    compare(status.action, "")
    verify(!status.visible)
    verify(findChild(h.app, "railHeaderLinkStatus").visible)
  }

  function test_new_chat_is_a_rail_button_with_a_shortcut() {
    var app = createHarness().app
    var button = findChild(app, "railNewChatButton")
    verify(button !== null)
    compare(button.tooltipText, "New chat · Ctrl+N")
    var dialog = findChild(app, "newChatDialog")
    verify(dialog !== null)
    verify(!dialog.opened)
    button.clicked()
    tryCompare(dialog, "opened", true)
    dialog.close()
    tryCompare(dialog, "opened", false)
    app.forceActiveFocus()
    keyClick(Qt.Key_N, Qt.ControlModifier)
    tryCompare(dialog, "opened", true)
  }

  function test_new_chat_opens_an_existing_chat_in_the_rail() {
    var h = createHarness()
    var dialog = findChild(h.app, "newChatDialog")
    h.app.openNewChat()
    tryCompare(dialog, "opened", true)
    dialog.openChatRequested("other@example")
    compare(h.service.selectedChatJid, "other@example")
  }

  function test_a_started_chat_is_selected_once_it_syncs() {
    var h = createHarness()
    var dialog = findChild(h.app, "newChatDialog")
    dialog.chatStarted("15550003333@s.whatsapp.net")
    compare(h.app.pendingOpenChatJid, "15550003333@s.whatsapp.net")
    compare(h.service.selectedChatJid, "shared@example", "not in the rail yet")
    h.service.chats = [workChat, otherChat, {
      account: "work", jid: "15550003333@s.whatsapp.net", name: "Synthetic started",
      kind: "dm", preview: "", unread: 0 }]
    compare(h.service.selectedChatJid, "15550003333@s.whatsapp.net")
    compare(h.app.pendingOpenChatJid, "")
  }

  function test_hidden_chat_list_offers_the_way_back_in_the_conversation() {
    var app = createHarness().app
    var show = findChild(app, "showChatListButton")
    verify(show !== null)
    verify(!show.visible, "no toggle in the conversation while the list is visible")
    findChild(app, "railCollapseButton").clicked()
    verify(app.sidebarCollapsed)
    verify(show.visible)
    compare(show.tooltipText, "Show chat list · Ctrl+B")
    show.clicked()
    verify(!app.sidebarCollapsed)
  }

  function test_conversation_subtitle_is_empty_for_a_single_account() {
    var app = createHarness({ multiAccount: false }).app
    var subtitle = findChild(app, "conversationSubtitle")
    verify(subtitle !== null)
    compare(subtitle.text, "")
    verify(!subtitle.visible)
  }

  function test_conversation_subtitle_names_the_account_when_several_are_linked() {
    var app = createHarness({ multiAccount: true }).app
    compare(findChild(app, "conversationSubtitle").text, AccountModel.labelOf(workChat))
  }

  function test_sync_status_always_explains_the_connection() {
    var harness = createHarness()
    var status = findChild(harness.app, "railSyncStatus")
    verify(status !== null)
    verify(status.visible, "the account status is always visible")
    compare(status.label, "Connecting…")
    harness.service.syncActive = false
    compare(status.label, "Sync stopped")
    verify(status.visible)
    harness.service.offlineMode = true
    compare(status.label, "Offline · local archive")
    harness.service.statusReady = false
    compare(status.label, "Checking link…")
  }

  function test_ctrl_number_chat_jumps_are_gone() {
    var app = createHarness().app
    verify(typeof app.selectChatAt === "undefined")
  }

  function test_an_open_conversation_offers_no_read_action() {
    var harness = createHarness()
    verify(findChild(harness.app, "conversationReadToggle") === null,
      "the open conversation is read by being open")
    harness.app.toggleChatRead(workChat, false)
    compare(harness.service.lastChatRead.read, false)
    compare(harness.service.lastChatRead.ref.jid, workChat.jid)
  }

  function test_rail_row_offers_the_read_toggle_on_hover() {
    var harness = createHarness()
    var toggle = findChild(harness.app, "chatReadToggle")
    verify(toggle !== null, "every rail row carries the toggle")
    verify(!toggle.visible, "hidden until the row is hovered")
    // Start outside the row so an identical position from a prior test
    // still produces a real hover transition after layout settles.
    mouseMove(harness.app, 0, 0)
    wait(0)
    mouseMove(toggle.parent, toggle.parent.width / 2, toggle.parent.height / 2)
    tryVerify(function() { return toggle.visible })
    toggle.clicked()
    verify(harness.service.lastChatRead !== null)
  }

  function test_right_click_on_a_chat_opens_its_actions() {
    var harness = createHarness()
    var app = harness.app
    var row = findChild(app, "chatRowBody")
    var menu = findChild(app, "chatContextMenu")
    verify(menu !== null)
    mouseMove(row, 40, 20)
    wait(50)
    mouseClick(row, 40, 20, Qt.RightButton)
    tryVerify(function() { return menu.opened })
    compare(app.contextChat.jid, workChat.jid)
    compare(app.contextChatActions.map(function(item) { return item.action }),
      ["unread", "pin", "mute", "archive", "remove-local"])
    verify(app.runChatContextAction("pin"))
    compare(harness.service.lastChatAction.action, "pin")
    compare(harness.service.lastChatAction.ref.jid, workChat.jid)
    verify(!menu.opened)
  }

  function test_chat_menu_read_toggle_targets_that_row() {
    var harness = createHarness()
    var app = harness.app
    app.openChatContextMenu(otherChat, 10, 10)
    verify(app.runChatContextAction("unread"))
    compare(harness.service.lastChatRead.ref.jid, otherChat.jid)
    compare(harness.service.lastChatRead.read, false)
  }

  function test_chat_photos_setting_hides_every_photo() {
    var harness = createHarness()
    var photo = Object.assign({}, workChat, { avatar_path: "__demo_avatar__" })
    harness.service.chats = [photo, otherChat]
    var header = findChild(harness.app, "conversationAvatar")
    tryVerify(function() { return header.avatarReady }, 5000)
    harness.service.showAvatars = false
    verify(!header.showPhoto)
    verify(!header.avatarReady, "no photo loads with the setting off")
  }

  function test_compact_density_shortens_rail_rows() {
    var harness = createHarness()
    var row = findChild(harness.app, "chatRowBody")
    var comfortable = row.height
    harness.service.railDensity = "compact"
    verify(row.height < comfortable)
  }

  function test_save_as_opens_a_save_dialog_with_a_suggested_name() {
    var harness = createHarness()
    var app = harness.app
    verify(app.saveMediaAs({ id: "photo", filename: "trip.jpg", media_type: "image" }))
    var process = findChild(app, "savePickerProcess")
    verify(process.running)
    verify(process.command.indexOf("--save") >= 0)
    verify(process.command.indexOf("--confirm-overwrite") >= 0)
    verify(process.command.filter(function(arg) {
      return arg.indexOf("--filename=") === 0 && arg.endsWith("/Downloads/trip.jpg") }).length === 1)
  }

  function test_app_reports_when_the_conversation_is_on_screen() {
    var harness = createHarness()
    verify(harness.service.appConversationVisible, "open app showing the selected chat")
    harness.app.settingsOpen = true
    verify(!harness.service.appConversationVisible, "settings cover the conversation")
    harness.app.settingsOpen = false
    harness.app.opened = false
    verify(!harness.service.appConversationVisible, "a closed app shows nothing")
  }

  function test_list_shows_pinned_muted_and_unsent_drafts() {
    var harness = createHarness()
    var flagged = Object.assign({}, otherChat, { pinned: true, muted: true })
    harness.service.chats = [workChat, flagged]
    var app = harness.app
    verify(app.draftFor(flagged) === "")
    app.composerStates = { "work\nother@example": { text: "see you\nsoon", attachments: [] } }
    compare(app.draftFor(flagged), "see you soon", "one line, drafts of other chats only")
    compare(app.draftFor(workChat), "", "the open chat shows its draft in the composer")
    wait(0)
    var pinned = []
    var muted = []
    function walk(item) {
      if (item.objectName === "chatPinnedIcon" && item.visible) pinned.push(item)
      if (item.objectName === "chatMutedIcon" && item.visible) muted.push(item)
      for (var i = 0; i < item.children.length; i++) walk(item.children[i])
    }
    walk(app)
    compare(pinned.length, 1)
    compare(muted.length, 1)
  }

  function test_desktop_notifications_live_in_settings() {
    var harness = createHarness({ notificationsEnabled: true, notificationsPreview: true })
    var app = harness.app
    app.settingsOpen = true
    findChild(app, "settingsView").openSection("notifications")
    wait(0)
    var notify = findChild(app, "setting-notify")
    var preview = findChild(app, "setting-notify_preview")
    verify(notify !== null)
    compare(preview, null)
    verify(notify.checked)
    notify.toggled()
    compare(harness.service.lastNotifications.enabled, false)
    compare(harness.service.lastNotifications.preview, null)
  }

  function test_a_shared_contact_draft_checks_once_then_sends_and_opens_the_chat() {
    var h = createHarness()
    verify(h.app.openContactChat({ name: "Carla Synthetic", phone: "+1 555 000 2222", digits: "15550002222",
      jid: "", has_chat: false }, { id: "card", sender: "Sam", from_me: false }))
    compare(h.service.checkedNumbers, ["15550002222"], "asked WhatsApp once, on opening")
    compare(h.app.contactDraftState, "checking")
    var status = findChild(h.app, "contactDraftStatus")
    verify(status.text.indexOf("checking") > 0)
    var send = findChild(h.app, "contactDraftSend")
    var field = findChild(h.app, "contactDraftField")
    field.text = "hello Carla"
    verify(!send.ready, "nothing goes before WhatsApp answers")
    verify(!h.app.sendContactDraft())
    h.service.numberChecks = { "15550002222": { phone: "15550002222", loading: false, registered: true,
      jid: "15550002222@s.whatsapp.net", error: "" } }
    compare(h.app.contactDraftState, "registered")
    verify(status.text.indexOf("on WhatsApp") > 0)
    verify(send.ready)
    verify(h.app.sendContactDraft())
    compare(h.service.startedChats.length, 1)
    compare(h.service.startedChats[0].jid, "15550002222@s.whatsapp.net")
    compare(h.service.startedChats[0].text, "hello Carla")
    verify(!field.enabled, "one send at a time")
    h.service.lastStartedChatJid = "15550002222@s.whatsapp.net"
    h.service.writeCompleted("send-new", { account: "work", jid: "15550002222@s.whatsapp.net" },
      { target: { jid: "15550002222@s.whatsapp.net" }, text: "hello Carla" }, "app")
    compare(h.app.contactDraft, null, "the draft gives way to the new chat")
    compare(h.app.pendingOpenChatJid, "15550002222@s.whatsapp.net")
  }

  function test_a_contact_not_on_whatsapp_cannot_be_messaged() {
    var h = createHarness()
    verify(h.app.openContactChat({ name: "Nobody Synthetic", digits: "15550003333", jid: "" }))
    h.service.numberChecks = { "15550003333": { phone: "15550003333", loading: false, registered: false,
      responded: true, jid: "", error: "" } }
    compare(h.app.contactDraftState, "absent")
    verify(!findChild(h.app, "contactDraftField").enabled)
    verify(findChild(h.app, "contactDraftExplainer").text.indexOf("is not on WhatsApp") > 0)
  }

  function test_a_failed_first_message_stays_in_the_draft() {
    var h = createHarness()
    verify(h.app.openContactChat({ name: "Known Synthetic", digits: "15550004444",
      jid: "15550004444@s.whatsapp.net", has_chat: false }))
    compare(h.app.contactDraftState, "known", "a known person needs no check")
    compare(h.service.checkedNumbers.length, 0)
    findChild(h.app, "contactDraftField").text = "hi"
    verify(h.app.sendContactDraft())
    h.service.writeFailed("WhatsApp refused it.", { account: "work", jid: "15550004444@s.whatsapp.net" },
      { kind: "send-new", request: {} }, "app")
    verify(h.app.contactDraft !== null)
    compare(findChild(h.app, "contactDraftError").text, "WhatsApp refused it.")
    verify(findChild(h.app, "contactDraftField").enabled)
  }

  function test_quit_closes_the_window_and_opening_starts_it_again() {
    var h = createHarness()
    verify(h.app.quitApp())
    compare(h.service.quits, 1)
    verify(!h.app.opened, "the window closes")
    var status = findChild(h.app, "railSyncStatus")
    verify(status.label.indexOf("Closed") === 0, "the list says it is closed")
    h.app.open(JSON.stringify({}))
    compare(h.service.launches, 1, "opening a closed OmaWhatsApp starts it")
    h.app.open(JSON.stringify({}))
    compare(h.service.launches, 1, "an open one is not started twice")
  }

  // A stock Omarchy has no zenity: picking a file says so and offers to
  // install it instead of failing silently.
  function test_without_zenity_the_file_picker_offers_to_install_it() {
    var harness = createHarness({ zenityAvailable: false })
    var picker = findChild(harness.app, "filePickerProcess")
    harness.app.openFilePicker("document")
    verify(!picker.running, "no dialog without zenity")
    verify(harness.app.copyToastVisible)
    verify(harness.app.toastText.indexOf("zenity") >= 0)
    compare(harness.app.toastActionLabel, "Install")
    verify(harness.app.runToastAction())
    compare(harness.service.zenityInstalls, 1)
    harness.service.zenityAvailable = true
    harness.app.openFilePicker("document")
    verify(picker.running, "with zenity the dialog opens")
    compare(picker.command[0], "/usr/bin/zenity")
  }
}
