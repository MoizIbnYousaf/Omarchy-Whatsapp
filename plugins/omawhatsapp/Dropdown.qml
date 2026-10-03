import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DropdownModel.js" as DropdownModel
import "AccountModel.js" as AccountModel
import "TimeFormat.js" as TimeFormat
import "ComposerModel.js" as ComposerModel
import "FormatModel.js" as FormatModel
import "PresenceModel.js" as PresenceModel
import "Tint.js" as Tint

// A complete, bar-anchored mini client. The resident service stays the single
// source of truth; this surface only owns transient navigation and draft state.
Panel {
  id: root
  moduleName: "io.github.moizibnyousaf.omawhatsapp"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool demoMode: false
  property int maxRows: 7
  property int selectedIndex: 0
  property int messageIndex: 0
  property string searchText: ""
  property string accountScope: ""
  property string viewMode: "chats"
  property var currentChat: null
  property var replyTarget: null
  property var pendingAttachments: []
  property var pendingWriteIntent: null
  property bool resumePendingWrite: false
  property string errorText: ""
  property bool copiedVisible: false
  property bool clearConfirmOpen: false
  property bool demoNotificationsCleared: false
  property string demoPlaybackId: ""
  property int composerMaxLines: service ? service.composerMaxLines : 6
  property string demoTimeFormat: "auto"
  // The account's signature on outgoing texts and captions, skippable once.
  property var demoSignature: ({ enabled: false, name: "", position: "top" })
  property bool signatureSkipped: false
  readonly property var composerSignature: demoMode ? demoSignature
    : (service && typeof service.signatureFor === "function"
      ? service.signatureFor(currentAccount()) : ({ enabled: false, name: "", position: "top" }))
  readonly property bool signatureActive: composerSignature.enabled === true
  readonly property string timeFormat: demoMode ? demoTimeFormat
    : (service ? service.timeFormat : "auto")

  // Voice notes play here, outside the rows a new message rebuilds.
  TimelineAudio {
    id: dropdownAudio
    objectName: "dropdownAudio"
    messages: root.sourceMessages
    activeId: root.activePlaybackId
    rate: root.service ? root.service.audioRate : 1
    active: root.opened && root.viewMode === "conversation"
    onAdvanceRequested: function(messageId) { root.requestPlayback(messageId) }
  }

  FontMetrics {
    id: composerMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
  property var demoItems: [
    { id: "demo-message-1", text: "The bar dropdown can send now.", sender: "Alex", timestamp: 1787540400, from_me: false, media_type: "", mime_type: "", local_path: "", reactions: [] },
    { id: "demo-message-2", text: "Fast, local, and keyboard-first.", sender: "You", timestamp: 1787540100, from_me: true, media_type: "", mime_type: "", local_path: "", reactions: [{ emoji: "⚡", from_me: false }], status: "read" },
    { id: "demo-message-3", text: "Open the full client only when you need the whole toolbox.", sender: "Design team", timestamp: 1787539800, from_me: false, media_type: "", mime_type: "", local_path: "", reactions: [] }
  ]

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: Color.popups.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color muted: Qt.rgba(
    foreground.r * 0.60 + background.r * 0.40,
    foreground.g * 0.60 + background.g * 0.40,
    foreground.b * 0.60 + background.b * 0.40, 1)
  readonly property color subtle: Qt.rgba(
    foreground.r * 0.10 + background.r * 0.90,
    foreground.g * 0.10 + background.g * 0.90,
    foreground.b * 0.10 + background.b * 0.90, 1)
  readonly property color selected: Qt.rgba(
    accent.r * 0.18 + background.r * 0.82,
    accent.g * 0.18 + background.g * 0.82,
    accent.b * 0.18 + background.b * 0.82, 1)
  readonly property string fontFamily: Style.font.family
  property var demoChats: [
    { jid: "demo-team", name: "Design team", kind: "group", account: "work", account_label: "work", avatar_path: "__demo_avatar__", preview: "The compact client can send now", timestamp: 1787540400, unread: 3, notification_unread: 3, pinned: true },
    { jid: "demo-alex", name: "Alex", kind: "dm", account: "personal", account_label: "personal", avatar_path: "__demo_avatar__", preview: "Looks perfect — ship it", timestamp: 1787539800, unread: 1, notification_unread: 1, pinned: false },
    { jid: "demo-lab", name: "Omarchy Lab", kind: "group", account: "work", account_label: "work", avatar_path: "", preview: "Native, private, and instant", timestamp: 1787539200, unread: 0, notification_unread: 0, pinned: false }
  ]
  readonly property bool multiAccount: demoMode
    || (!!service && service.multiAccount === true)
  readonly property var sourceChats: demoMode
    ? demoChats : (service && Array.isArray(service.chats) ? service.chats : [])
  readonly property var accountEntries: demoMode
    ? [{ account: "work", label: "work" },
       { account: "personal", label: "personal" }]
    : (service && Array.isArray(service.accounts) ? service.accounts : [])
  function accountMark(chat) {
    if (!root.multiAccount || !chat) return -1
    return AccountModel.accountIndex(root.accountEntries, String(chat.account || ""))
  }
  // The count in the header toggles this: only chats with unread messages.
  property bool unreadOnly: false
  function badgeTapped(button) {
    if (button === Qt.RightButton) return root.requestClearNotifications()
    root.unreadOnly = !root.unreadOnly
    root.selectedIndex = 0
    return true
  }
  readonly property var filteredChats: {
    var needle = String(searchText || "").trim().toLowerCase()
    var scope = AccountModel.normalizeScope(root.accountScope, root.accountEntries)
    // Archived chats stay out of the recent list, as on the phone.
    return AccountModel.filterChats(root.sourceChats, scope, needle,
      Math.max(1, Number(maxRows || 7)), root.unreadOnly ? "unread" : "all")
  }
  Binding {
    target: root.service
    property: "dropdownConversationVisible"
    when: !!root.service && !root.demoMode
    value: root.opened && root.viewMode === "conversation" && root.serviceOnCurrentChat
  }
  readonly property bool serviceOnCurrentChat: !!service
    && AccountModel.sameRef(
      AccountModel.chatRef(service.selectedChatAccount, service.selectedChatJid),
      currentChatRef())
  readonly property var sourceMessages: demoMode
    ? demoItems : (serviceOnCurrentChat && Array.isArray(service.messages)
      ? (Array.isArray(service.selectedMessages) ? service.selectedMessages : service.messages) : [])
  readonly property int rowHeight: Style.space(52)
  readonly property int chatListHeight: Math.max(2,
    Math.min(Math.max(2, maxRows), Math.max(2, filteredChats.length))) * rowHeight
  readonly property string accountReadinessSummary: AccountModel.unreadyAccountSummary(
    demoMode || !service ? [] : service.accounts)
  readonly property int accountReadinessHeight: accountReadinessSummary === ""
    ? 0 : Style.space(36)
  readonly property int chatChromeHeight:
    Style.space(40 + 8 + 32 + 8 + 8 + 8 + 26)
      + accountSwitcher.height + railSyncStatus.height + Style.space(8)
  readonly property int desiredHeight: viewMode === "conversation"
    ? Style.space(620) : chatChromeHeight
      + accountReadinessHeight + chatListHeight
  readonly property int notificationCount: demoMode
    ? (demoNotificationsCleared ? 0 : 2)
    : (service ? Number(service.notificationUnreadCount || 0) : 0)
  readonly property bool ready: demoMode || (service && service.railReady)
  readonly property bool accountStatusReady: demoMode || (!!service
    && service.statusReady
    && String(service.statusAccount || "") === currentAccount())
  readonly property bool offline: !demoMode && accountStatusReady
    && service.offlineMode
  // Only this surface's own sends: automatic reading and other background
  // writes must never freeze the mini client or block going back.
  readonly property bool sending: !demoMode && !!service && service.writing
    && service.activeWriteOwner === "dropdown"
    && String(service.activeWriteChatJid || "") === currentJid()
    && String(service.activeWriteAccount || "") === currentAccount()
  readonly property bool voiceForCurrentChat: !demoMode && service
    && String(service.voiceDraftJid || "") === currentJid()
    && String(service.voiceDraftAccount || "") === currentAccount()
    && String(service.voiceState || "idle") !== "idle"
  readonly property var playbackCoordinator: service ? service.playback : null
  readonly property string activePlaybackId: demoMode ? demoPlaybackId
    : (playbackCoordinator
      ? playbackCoordinator.messageFor("dropdown", currentChatRef()) : "")

  signal fullAppRequested(var payload)
  signal refreshRequested()

  onFilteredChatsChanged: clampSelection()

  function currentJid() {
    return currentChat ? String(currentChat.jid || "") : ""
  }

  function currentAccount() {
    return currentChat ? String(currentChat.account || "") : ""
  }

  function currentChatRef() {
    return AccountModel.refOf(currentChat)
  }

  function stopPlayback() {
    demoPlaybackId = ""
    if (playbackCoordinator) playbackCoordinator.releaseSurface("dropdown")
  }

  function requestPlayback(messageId) {
    var granted = false
    if (demoMode || !playbackCoordinator) {
      demoPlaybackId = String(messageId || "")
      granted = demoPlaybackId !== ""
    } else {
      granted = playbackCoordinator.acquire("dropdown", currentChatRef(), messageId)
    }
    if (granted && dropdownAudio.playable(dropdownAudio.itemFor(messageId)))
      dropdownAudio.play(messageId)
    return granted
  }

  function reconcileCurrentChat() {
    if (!opened || demoMode || viewMode !== "conversation" || !service || !currentChat) return
    var exact = AccountModel.findChat(service.chats, currentChatRef())
    if (!exact) {
      currentChat = null
      backToChats()
      return
    }
    currentChat = exact
  }

  function validateServiceSelection() {
    if (!opened || demoMode || viewMode !== "conversation" || !service || !currentChat) return
    if (sending) return
    var serviceRef = AccountModel.chatRef(
      service.selectedChatAccount, service.selectedChatJid)
    if (AccountModel.sameRef(serviceRef, currentChatRef())) return
    currentChat = null
    backToChats()
  }

  function clampSelection() {
    selectedIndex = DropdownModel.clampIndex(selectedIndex, filteredChats.length)
  }

  function openFor(realData) {
    var resume = realData !== false && resumePendingWrite
      && currentChat !== null && viewMode === "conversation"
    if (resume) {
      demoMode = false
      resumePendingWrite = false
      searchText = ""
      if (service) {
        service.dropdownOpen = true
        service.selectChat(currentChat)
        service.refreshChats()
      }
      controller.show()
      Qt.callLater(function() {
        if (root.opened) root.focusComposer()
      })
      return
    }
    if (ComposerModel.validWriteIntent(pendingWriteIntent)) return
    resumePendingWrite = false
    if (!demoMode && service) service.discardStages(pendingAttachments)
    demoMode = realData === false
    clearConfirmOpen = false
    demoNotificationsCleared = false
    searchText = ""
    selectedIndex = 0
    messageIndex = 0
    viewMode = "chats"
    currentChat = null
    replyTarget = null
    pendingAttachments = []
    errorText = ""
    if (!demoMode && service) {
      service.dropdownOpen = true
      service.refreshChats()
    }
    controller.show()
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  readonly property bool enterSends: demoMode || !service || service.enterSends !== false
  readonly property bool showAvatars: demoMode || !service || service.showAvatars !== false
  readonly property string composerHint: enterSends
    ? "Enter sends · Shift+Enter adds a line" : "Ctrl+Enter sends · Enter adds a line"

  // Open on a conversation, the dropdown shows the account online like the
  // window does, and the chat's typing, online or last seen.
  readonly property bool presenceFocused: opened && viewMode === "conversation" && !demoMode
  onPresenceFocusedChanged: if (service) service.setPresenceFocus("dropdown", presenceFocused)
  // The service may go first when the shell tears everything down.
  Component.onDestruction: if (!demoMode && service && service.setPresenceFocus)
    service.setPresenceFocus("dropdown", false)
  readonly property var presenceLine: {
    if (demoMode || !service || !currentChat) return { text: "", live: false }
    var now = service.presenceNow
    return PresenceModel.line(service.presenceSnapshotFor(String(currentChat.account || "")),
      String(currentChat.jid || ""), {
        now: now, date: new Date(now * 1000), group: String(currentChat.kind || "") === "group",
        names: ({}), clock: TimeFormat.clockPattern(timeFormat, Qt.locale().timeFormat(Locale.ShortFormat))
      })
  }

  function open() { openFor(true) }
  function openDemo() { openFor(false) }

  function close() {
    if (ComposerModel.validWriteIntent(pendingWriteIntent))
      resumePendingWrite = true
    searchField.focus = false
    composer.focus = false
    clearConfirmOpen = false
    stopPlayback()
    if (!demoMode && service) service.stopVoiceForSurfaceClose()
    if (!demoMode && service) service.dropdownOpen = false
    controller.hide()
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function moveSelection(delta) {
    if (viewMode === "conversation") {
      if (sourceMessages.length === 0) return
      messageIndex = DropdownModel.visualMessageIndex(
        messageIndex, delta, sourceMessages.length)
      messageList.positionViewAtIndex(messageIndex, ListView.Contain)
      return
    }
    if (filteredChats.length === 0) return
    selectedIndex = DropdownModel.clampIndex(selectedIndex + delta, filteredChats.length)
    chatList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function activateSelection() {
    if (viewMode === "conversation") {
      focusComposer()
      return
    }
    if (selectedIndex < 0 || selectedIndex >= filteredChats.length) return
    openConversation(filteredChats[selectedIndex])
  }

  // Anchored to the oldest unread message, so replies never land above it.
  property var unreadMarker: ({ key: "", count: 0, anchor: "", resolved: true })
  readonly property int unreadDividerIndex: unreadMarker.key !== ""
    && unreadMarker.key === AccountModel.refOf(currentChat).key && unreadMarker.count > 0
    ? AccountModel.messageIndexOf(sourceMessages, unreadMarker.anchor) : -1
  function resolveUnreadAnchor() {
    var marker = unreadMarker
    if (marker.resolved || marker.key !== AccountModel.refOf(currentChat).key
        || !AccountModel.hasStoredMessages(sourceMessages)) return
    unreadMarker = Object.assign({}, marker, {
      anchor: AccountModel.unreadAnchorId(sourceMessages, marker.count), resolved: true })
  }
  onSourceMessagesChanged: resolveUnreadAnchor()

  function openConversation(chat) {
    if (sending) return
    if (!chat || !chat.jid) return
    signatureSkipped = false
    unreadMarker = { key: AccountModel.refOf(chat).key, count: Number(chat.unread || 0),
      anchor: "", resolved: Number(chat.unread || 0) <= 0 }
    if (!demoMode && service) service.discardStages(pendingAttachments)
    stopPlayback()
    currentChat = chat
    viewMode = "conversation"
    messageIndex = 0
    replyTarget = null
    pendingAttachments = []
    errorText = ""
    if (!demoMode && service) service.selectChat(chat)
    resolveUnreadAnchor()
    Qt.callLater(focusComposer)
  }

  function backToChats() {
    if (sending) return
    if (!demoMode && service) service.stopVoiceForSurfaceClose()
    stopPlayback()
    replyTarget = null
    composer.focus = false
    viewMode = "chats"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function scrollToNewest() {
    messageList.positionViewAtBeginning()
    Qt.callLater(function() {
      messageList.positionViewAtBeginning()
      Qt.callLater(function() { messageList.positionViewAtBeginning() })
    })
  }

  function newestMessageOffset(contentY) {
    if (messageList.count === 0) return 0
    var item = messageList.itemAtIndex(0)
    if (!item) return 100000
    return item.mapToItem(messageList, 0, item.height).y - messageList.height
  }

  // The day of the topmost message floats at the top while scrolling.
  property string floatingDayLabel: ""
  function showFloatingDay() {
    if (messageList.count === 0) return
    var index = messageList.indexAt(messageList.width / 2, messageList.contentY + Style.space(10))
    var item = index >= 0 ? root.sourceMessages[index] : null
    floatingDayLabel = item ? TimeFormat.dayLabel(item.timestamp) : ""
    compactDayHold.restart()
  }

  // Opens one chat by its account and JID, as a clicked notification asks.
  function openChatRef(account, jid) {
    var target = String(jid || "")
    if (target === "") return false
    var chats = service && Array.isArray(service.chats) ? service.chats : []
    var known = chats.find(function(chat) {
      return String(chat.jid || "") === target
        && (String(account || "") === "" || String(chat.account || "") === String(account))
    })
    openConversation(known || { account: String(account || ""), jid: target,
      name: "WhatsApp chat", kind: target.indexOf("@g.us") > 0 ? "group" : "dm" })
    return true
  }

  // Choosing where to forward needs the full app's picker; it opens there
  // for this message, so the forward is never started twice.
  function forwardInFullApp(item) {
    if (sending || !item || !item.id) return false
    var payload = DropdownModel.fullAppPayload(currentChat)
    payload.forward = { id: String(item.id), text: String(item.text || ""),
      media_type: String(item.media_type || ""), filename: String(item.filename || "") }
    if (!demoMode && service) service.discardStages(pendingAttachments)
    pendingAttachments = []
    close()
    fullAppRequested(payload)
    return true
  }

  function openFullApp() {
    if (sending) return
    var payload = DropdownModel.fullAppPayload(currentChat)
    if (!demoMode && service) service.discardStages(pendingAttachments)
    pendingAttachments = []
    close()
    fullAppRequested(payload)
  }

  // Starting a chat needs room for search, a number check and a first
  // message, so the dropdown hands it to the full app's dialog.
  function openNewChat() {
    if (sending) return false
    if (!demoMode && service) service.discardStages(pendingAttachments)
    pendingAttachments = []
    close()
    fullAppRequested({ newChat: true })
    return true
  }

  function refresh() {
    if (!demoMode && service) {
      service.refreshChats()
      if (viewMode === "conversation") service.refreshMessages()
    }
    refreshRequested()
  }

  function requestClearNotifications() {
    if (notificationCount <= 0 || clearConfirmOpen) return false
    clearConfirm.selectedIndex = 1
    clearConfirmOpen = true
    Qt.callLater(function() { clearConfirmKeys.forceActiveFocus() })
    return true
  }

  function cancelClearNotifications() {
    clearConfirmOpen = false
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function confirmClearNotifications() {
    if (!clearConfirmOpen) return false
    clearConfirmOpen = false
    if (demoMode) demoNotificationsCleared = true
    else if (service) service.dismissNotifications("", "")
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
    return true
  }

  function focusSearch() {
    if (viewMode !== "chats") return
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function focusComposer() {
    if (viewMode !== "conversation") return
    composer.forceActiveFocus()
    composer.cursorPosition = composer.length
  }

  // Right-click in the composer: editing actions, then WhatsApp formatting.
  function openComposerMenu(x, y) {
    var point = composer.mapToItem(dropdownFormatMenu.parent, x, y)
    dropdownFormatMenu.x = Math.max(0, Math.min(dropdownFormatMenu.parent.width - dropdownFormatMenu.width, point.x))
    dropdownFormatMenu.y = Math.max(-dropdownFormatMenu.height - Style.space(6), point.y - dropdownFormatMenu.height)
    dropdownFormatMenu.open()
  }
  function composerMenuAction(kind) {
    if (kind === "cut") composer.cut()
    else if (kind === "copy") composer.copy()
    else if (kind === "paste") root.pasteClipboard()
    else if (kind === "select-all") composer.selectAll()
    else return root.applyFormat(kind)
    composer.forceActiveFocus()
    return true
  }

  function applyFormat(kind) {
    var edit = FormatModel.apply(composer.text, composer.selectionStart, composer.selectionEnd, kind)
    if (!edit) return false
    composer.remove(edit.head, edit.end)
    composer.insert(edit.head, edit.insert)
    composer.select(edit.start, edit.selectEnd)
    composer.forceActiveFocus()
    return true
  }

  // "Message" on a shared contact: its chat here when it has one, otherwise
  // the full app's new chat dialog with the number typed in.
  // A known person opens here; someone with no chat yet gets the full app's
  // draft chat, over the chat the card came from.
  function openContactChat(card, message) {
    if (!card || demoMode) return false
    var jid = String(card.jid || "")
    var chats = service && Array.isArray(service.chats) ? service.chats : []
    var known = jid === "" ? null : chats.find(function(chat) { return String(chat.jid || "") === jid })
    if (known) {
      openConversation(known)
      return true
    }
    var payload = DropdownModel.fullAppPayload(currentChat)
    payload.contact = { name: String(card.name || ""), phone: String(card.phone || ""),
      digits: String(card.digits || ""), jid: jid,
      message_id: message ? String(message.id || "") : "",
      shared_by: message && message.from_me !== true ? String(message.sender || "") : "" }
    close()
    fullAppRequested(payload)
    return true
  }

  function pasteClipboard() {
    if (demoMode) {
      composer.insert(composer.cursorPosition, "pasted from clipboard")
      focusComposer()
      return
    }
    // Pasting never waits for a WhatsApp action; plain text still pastes
    // when the helper cannot run.
    if (!service || !service.pasteClipboard(currentChatRef(), "dropdown")) composer.paste()
  }

  // A send while another WhatsApp action runs waits for it instead of being
  // dropped, as in the full app.
  property string queuedSendKey: ""
  readonly property bool sendQueued: queuedSendKey !== ""
    && queuedSendKey === String(currentChatRef().key || "")
  function runQueuedSend() {
    if (queuedSendKey === "" || !service || service.writing) return false
    if (queuedSendKey !== String(currentChatRef().key || "")) {
      queuedSendKey = ""
      return false
    }
    queuedSendKey = ""
    sendDraft()
    return true
  }

  function localFileUrl(path) {
    return "file://" + String(path || "").split("/")
      .map(function(part) { return encodeURIComponent(part) }).join("/")
  }

  function openFilePicker() {
    var origin = currentChatRef()
    if (filePickerProcess.running || sending || origin.jid === "") return
    if (!demoMode && service && service.zenityAvailable === false) {
      errorText = "Choosing files needs zenity (omarchy pkg add zenity). Paste or drag files in meanwhile."
      return
    }
    filePickerProcess.originRef = AccountModel.chatRef(origin.account, origin.jid)
    filePickerProcess.command = ["/usr/bin/zenity", "--file-selection",
      "--multiple", "--separator=\n", "--title=Add WhatsApp attachments"]
    filePickerProcess.running = true
  }

  function sendDraft() {
    var text = String(composer.text || "").trim()
    if (text === "" && pendingAttachments.length === 0) return
    if (demoMode) {
      demoItems = [ComposerModel.demoMessage(text,
        pendingAttachments.length > 0, replyTarget, Date.now())].concat(demoItems)
      composer.text = ""
      pendingAttachments = []
      replyTarget = null
      return
    }
    if (!service || offline) return
    // Plain texts join the service queue at once; files wait here.
    if (service.writing && pendingAttachments.length > 0) {
      queuedSendKey = String(currentChatRef().key || "")
      return
    }
    queuedSendKey = ""
    errorText = ""
    var kind = pendingAttachments.length > 0 ? "files" : "send"
    var request = pendingAttachments.length > 0 ? {
      paths: pendingAttachments.slice(),
      caption: text,
      reply_id: replyTarget ? String(replyTarget.id || "") : ""
    } : {
      text: text,
      reply_id: replyTarget ? String(replyTarget.id || "") : "",
      mentions: []
    }
    var snapshot = {
      text: String(composer.text || ""),
      attachments: pendingAttachments.slice(),
      reply: replyTarget,
      mentions: []
    }
    var intent = ComposerModel.writeIntent(currentChatRef(), kind, request, snapshot)
    pendingWriteIntent = intent
    var started = pendingAttachments.length > 0
      ? service.sendFilesReply(currentChatRef(), request.paths, request.caption,
          request.reply_id, "dropdown", !signatureSkipped)
      : service.sendText(currentChatRef(), text,
          request.reply_id, request.mentions, "dropdown", !signatureSkipped)
    if (started) {
      signatureSkipped = false
      var consumed = ComposerModel.startedIntentState(intent)
      composer.text = String(consumed.text || "")
      pendingAttachments = consumed.attachments
      replyTarget = consumed.reply
    } else {
      pendingWriteIntent = null
    }
  }

  function toggleVoiceRecording() {
    if (demoMode) {
      errorText = "Voice notes record only in a real chat"
      return false
    }
    if (!service || currentJid() === "") return false
    if (service.writing) {
      errorText = "Finish the current WhatsApp action before recording"
      return false
    }
    if (String(service.voiceState || "idle") === "idle"
        && (String(composer.text || "").trim() !== ""
            || pendingAttachments.length > 0)) {
      errorText = "Send or clear the current draft before recording a voice note"
      return false
    }
    errorText = ""
    return service.toggleVoice(currentAccount(), currentJid(), String(currentChat.name || "WhatsApp chat"),
      replyTarget ? replyTarget.id : "", "dropdown")
  }

  function removeAttachment(index) {
    if (sending) return
    var next = pendingAttachments.slice()
    var removed = next.splice(index, 1)
    if (!demoMode && service) service.discardStages(removed)
    pendingAttachments = next
  }

  function attachmentName(url) {
    var parts = String(url || "").split("/")
    try { return decodeURIComponent(parts[parts.length - 1] || "Attachment") }
    catch (error) { return parts[parts.length - 1] || "Attachment" }
  }

  function copyText(value) {
    var text = String(value || "")
    if (text === "" || clipboardProcess.running) return
    clipboardProcess.payload = text
    clipboardProcess.stdinEnabled = true
    clipboardProcess.running = true
  }

  // Someone typing in a listed chat replaces its preview, as in the full app.
  function chatTyping(chat) {
    if (demoMode || !service || !chat) return false
    return PresenceModel.isTyping(service.presenceSnapshotFor(String(chat.account || "")),
      String(chat.jid || ""), service.presenceNow)
  }

  // The row's quick action: read if it has unread messages, unread otherwise.
  function toggleChatRead(chat) {
    if (!chat) return false
    var read = Number(chat.unread || 0) > 0
    if (demoMode) {
      demoChats = demoChats.map(function(item) {
        if (String(item.jid) !== String(chat.jid)) return item
        var next = Object.assign({}, item)
        next.unread = read ? 0 : 1
        next.notification_unread = read ? 0 : 1
        return next
      })
      return true
    }
    return !!service && service.setChatRead(AccountModel.refOf(chat), read, "dropdown")
  }

  // The same stamps as the full app's list.
  // A key typed into the box shows "typing…" to the chat; an emptied box
  // stops it (see the full app).
  function noteComposerKey(event) {
    if (demoMode || !service || typeof service.composerActivity !== "function") return
    var navigation = [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Escape,
      Qt.Key_Tab, Qt.Key_Up, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right, Qt.Key_PageUp, Qt.Key_PageDown,
      Qt.Key_Home, Qt.Key_End, Qt.Key_Return, Qt.Key_Enter]
    if (navigation.indexOf(event.key) >= 0) return
    var ref = currentChatRef()
    Qt.callLater(function() { if (root.service) root.service.composerActivity(ref, composer.text) })
  }
  function composerEmptied() {
    if (demoMode || !service || typeof service.composerActivity !== "function") return
    service.composerActivity(currentChatRef(), "")
  }

  function timeLabel(value) {
    return TimeFormat.listStamp(value, new Date(),
      TimeFormat.clockPattern(root.timeFormat, Qt.locale().timeFormat(Locale.ShortFormat)),
      Qt.locale().dateFormat(Locale.ShortFormat))
  }

  Connections {
    target: root.service
    function onChatsChanged() { root.reconcileCurrentChat() }
    function onSelectedChatJidChanged() {
      Qt.callLater(root.validateServiceSelection)
    }
    function onSelectedChatAccountChanged() {
      Qt.callLater(root.validateServiceSelection)
    }
    function onPasteFailed(message, chatRef, owner) {
      if (!ComposerModel.ownsOperation(owner, "dropdown")) return
      if (AccountModel.sameRef(chatRef, root.currentChatRef())) composer.paste()
    }
    function onWritingChanged() {
      if (root.service && !root.service.writing && root.queuedSendKey !== "")
        Qt.callLater(root.runQueuedSend)
    }
    function onTextPasted(text, chatRef, owner) {
      if (!ComposerModel.ownsOperation(owner, "dropdown")) return
      if (!AccountModel.sameRef(chatRef, root.currentChatRef())) return
      composer.insert(composer.cursorPosition, String(text || ""))
      root.focusComposer()
    }
    function onAttachmentPasted(path, chatRef, owner) {
      if (!ComposerModel.ownsOperation(owner, "dropdown")) return
      if (!AccountModel.sameRef(chatRef, root.currentChatRef())) return
      var next = root.pendingAttachments.slice()
      if (next.indexOf(path) < 0 && next.length < 10) next.push(path)
      else if (next.indexOf(path) < 0 && root.service)
        root.service.discardStage(path)
      root.pendingAttachments = next
      root.focusComposer()
    }
    function onWriteCompleted(kind, chatRef, request, owner) {
      if (!ComposerModel.ownsOperation(owner, "dropdown")) return
      var intent = root.pendingWriteIntent
      if (ComposerModel.validWriteIntent(intent)) {
        if (!ComposerModel.writeIntentMatches(intent, chatRef, kind)) return
      } else if (!AccountModel.sameRef(chatRef, root.currentChatRef())) return
      if (kind === "send" || kind === "files") {
        var current = {
          text: String(composer.text || ""),
          attachments: root.pendingAttachments,
          reply: root.replyTarget
        }
        var completed = ComposerModel.validWriteIntent(intent)
          ? ComposerModel.completedIntentState(current, intent)
          : ComposerModel.completedState(current, kind, request)
        composer.text = String(completed.text || "")
        root.pendingAttachments = completed.attachments
        root.replyTarget = completed.reply
      }
      if (kind === "voice") root.replyTarget = null
      root.pendingWriteIntent = null
      if (!root.opened) root.resumePendingWrite = true
      else root.focusComposer()
      Qt.callLater(root.validateServiceSelection)
    }
    function onChatStateFailed(message, chatRef, action, owner) {
      if (!ComposerModel.ownsOperation(owner, "dropdown")) return
      root.errorText = String(message || "WhatsApp could not change the read state.")
    }
    function onWriteFailed(message, chatRef, details, owner) {
      if (!ComposerModel.ownsOperation(owner, "dropdown")) return
      var intent = root.pendingWriteIntent
      if (ComposerModel.validWriteIntent(intent)) {
        if (!ComposerModel.writeIntentMatches(intent, chatRef,
            details && details.kind)) return
      } else if (!AccountModel.sameRef(chatRef, root.currentChatRef())) return
      var kind = String(details && details.kind
        || (intent ? intent.kind : ""))
      // A failed text stays as a bubble to retry; the composer keeps what
      // was typed since.
      if (ComposerModel.validWriteIntent(intent) && !(details && details.pending_kept)) {
        var failed = ComposerModel.failedIntentState({
          text: String(composer.text || ""),
          attachments: root.pendingAttachments,
          reply: root.replyTarget,
          mentions: []
        }, intent, details)
        composer.text = String(failed.text || "")
        root.pendingAttachments = failed.attachments
        root.replyTarget = failed.reply
      } else if (kind === "files") {
        root.pendingAttachments = ComposerModel.remainingAttachments(
          root.pendingAttachments, details)
      }
      root.pendingWriteIntent = null
      root.errorText = String(message || "Message could not be sent")
      if (!root.opened) root.resumePendingWrite = true
      else root.focusComposer()
      Qt.callLater(root.validateServiceSelection)
    }
  }

  Process {
    id: clipboardProcess
    property string payload: ""
    command: ["/usr/bin/wl-copy", "--type", "text/plain;charset=utf-8"]
    stdinEnabled: true
    onStarted: {
      write(payload)
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.copiedVisible = true
        copiedTimer.restart()
      }
    }
  }

  Process {
    id: filePickerProcess
    property var originRef: AccountModel.chatRef("", "")
    command: []
    stdout: StdioCollector { id: filePickerOutput }
    stderr: StdioCollector { id: filePickerError }
    onExited: function(exitCode) {
      var target = originRef
      originRef = AccountModel.chatRef("", "")
      if (exitCode !== 0 || !root.opened || root.viewMode !== "conversation"
          || !AccountModel.sameRef(target, root.currentChatRef())) return
      var incoming = String(filePickerOutput.text || "").split(/\r?\n/)
        .map(function(path) { return path.trim() })
        .filter(function(path) { return path.startsWith("/") })
        .map(root.localFileUrl)
      var result = ComposerModel.pickedState({
        text: String(composer.text || ""),
        attachments: root.pendingAttachments,
        reply: root.replyTarget,
        error: root.errorText
      }, incoming, "document", 10)
      root.pendingAttachments = result.state.attachments
      root.errorText = String(result.state.error || "")
      if (!root.demoMode && root.service && result.rejected.length > 0)
        root.service.discardStages(result.rejected)
      root.focusComposer()
    }
  }

  Timer {
    id: copiedTimer
    interval: 1600
    repeat: false
    onTriggered: root.copiedVisible = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(root.desiredHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || composer.activeFocus
        || root.clearConfirmOpen
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
        else if (dx !== 0 && root.viewMode === "chats") root.switchPanel(dx)
      }
      onActivateRequested: root.activateSelection()
      onCloseRequested: {
        if (root.viewMode === "conversation" && root.voiceForCurrentChat
            && root.service && (root.service.voiceState === "recording"
                || root.service.voiceState === "preparing"))
          root.service.stopVoiceRecording()
        else if (root.viewMode === "conversation") root.backToChats()
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.viewMode === "chats") root.switchPanel(direction)
        else root.focusComposer()
      }
      onTextKey: function(text) {
        if (text === "/") root.focusSearch()
        else if (text === "r" || text === "R") root.refresh()
        else if (text === "o" || text === "O") root.openFullApp()
        else if (text === "i" || text === "I") root.focusComposer()
      }

      Shortcut {
        sequence: "Ctrl+Shift+V"
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.opened && root.viewMode === "conversation"
        onActivated: root.toggleVoiceRecording()
      }

      Item {
        anchors.fill: parent

        Column {
          visible: root.viewMode === "chats"
          anchors.fill: parent
          spacing: Style.space(8)

          // "Chats", the unread count (click: only unread; right-click:
          // clear the badges), and the actions: clear, new chat, full app.
          Item {
            id: dropdownHeader
            width: parent.width
            height: Style.space(40)

            // The brand mark stays on every OmaWhatsApp surface.
            Text {
              textFormat: Text.PlainText
              id: whatsappMark
              objectName: "dropdownBrandMark"
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              text: "󰖣"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Text {
              textFormat: Text.PlainText
              id: dropdownTitle
              anchors.left: whatsappMark.right
              anchors.leftMargin: Style.space(7)
              anchors.verticalCenter: parent.verticalCenter
              text: "Chats"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.weight: Font.Bold
            }

            Rectangle {
              id: notificationBadge
              objectName: "notificationBadge"
              visible: root.notificationCount > 0 || root.unreadOnly
              anchors.left: dropdownTitle.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: unreadHeader.implicitWidth + Style.space(14)
              height: Style.space(22)
              radius: height / 2
              color: root.unreadOnly ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
                : notificationBadgeHover.hovered ? root.selected : "transparent"
              border.width: root.unreadOnly ? 1 : 0
              border.color: root.accent
              Text {
                textFormat: Text.PlainText
                id: unreadHeader
                objectName: "dropdownUnreadCount"
                anchors.centerIn: parent
                text: (root.notificationCount > 99 ? "99+" : String(root.notificationCount)) + " unread"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              HoverHandler {
                id: notificationBadgeHover
                cursorShape: Qt.PointingHandCursor
              }
              TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: function(eventPoint, button) { root.badgeTapped(button) }
              }
              PanelToolTip {
                visible: notificationBadgeHover.hovered
                text: (root.unreadOnly ? "Show all chats" : "Show only unread chats")
                  + " · right-click clears the badge"
              }
            }

            Text {
              textFormat: Text.PlainText
              objectName: "dropdownSyncStatus"
              visible: !notificationBadge.visible && text !== ""
              anchors.left: dropdownTitle.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.offline ? "offline archive" : (root.ready ? "" : "reconnecting")
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Rectangle {
                objectName: "dropdownClearBadges"
                visible: root.notificationCount > 0
                anchors.verticalCenter: parent.verticalCenter
                width: clearBadgesLabel.implicitWidth + Style.space(16)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: clearBadgesHover.hovered ? root.selected : "transparent"
                Text {
                  textFormat: Text.PlainText
                  id: clearBadgesLabel
                  anchors.centerIn: parent
                  text: "Clear"
                  color: clearBadgesHover.hovered ? root.foreground : root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                HoverHandler { id: clearBadgesHover; cursorShape: Qt.PointingHandCursor }
                PanelToolTip {
                  visible: clearBadgesHover.hovered
                  text: "Clear the badges · the chats stay unread"
                }
                TapHandler { onTapped: root.requestClearNotifications() }
              }

              PanelActionButton {
                id: newChatButton
                objectName: "dropdownNewChatButton"
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󱐒"
                tooltipText: "New chat · opens the full app"
                foreground: root.muted
                hoverColor: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                size: Style.space(28)
                onClicked: root.openNewChat()
              }

              Rectangle {
                objectName: "dropdownOpenFullButton"
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(28)
                height: width
                radius: Style.cornerRadius
                color: openAllHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : root.selected
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "󰏌"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                HoverHandler { id: openAllHover; cursorShape: Qt.PointingHandCursor }
                PanelToolTip { visible: openAllHover.hovered; text: "Open the full app · O" }
                TapHandler { onTapped: root.openFullApp() }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(32)
            HoverHandler { id: searchBoxHover }
            PanelToolTip {
              delay: 900
              visible: searchBoxHover.hovered && !searchField.activeFocus
              text: "/ to search · J/K or ↑/↓ to move · Enter opens the chat"
            }
            radius: Style.cornerRadius
            color: root.subtle
            border.width: searchField.activeFocus ? 1 : 0
            border.color: root.accent
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "󰍉"
              color: searchField.activeFocus ? root.accent : root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            TextField {
              id: searchField
              anchors.left: parent.left
              anchors.leftMargin: Style.space(30)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              text: root.searchText
              onTextChanged: root.searchText = text
              placeholderText: "Search"
              color: root.foreground
              placeholderTextColor: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              background: null
              selectByMouse: true
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  if (text !== "") text = ""
                  else { focus = false; keyCatcher.forceActiveFocus() }
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  focus = false
                  keyCatcher.forceActiveFocus()
                  root.moveSelection(1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  focus = false
                  keyCatcher.forceActiveFocus()
                  root.activateSelection()
                  event.accepted = true
                }
              }
            }
          }

          AccountSwitcher {
            id: accountSwitcher
            width: parent.width
            accounts: root.accountEntries
            selectedScope: root.accountScope
            foreground: root.foreground
            background: root.background
            accent: root.accent
            muted: root.muted
            urgent: root.urgent
            fontFamily: root.fontFamily
            linkBusy: !!root.service && !!root.service.accountOperations
              && root.service.accountOperations.linkBusy
            avatarBusy: !!root.service && !!root.service.accountOperations
              && root.service.accountOperations.avatarBusy
            statusMessage: root.service && root.service.accountOperations
              ? root.service.accountOperations.statusMessage : ""
            allowAccountLink: !root.demoMode && !!root.service
            onScopeSelected: function(scope) {
              root.accountScope = scope
              root.selectedIndex = 0
            }
            onLinkRequested: function(name) {
              if (root.service) root.service.accountOperations.linkAccount(name)
            }
          }

          LinkStatus {
            id: railSyncStatus
            objectName: "railSyncStatus"
            readonly property var account: root.accountEntries.find(function(entry) {
              return String(entry.account || "") === String(root.accountScope || root.currentAccount() || (root.service ? root.service.defaultAccountName : ""))
            }) || ({})
            width: parent.width
            state: root.demoMode ? "connected"
              : String((root.service && root.service.closed && account.connection_state !== "relink-required" && account.connection_state !== "unlinked" ? "closed" : account.connection_state) || (root.accountStatusReady
                ? (root.service.closed ? "closed" : root.service.offlineMode ? "offline" : root.service.syncActive ? "connecting" : "stopped") : "unknown"))
            pauseReason: root.service && String(account.account || "") === String(root.service.statusAccount || "")
              ? String(root.service.syncPauseReason || "") : ""
            foreground: root.foreground
            accent: root.accent
            dim: root.muted
            urgent: root.urgent
            fontFamily: root.fontFamily
            demo: root.demoMode
            busy: !!root.service && !!root.service.accountOperations && root.service.accountOperations.linkBusy
            actionEnabled: !!root.service && !root.service.controlWriting
            onActionRequested: {
              var name = String(account.account || root.currentAccount())
              if (expired) {
                if (account.main === true) root.service.accountOperations.linkMainAccount(name)
                else root.service.accountOperations.linkAccount(name)
              } else if (root.service.closed) root.service.launchApp()
              else root.service.setOnline(true, name)
            }
          }

          AccountReadiness {
            width: parent.width
            accounts: root.demoMode || !root.service ? [] : root.service.accounts
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            compact: true
          }

          Item {
            width: parent.width
            height: Math.max(Style.space(120),
              Math.min(root.chatListHeight, keyCatcher.height - root.chatChromeHeight
                - root.accountReadinessHeight))

            ListView {
              id: chatList
              anchors.fill: parent
              clip: true
              model: root.filteredChats
              currentIndex: root.selectedIndex
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              // Name and time, then the preview; the badge at the end, or on
              // hover the two quick actions: mark read and reply here.
              delegate: Item {
                id: chatRow
                objectName: "dropdownChatRow"
                required property var modelData
                required property int index
                width: chatList.width
                height: root.rowHeight
                readonly property bool current: chatRow.index === root.selectedIndex
                readonly property bool hovered: rowHover.hovered
                readonly property int unreadCount: Number(chatRow.modelData.notification_unread || 0)
                readonly property bool typing: root.chatTyping(chatRow.modelData)
                readonly property var preview: AccountModel.previewParts(chatRow.modelData)
                readonly property string tick: !typing && chatRow.modelData.last_from_me
                  ? AccountModel.deliveryGlyph(chatRow.modelData.last_status) : ""
                readonly property real contentX: avatar.x + avatar.width + Style.space(10)
                readonly property real lineTop: (height - dropdownChatName.implicitHeight
                  - Style.space(2) - rowPreview.implicitHeight) / 2
                Rectangle {
                  anchors.fill: parent
                  anchors.topMargin: 1
                  anchors.bottomMargin: 1
                  radius: Style.cornerRadius + 2
                  color: chatRow.current || chatRow.hovered ? root.selected : "transparent"
                }
                Rectangle {
                  objectName: "dropdownAccountStripe"
                  readonly property int mark: root.accountMark(chatRow.modelData)
                  visible: mark >= 0
                  x: Style.space(2)
                  width: 3
                  height: Math.round(parent.height * 0.5)
                  radius: 1.5
                  anchors.verticalCenter: parent.verticalCenter
                  color: Tint.accountColor(mark, root.accent)
                }
                ChatAvatar {
                  showPhoto: root.showAvatars
                  id: avatar
                  x: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(32)
                  height: width
                  chat: chatRow.modelData
                  selected: chatRow.current
                  foreground: root.foreground
                  background: root.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                }
                Text {
                  textFormat: Text.PlainText
                  id: dropdownChatName
                  objectName: "dropdownChatName"
                  x: chatRow.contentX
                  y: chatRow.lineTop
                  width: Math.max(0, rowTime.x - Style.space(8) - x)
                  text: String(chatRow.modelData.name || "WhatsApp chat")
                  elide: Text.ElideRight
                  maximumLineCount: 1
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.weight: chatRow.unreadCount > 0 ? Font.Bold : Font.Medium
                }
                Text {
                  textFormat: Text.PlainText
                  id: rowTime
                  objectName: "dropdownChatTime"
                  x: rowTrailing.x + rowTrailing.width - implicitWidth
                  y: chatRow.lineTop + (dropdownChatName.implicitHeight - implicitHeight) / 2
                  text: root.timeLabel(chatRow.modelData.timestamp)
                  color: chatRow.unreadCount > 0 ? root.accent : root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Row {
                  id: rowPreviewLine
                  x: chatRow.contentX
                  y: chatRow.lineTop + dropdownChatName.implicitHeight + Style.space(2)
                  width: Math.max(0, rowTrailing.x - Style.space(8) - x)
                  spacing: Style.space(4)
                  Text {
                    textFormat: Text.PlainText
                    objectName: "dropdownChatTick"
                    visible: text !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: chatRow.tick
                    color: chatRow.modelData.last_status === "read" || chatRow.modelData.last_status === "played"
                      ? root.accent : root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    textFormat: Text.PlainText
                    objectName: "dropdownChatKind"
                    visible: text !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: chatRow.typing ? "" : AccountModel.previewKindGlyph(chatRow.preview.kind)
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    textFormat: Text.PlainText
                    id: rowPreview
                    objectName: "dropdownChatPreview"
                    width: rowPreviewLine.width
                      - (chatRow.tick !== "" ? implicitHeight + rowPreviewLine.spacing : 0)
                      - (!chatRow.typing && chatRow.preview.kind !== "" ? implicitHeight + rowPreviewLine.spacing : 0)
                    text: chatRow.typing ? "typing…"
                      : AccountModel.previewPrefix(chatRow.modelData, root.multiAccount)
                        + (chatRow.modelData.last_from_me && chatRow.tick === "" ? "You: " : "")
                        + AccountModel.previewSender(chatRow.modelData)
                        + (FormatModel.plain(chatRow.preview.text) || "No local messages yet")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: chatRow.typing ? root.accent : chatRow.unreadCount > 0 ? root.foreground : root.muted
                    opacity: chatRow.unreadCount > 0 && !chatRow.typing ? 0.86 : 1
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                Row {
                  id: rowTrailing
                  z: 2
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  y: rowPreviewLine.y + (rowPreviewLine.height - height) / 2
                  height: Style.space(24)
                  spacing: Style.space(4)
                  Row {
                    id: dropdownChatFlags
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !chatRow.hovered
                    spacing: Style.space(4)
                    Text {
                      textFormat: Text.PlainText
                      visible: chatRow.modelData.muted === true
                      text: "󰪑"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: chatRow.modelData.pinned === true
                      text: "󰐃"
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  Rectangle {
                    objectName: "dropdownMentionBadge"
                    visible: chatRow.modelData.mentioned === true && chatRow.unreadCount > 0 && !chatRow.hovered
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.space(18)
                    width: height
                    radius: height / 2
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: "@"
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - 1
                      font.weight: Font.Bold
                    }
                  }
                  Rectangle {
                    objectName: "dropdownChatBadge"
                    visible: chatRow.unreadCount > 0 && !chatRow.hovered
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.space(18)
                    width: Math.max(height, rowUnread.implicitWidth + Style.space(9))
                    radius: height / 2
                    color: root.accent
                    Text {
                      textFormat: Text.PlainText
                      id: rowUnread
                      anchors.centerIn: parent
                      text: chatRow.unreadCount > 99 ? "99+" : String(chatRow.unreadCount)
                      color: root.background
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - 1
                      font.weight: Font.Bold
                    }
                  }
                  PanelActionButton {
                    objectName: "dropdownChatReadToggle"
                    visible: chatRow.hovered
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: Number(chatRow.modelData.unread || 0) > 0 ? "󰄬" : "󱥂"
                    tooltipText: Number(chatRow.modelData.unread || 0) > 0 ? "Mark as read" : "Mark as unread"
                    foreground: root.muted
                    hoverColor: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    size: Style.space(24)
                    onClicked: root.toggleChatRead(chatRow.modelData)
                  }
                  Rectangle {
                    objectName: "dropdownChatReply"
                    visible: chatRow.hovered
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(24)
                    height: width
                    radius: Style.cornerRadius
                    color: replyHereHover.hovered ? Qt.lighter(root.accent, 1.12) : root.accent
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: "󰑚"
                      color: root.background
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    HoverHandler { id: replyHereHover; cursorShape: Qt.PointingHandCursor }
                    PanelToolTip { visible: replyHereHover.hovered; text: "Reply here · Enter" }
                    TapHandler {
                      onTapped: {
                        root.selectedIndex = chatRow.index
                        root.openConversation(chatRow.modelData)
                      }
                    }
                  }
                }
                HoverHandler { id: rowHover }
                TapHandler {
                  onTapped: {
                    root.selectedIndex = chatRow.index
                    root.openConversation(chatRow.modelData)
                  }
                }
              }
            }

            Column {
              visible: root.filteredChats.length === 0
              anchors.centerIn: parent
              spacing: Style.space(7)
              readonly property bool firstRun: !root.demoMode && !!root.service
                && root.service.needsOnboarding === true
              Text {
                textFormat: Text.PlainText
                objectName: "dropdownEmptyTitle"
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.firstRun ? "Link your WhatsApp to start"
                  : root.ready ? "No matching chats" : "OmaWhatsApp is reconnecting"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.firstRun ? "The full app shows a QR code for your phone"
                  : root.ready ? "Try a different search" : "Your local archive will appear here"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Rectangle {
                objectName: "dropdownSetUp"
                visible: parent.firstRun
                anchors.horizontalCenter: parent.horizontalCenter
                width: dropdownSetUpLabel.implicitWidth + Style.space(28)
                height: Style.space(34)
                radius: Style.cornerRadius + 2
                color: root.accent
                Text {
                  textFormat: Text.PlainText
                  id: dropdownSetUpLabel
                  anchors.centerIn: parent
                  text: "Set up"
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.Bold
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openFullApp() }
              }
            }
          }

          // Each key next to what it does; the owner found bare keys cryptic.
          Row {
            id: dropdownKeys
            objectName: "dropdownKeys"
            x: Style.space(4)
            height: Style.space(26)
            spacing: Style.space(14)
            Repeater {
              model: [{ key: "↑↓", label: "move" }, { key: "Enter", label: "reply" },
                { key: "O", label: "full app" }, { key: "Esc", label: "close" }]
              delegate: Row {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Text {
                  textFormat: Text.PlainText
                  text: modelData.key
                  color: root.foreground
                  opacity: 0.72
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                  font.weight: Font.Bold
                }
                Text {
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                }
              }
            }
          }
        }

        Item {
          visible: root.viewMode === "conversation"
          anchors.fill: parent

          Item {
            id: conversationHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Style.space(48)
            Rectangle {
              id: backButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(30)
              height: width
              radius: Style.cornerRadius
              color: backHover.hovered ? root.selected : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰅁"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: backHover }
              PanelToolTip { visible: backHover.hovered; text: "Back to chats · Esc" }
              TapHandler { onTapped: root.backToChats() }
            }
            ChatAvatar {
              showPhoto: root.showAvatars
              id: conversationAvatar
              anchors.left: backButton.right
              anchors.leftMargin: Style.space(7)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: width
              chat: root.currentChat || ({})
              selected: true
              foreground: root.foreground
              background: root.background
              accent: root.accent
              fontFamily: root.fontFamily
            }
            Column {
              anchors.left: conversationAvatar.right
              anchors.leftMargin: Style.space(9)
              anchors.right: fullButton.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.currentChat ? String(root.currentChat.name || "WhatsApp chat") : "WhatsApp chat"
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.Bold
              }
              Text {
                textFormat: Text.PlainText
                objectName: "dropdownConversationStatus"
                text: root.offline ? "offline · viewing local archive"
                  : root.presenceLine.text !== "" ? root.presenceLine.text
                  : (root.sending ? "sending…" : "")
                visible: text !== ""
                color: root.presenceLine.live && !root.offline ? root.accent : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Rectangle {
              id: fullButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(30)
              height: width
              radius: Style.cornerRadius
              color: fullHover.hovered ? root.selected : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰏌"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: fullHover }
              PanelToolTip { visible: fullHover.hovered; text: "Open in the full app · O" }
              TapHandler { onTapped: root.openFullApp() }
            }
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: root.subtle
            }
          }

          ListView {
            id: messageList
            anchors.top: conversationHeader.bottom
            anchors.topMargin: Style.space(8)
            anchors.bottom: composerCard.top
            anchors.bottomMargin: Style.space(8)
            anchors.left: parent.left
            anchors.right: parent.right
            clip: true
            // Gaps come from each row: tight inside one person's run.
            spacing: 0
            model: root.sourceMessages
            currentIndex: root.messageIndex
            verticalLayoutDirection: ListView.BottomToTop
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            onContentYChanged: root.showFloatingDay()
            delegate: Item {
              id: compactRow
              required property var modelData
              required property int index
              width: messageList.width
              z: compactMessage.raised ? 3 : 0
              readonly property bool startsDay: TimeFormat.startsDay(root.sourceMessages, index)
              readonly property bool joinsAbove: !startsDay && index !== root.unreadDividerIndex
                && AccountModel.sameRun(root.sourceMessages[index + 1], modelData)
              readonly property bool joinsBelow: index > 0
                && !TimeFormat.startsDay(root.sourceMessages, index - 1)
                && index - 1 !== root.unreadDividerIndex
                && AccountModel.sameRun(modelData, root.sourceMessages[index - 1])
              height: compactGap.height + compactDay.height + compactUnread.height + compactMessage.height
              Item {
                id: compactGap
                width: parent.width
                height: compactRow.joinsAbove ? Style.space(2) : Style.space(7)
              }
              Item {
                id: compactDay
                objectName: "dayHeader"
                anchors.top: compactGap.bottom
                visible: compactRow.startsDay
                width: parent.width
                height: visible ? Style.space(34) : 0
                Rectangle {
                  anchors.centerIn: parent
                  width: compactDayLabel.implicitWidth + Style.space(18)
                  height: Style.space(22)
                  radius: height / 2
                  color: root.subtle
                  Text {
                    textFormat: Text.PlainText
                    id: compactDayLabel
                    anchors.centerIn: parent
                    text: TimeFormat.dayLabel(compactRow.modelData.timestamp)
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
              // Where the unread messages start: "3 new" between two hairlines.
              Item {
                id: compactUnread
                objectName: "unreadDivider"
                anchors.top: compactDay.bottom
                visible: compactRow.index === root.unreadDividerIndex
                width: parent.width
                height: visible ? Style.space(26) : 0
                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.right: compactUnreadLabel.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  height: 1
                  color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                }
                Text {
                  textFormat: Text.PlainText
                  id: compactUnreadLabel
                  anchors.centerIn: parent
                  text: root.unreadMarker.count + " new"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Rectangle {
                  anchors.left: compactUnreadLabel.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  height: 1
                  color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                }
              }
              MessageBubble {
                id: compactMessage
                anchors.top: compactUnread.bottom
                timeFormat: root.timeFormat
                width: parent.width
                message: modelData
                foreground: root.foreground
                background: root.background
                accent: root.accent
                dim: root.muted
                dimmer: root.muted
                fontFamily: root.fontFamily
                groupChat: root.currentChat && root.currentChat.kind === "group"
                joinsAbove: compactRow.joinsAbove
                joinsBelow: compactRow.joinsBelow
                selected: index === root.messageIndex
                narrow: true
                surfaceActive: root.opened && root.viewMode === "conversation"
                activePlaybackId: root.activePlaybackId
                sharedAudio: dropdownAudio
                audioRate: root.service ? root.service.audioRate : 1
                onAudioRateRequested: function(rate) { if (root.service) root.service.audioRate = rate }
                busyMedia: root.sending
                  && root.service.mediaDownloadId === String(modelData.id || "")
                onSelectedRequested: {
                  root.messageIndex = index
                  keyCatcher.forceActiveFocus()
                }
                onOpenMediaRequested: root.openFullApp()
                onPlaybackRequested: function(messageId) {
                  root.requestPlayback(messageId)
                }
                onDownloadMediaRequested: if (!root.demoMode && root.service)
                  root.service.downloadMedia(root.currentChatRef(), modelData, "dropdown")
                onReplyRequested: {
                  root.replyTarget = modelData
                  root.focusComposer()
                }
                onReactionRequested: function(emoji) {
                  if (!root.demoMode && root.service)
                    root.service.reactTo(
                      root.currentChatRef(), modelData, emoji, "dropdown")
                }
                onEditRequested: root.openFullApp()
                onDeleteRequested: root.openFullApp()
                onPendingSendRequested: function(action) {
                  if (root.service) root.service.resolvePendingSend(modelData.id, action)
                }
                onForwardRequested: root.forwardInFullApp(modelData)
                onCopyRequested: function(text) { root.copyText(text) }
                onPollVoteRequested: function(options) {
                  if (!root.demoMode && root.service)
                    root.service.votePoll(root.currentChatRef(), modelData, options, "dropdown")
                }
                onContactChatRequested: function(card) { root.openContactChat(card, modelData) }
                onOptionRequested: function(optionIndex) {
                  if (!root.demoMode && root.service)
                    root.service.selectOption(
                      root.currentChatRef(), modelData, optionIndex, "dropdown")
                }
              }
            }
            Text {
              textFormat: Text.PlainText
              visible: root.sourceMessages.length === 0
              anchors.centerIn: parent
              text: !root.demoMode && root.service && root.service.loadingMessages
                ? "Loading local messages…" : "No local messages in this chat"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Timer { id: compactDayHold; interval: 1400; repeat: false }
          Rectangle {
            id: compactFloatingDay
            objectName: "floatingDay"
            z: 18
            readonly property bool shown: root.floatingDayLabel !== "" && compactJump.away
              && (messageList.moving || compactDayHold.running)
            opacity: shown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            anchors.top: messageList.top
            anchors.topMargin: Style.space(4)
            anchors.horizontalCenter: messageList.horizontalCenter
            width: compactFloatingDayText.implicitWidth + Style.space(20)
            height: Style.space(24)
            radius: height / 2
            color: Qt.tint(root.background, Qt.rgba(root.foreground.r, root.foreground.g,
              root.foreground.b, 0.12))
            Text {
              textFormat: Text.PlainText
              id: compactFloatingDayText
              anchors.centerIn: parent
              text: root.floatingDayLabel
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Rectangle {
            objectName: "jumpToLatestBacking"
            z: 19
            visible: compactJump.visible
            anchors.fill: compactJump
            radius: Style.cornerRadius
            color: root.background
          }
          PanelActionButton {
            id: compactJump
            objectName: "jumpToLatest"
            z: 20
            // Measured on the newest message itself, as in the full app.
            readonly property bool away: root.newestMessageOffset(messageList.contentY) > Style.space(48)
            visible: away
            anchors.right: messageList.right
            anchors.bottom: messageList.bottom
            anchors.margins: Style.space(6)
            size: Style.space(32)
            iconText: "󰁅"
            tooltipText: "Jump to latest"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            bordered: true
            onClicked: root.scrollToNewest()
          }

          Rectangle {
            id: composerCard
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: composerColumn.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: "transparent"
            Column {
              id: composerColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(8)
              spacing: Style.space(6)
              Rectangle {
                visible: root.replyTarget !== null
                width: parent.width
                height: visible ? Style.space(34) : 0
                radius: Style.cornerRadius
                color: root.selected
                Text {
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(9)
                  anchors.right: cancelReply.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Replying to " + String(root.replyTarget && root.replyTarget.sender || "message")
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  textFormat: Text.PlainText
                  id: cancelReply
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(9)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "×"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  TapHandler { onTapped: root.replyTarget = null }
                  HoverHandler { id: cancelReplyHover }
                  PanelToolTip { visible: cancelReplyHover.hovered; text: "Cancel reply" }
                }
              }
              Row {
                visible: root.pendingAttachments.length > 0
                width: parent.width
                height: visible ? Style.space(30) : 0
                spacing: Style.space(5)
                Repeater {
                  model: root.pendingAttachments
                  delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: Math.min(Style.space(150), attachmentLabel.implicitWidth + Style.space(28))
                    height: Style.space(28)
                    radius: Style.cornerRadius
                    color: root.selected
                    Text {
                      textFormat: Text.PlainText
                      id: attachmentLabel
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(7)
                      anchors.right: removeFile.left
                      anchors.rightMargin: Style.space(5)
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.attachmentName(modelData)
                      elide: Text.ElideMiddle
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      textFormat: Text.PlainText
                      id: removeFile
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(7)
                      anchors.verticalCenter: parent.verticalCenter
                      text: "×"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      TapHandler {
                        enabled: !root.sending
                        onTapped: root.removeAttachment(index)
                      }
                      HoverHandler { id: removeFileHover }
                      PanelToolTip { visible: removeFileHover.hovered; text: "Remove attachment" }
                    }
                  }
                }
              }
              Item {
                objectName: "dropdownSignature"
                visible: root.signatureActive && !root.voiceForCurrentChat
                width: parent.width
                height: visible ? Style.space(18) : 0
                Text {
                  textFormat: Text.PlainText
                  id: dropdownSignatureLabel
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.signatureSkipped ? "󰷼  Without your signature this time"
                    : "󰷼  Signed as " + root.composerSignature.name
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                }
                Text {
                  textFormat: Text.PlainText
                  objectName: "dropdownSignatureToggle"
                  anchors.left: dropdownSignatureLabel.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.signatureSkipped ? "Sign it" : "Skip once"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                  HoverHandler { cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: root.signatureSkipped = !root.signatureSkipped }
                }
              }
              Item {
                id: composerRowItem
                objectName: "composerRowItem"
                visible: !root.voiceForCurrentChat
                width: parent.width
                readonly property int singleLineHeight: Math.max(1, Math.ceil(composerMetrics.lineSpacing))
                readonly property int visibleLines: Math.max(1, Math.min(composer.lineCount, root.composerMaxLines))
                // Same rules as the full app: one control height, one bottom edge.
                readonly property real controlSize: Style.space(36)
                readonly property real fieldPadding: Math.max(Style.space(5),
                  Math.floor((controlSize - singleLineHeight) / 2))
                readonly property real baseHeight: controlSize
                height: !root.voiceForCurrentChat
                  ? Math.max(controlSize, Math.ceil(visibleLines * singleLineHeight) + fieldPadding * 2) : 0

                PanelActionButton {
                  id: filePickerButton
                  objectName: "composerAttachButton"
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  size: composerRowItem.controlSize
                  iconText: "󰏢"
                  tooltipText: "Attach files · Ctrl+O"
                  foreground: root.muted
                  hoverColor: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.body
                  onClicked: root.openFilePicker()
                }
                PanelActionButton {
                  id: emojiButton
                  objectName: "composerEmojiButton"
                  anchors.left: filePickerButton.right
                  anchors.bottom: parent.bottom
                  size: composerRowItem.controlSize
                  iconText: "󰇵"
                  tooltipText: dropdownEmojiPicker.opened ? "" : "Emoji"
                  foreground: dropdownEmojiPicker.opened ? root.accent : root.muted
                  hoverColor: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.body
                  onClicked: dropdownEmojiPicker.opened ? dropdownEmojiPicker.close() : dropdownEmojiPicker.open()

                  EmojiPicker {
                    id: dropdownEmojiPicker
                    x: 0
                    y: -height - Style.space(8)
                    target: composer
                    foreground: root.foreground
                    surface: root.background
                    accent: root.accent
                    muted: root.muted
                    fontFamily: root.fontFamily
                    stickersEnabled: !root.demoMode && !!root.service
                    stickers: root.service && root.service.stickers ? root.service.stickers : []
                    stickersLoading: !!root.service && root.service.stickersLoading === true
                    onStickersOpened: if (root.service) root.service.refreshStickers(true)
                    onStickerPicked: function(path) {
                      if (root.demoMode || !root.service) return
                      var replyId = root.replyTarget ? String(root.replyTarget.id || "") : ""
                      if (root.service.sendSticker(root.currentChatRef(), path, replyId, "dropdown"))
                        root.replyTarget = null
                    }
                  }
                }
                Rectangle {
                  id: sendButton
                  objectName: "composerSendButton"
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  width: composerRowItem.controlSize
                  height: width
                  radius: width / 2
                  // Only files wait for the running action; text queues at once.
                  readonly property bool busy: root.sending && !root.sendQueued
                    && root.pendingAttachments.length > 0
                  color: busy ? root.subtle : root.accent
                  opacity: busy ? 0.5 : 1
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.sendQueued ? "󰔟" : sendButton.busy ? "…"
                      : (String(composer.text || "").trim() !== ""
                          || root.pendingAttachments.length > 0 ? "󰒊" : "󰍬")
                    color: sendButton.busy ? root.muted : root.background
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  HoverHandler { id: sendHover; cursorShape: Qt.PointingHandCursor }
                  PanelToolTip {
                    visible: sendHover.hovered && (!sendButton.busy || root.sendQueued)
                    text: root.sendQueued ? "Sends as soon as the current WhatsApp action finishes"
                      : String(composer.text || "").trim() !== "" || root.pendingAttachments.length > 0
                      ? (root.enterSends ? "Send · Enter" : "Send · Ctrl+Enter")
                      : "Record a voice note · Ctrl+Shift+V"
                  }
                  TapHandler {
                    onTapped: {
                      if (String(composer.text || "").trim() !== ""
                          || root.pendingAttachments.length > 0) root.sendDraft()
                      else if (!root.sending) root.toggleVoiceRecording()
                    }
                  }
                }
                Rectangle {
                  id: composerFieldSurface
                  objectName: "composerFieldSurface"
                  anchors.left: emojiButton.right
                  anchors.leftMargin: Style.space(6)
                  anchors.right: sendButton.left
                  anchors.rightMargin: Style.space(8)
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  radius: Style.cornerRadius + 2
                  color: root.subtle
                  border.width: 1
                  border.color: composer.activeFocus
                    ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.70)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                  HoverHandler { id: composerFieldHover }
                  PanelToolTip {
                    delay: 900
                    visible: composerFieldHover.hovered && !composer.activeFocus
                    text: root.composerHint
                  }
                  // Formatting: a bar over any selection, and the right-click menu.
                  FormatBar {
                    id: dropdownFormatBar
                    editor: composer
                    anchorItem: composerFieldSurface
                    enabledHere: !root.offline
                    foreground: root.foreground
                    surface: root.background
                    accent: root.accent
                    muted: root.muted
                    fontFamily: root.fontFamily
                    onChosen: function(kind) { root.applyFormat(kind) }
                  }
                  FormatMenu {
                    id: dropdownFormatMenu
                    editActions: true
                    hasSelection: composer.selectedText !== ""
                    foreground: root.foreground
                    surface: root.background
                    accent: root.accent
                    muted: root.muted
                    fontFamily: root.fontFamily
                    onChosen: function(kind) { root.composerMenuAction(kind) }
                  }
                }
                Flickable {
                  id: composerFlickable
                  objectName: "composerFlickable"
                  anchors.left: composerFieldSurface.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: composerFieldSurface.right
                  anchors.rightMargin: Style.space(4)
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.topMargin: composerRowItem.fieldPadding
                  anchors.bottomMargin: composerRowItem.fieldPadding
                  contentWidth: width
                  contentHeight: Math.max(height, composer.contentHeight)
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  onHeightChanged: Qt.callLater(function() {
                    composerFlickable.ensureVisible(composer.cursorRectangle)
                  })

                  ScrollBar.vertical: ScrollBar {
                    id: composerScrollBar
                    objectName: "composerScrollBar"
                    policy: composerFlickable.contentHeight > composerFlickable.height + 0.5
                      ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    width: Style.space(8)
                    contentItem: Rectangle {
                      implicitWidth: Style.space(4)
                      radius: width / 2
                      color: composerScrollBar.pressed ? root.accent
                        : (composerScrollBar.hovered ? root.accent
                           : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35))
                    }
                  }

                  function ensureVisible(r) {
                    if (contentY >= r.y)
                      contentY = r.y
                    else if (contentY + height <= r.y + r.height)
                      contentY = r.y + r.height - height
                  }

                  TextEdit {
                    id: composer
                    objectName: "composerInput"
                    width: composerFlickable.width - Style.space(12)
                    height: Math.max(contentHeight, composerFlickable.height)
                    color: root.foreground
                    selectionColor: root.accent
                    selectedTextColor: root.background
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    selectByMouse: true
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    onTextChanged: if (text === "") root.composerEmptied()
                    readOnly: root.offline
                    onCursorRectangleChanged: composerFlickable.ensureVisible(cursorRectangle)
                    TapHandler {
                      acceptedButtons: Qt.RightButton
                      enabled: !root.offline
                      onTapped: function(eventPoint) {
                        root.openComposerMenu(eventPoint.position.x, eventPoint.position.y)
                      }
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: !composer.text && !composer.inputMethodComposing
                      anchors.left: parent.left
                      anchors.top: parent.top
                      text: root.offline ? "Offline archive is read-only" : "Message"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Keys.onPressed: function(event) {
                      root.noteComposerKey(event)
                      if ((event.modifiers & Qt.ControlModifier)
                          && (event.modifiers & Qt.ShiftModifier)
                          && event.key === Qt.Key_V) {
                        root.toggleVoiceRecording()
                        event.accepted = true
                      } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                        root.pasteClipboard()
                        event.accepted = true
                      } else if ((event.modifiers & Qt.ControlModifier)
                                 && !(event.modifiers & Qt.ShiftModifier)
                                 && (event.key === Qt.Key_B || event.key === Qt.Key_I)) {
                        root.applyFormat(event.key === Qt.Key_B ? "bold" : "italic")
                        event.accepted = true
                      } else if ((event.modifiers & Qt.ControlModifier)
                                 && (event.modifiers & Qt.ShiftModifier)
                                 && (event.key === Qt.Key_X || event.key === Qt.Key_M)) {
                        root.applyFormat(event.key === Qt.Key_X ? "strike" : "mono")
                        event.accepted = true
                      } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_O) {
                        root.openFilePicker()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Escape) {
                        if (root.replyTarget) root.replyTarget = null
                        else {
                          focus = false
                          keyCatcher.forceActiveFocus()
                        }
                        event.accepted = true
                      } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                 && (root.enterSends
                                   ? !(event.modifiers & Qt.ShiftModifier)
                                   : !!(event.modifiers & Qt.ControlModifier))) {
                        root.sendDraft()
                        event.accepted = true
                      }
                    }
                  }
                }
              }
              Text {
                textFormat: Text.PlainText
                objectName: "dropdownComposerHint"
                visible: !root.voiceForCurrentChat && !root.offline && root.errorText === ""
                x: composerFieldSurface.x + Style.space(2)
                width: parent.width - x
                text: root.composerHint + " · Esc goes back"
                elide: Text.ElideRight
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption - 1
              }
              VoiceComposer {
                width: parent.width
                height: visible ? implicitHeight : 0
                service: root.service
                owner: "dropdown"
                account: root.currentAccount()
                jid: root.currentJid()
                offline: root.offline
                foreground: root.foreground
                background: root.background
                accent: root.accent
                urgent: root.urgent
                muted: root.muted
                fontFamily: root.fontFamily
                compact: true
              }
              Text {
                textFormat: Text.PlainText
                visible: root.errorText !== ""
                width: parent.width
                text: root.errorText
                elide: Text.ElideRight
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Rectangle {
            visible: root.copiedVisible
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: composerCard.top
            anchors.bottomMargin: Style.space(10)
            width: copiedLabel.implicitWidth + Style.space(24)
            height: Style.space(34)
            radius: Style.cornerRadius
            color: root.background
            border.width: 1
            border.color: root.accent
            Text {
              textFormat: Text.PlainText
              id: copiedLabel
              anchors.centerIn: parent
              text: "copied to clipboard"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
            }
          }

          Item {
            id: clearConfirmKeys
            anchors.fill: parent
            visible: root.clearConfirmOpen
            focus: visible
            z: 20
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (clearConfirm.handleKey(event)) event.accepted = true
            }

            ConfirmDialog {
              id: clearConfirm
              objectName: "clearNotificationsConfirm"
              anchors.fill: parent
              opened: root.clearConfirmOpen
              message: "Clear all notification badges? Messages stay unread and no read receipts are sent."
              confirmText: "Clear"
              background: root.background
              foreground: root.foreground
              selectedBackground: root.selected
              selectedText: root.accent
              fontFamily: root.fontFamily
              cornerRadius: Style.cornerRadius
              onCanceled: root.cancelClearNotifications()
              onConfirmed: root.confirmClearNotifications()
            }
          }
        }
      }
    }
  }
}
