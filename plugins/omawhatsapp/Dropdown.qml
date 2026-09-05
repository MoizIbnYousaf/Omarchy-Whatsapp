import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DropdownModel.js" as DropdownModel
import "AccountModel.js" as AccountModel
import "ComposerModel.js" as ComposerModel

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
  property var demoItems: [
    { id: "demo-message-1", text: "The bar dropdown can send now.", sender: "Alex", timestamp: 1787540400, from_me: false, media_type: "", mime_type: "", local_path: "", reactions: [] },
    { id: "demo-message-2", text: "Fast, local, and keyboard-first.", sender: "You", timestamp: 1787540100, from_me: true, media_type: "", mime_type: "", local_path: "", reactions: [{ emoji: "⚡", from_me: false }] },
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
  readonly property var demoChats: [
    { jid: "demo-team", name: "Design team", kind: "group", account: "work", account_label: "work", avatar_path: "__demo_avatar__", preview: "The compact client can send now", timestamp: 1787540400, unread: 3, notification_unread: 3, pinned: true },
    { jid: "demo-alex", name: "Alex", kind: "dm", account: "personal", account_label: "personal", avatar_path: "__demo_avatar__", preview: "Looks perfect — ship it", timestamp: 1787539800, unread: 1, notification_unread: 1, pinned: false },
    { jid: "demo-lab", name: "OmaWhatsApp Lab", kind: "group", account: "work", account_label: "work", avatar_path: "", preview: "Native, private, and instant", timestamp: 1787539200, unread: 0, notification_unread: 0, pinned: false }
  ]
  readonly property bool multiAccount: demoMode
    || (!!service && service.multiAccount === true)
  readonly property var sourceChats: demoMode
    ? demoChats : (service && Array.isArray(service.chats) ? service.chats : [])
  readonly property var accountEntries: demoMode
    ? [{ account: "work", label: "work" },
       { account: "personal", label: "personal" }]
    : (service && Array.isArray(service.accounts) ? service.accounts : [])
  readonly property var filteredChats: {
    var needle = String(searchText || "").trim().toLowerCase()
    var scope = AccountModel.normalizeScope(root.accountScope, root.accountEntries)
    return AccountModel.filterChats(root.sourceChats, scope, needle,
      Math.max(1, Number(maxRows || 7)))
  }
  readonly property bool serviceOnCurrentChat: !!service
    && AccountModel.sameRef(
      AccountModel.chatRef(service.selectedChatAccount, service.selectedChatJid),
      currentChatRef())
  readonly property var sourceMessages: demoMode
    ? demoItems : (serviceOnCurrentChat && Array.isArray(service.messages)
      ? service.messages : [])
  readonly property int rowHeight: Style.space(62)
  readonly property int chatListHeight: Math.max(2,
    Math.min(Math.max(2, maxRows), Math.max(2, filteredChats.length))) * rowHeight
  readonly property string accountReadinessSummary: AccountModel.unreadyAccountSummary(
    demoMode || !service ? [] : service.accounts)
  readonly property int accountReadinessHeight: accountReadinessSummary === ""
    ? 0 : Style.space(36)
  readonly property int chatChromeHeight:
    Style.space(48 + 8 + 40 + 8 + 8 + 8 + 42)
      + accountSwitcher.height
  readonly property int desiredHeight: viewMode === "conversation"
    ? Style.space(620) : chatChromeHeight
      + accountReadinessHeight + chatListHeight
  readonly property int notificationCount: demoMode
    ? (demoNotificationsCleared ? 0 : 4)
    : (service ? Number(service.notificationUnreadCount || 0) : 0)
  readonly property bool ready: demoMode || (service && service.railReady)
  readonly property bool accountStatusReady: demoMode || (!!service
    && service.statusReady
    && String(service.statusAccount || "") === currentAccount())
  readonly property bool offline: !demoMode && accountStatusReady
    && service.offlineMode
  readonly property bool sending: !demoMode && service && service.writing
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
    if (demoMode || !playbackCoordinator) {
      demoPlaybackId = String(messageId || "")
      return demoPlaybackId !== ""
    }
    return playbackCoordinator.acquire("dropdown", currentChatRef(), messageId)
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

  function openConversation(chat) {
    if (sending) return
    if (!chat || !chat.jid) return
    if (!demoMode && service) service.discardStages(pendingAttachments)
    stopPlayback()
    currentChat = chat
    viewMode = "conversation"
    messageIndex = 0
    replyTarget = null
    pendingAttachments = []
    errorText = ""
    if (!demoMode && service) service.selectChat(chat)
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

  function openFullApp() {
    if (sending) return
    var payload = DropdownModel.fullAppPayload(currentChat)
    if (!demoMode && service) service.discardStages(pendingAttachments)
    pendingAttachments = []
    close()
    fullAppRequested(payload)
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

  function pasteClipboard() {
    if (demoMode) {
      composer.insert(composer.cursorPosition, "pasted from clipboard")
      focusComposer()
      return
    }
    if (!service || sending) return
    service.pasteClipboard(currentChatRef(), "dropdown")
  }

  function localFileUrl(path) {
    return "file://" + String(path || "").split("/")
      .map(function(part) { return encodeURIComponent(part) }).join("/")
  }

  function openFilePicker() {
    var origin = currentChatRef()
    if (filePickerProcess.running || sending || origin.jid === "") return
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
    if (!service || sending || offline) return
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
          request.reply_id, "dropdown")
      : service.sendText(currentChatRef(), text,
          request.reply_id, request.mentions, "dropdown")
    if (started) {
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

  function timeLabel(value) {
    var seconds = Number(value || 0)
    if (!isFinite(seconds) || seconds <= 0) return ""
    var date = new Date(seconds * 1000)
    var today = new Date()
    if (date.toDateString() === today.toDateString()) return Qt.formatTime(date, "h:mm AP")
    var yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1)
    if (date.toDateString() === yesterday.toDateString()) return "Yesterday"
    return Qt.formatDate(date, "MMM d")
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
    function onWriteFailed(message, chatRef, details, owner) {
      if (!ComposerModel.ownsOperation(owner, "dropdown")) return
      var intent = root.pendingWriteIntent
      if (ComposerModel.validWriteIntent(intent)) {
        if (!ComposerModel.writeIntentMatches(intent, chatRef,
            details && details.kind)) return
      } else if (!AccountModel.sameRef(chatRef, root.currentChatRef())) return
      var kind = String(details && details.kind
        || (intent ? intent.kind : ""))
      if (ComposerModel.validWriteIntent(intent)) {
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

          Item {
            width: parent.width
            height: Style.space(48)

            Rectangle {
              id: whatsappMark
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
              height: width
              radius: width / 2
              color: root.selected
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰖣"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            Column {
              anchors.left: whatsappMark.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)
              Text {
                textFormat: Text.PlainText
                text: "OmaWhatsApp"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              Text {
                textFormat: Text.PlainText
                text: root.offline ? "offline archive"
                  : (root.ready ? "synced · local first" : "reconnecting")
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              id: notificationBadge
              visible: root.notificationCount > 0
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(Style.space(25), unreadHeader.implicitWidth + Style.space(10))
              height: Style.space(24)
              radius: height / 2
              color: root.accent
              opacity: notificationBadgeHover.hovered ? 0.82 : 1
              Text {
                textFormat: Text.PlainText
                id: unreadHeader
                anchors.centerIn: parent
                text: root.notificationCount > 99 ? "99+" : String(root.notificationCount)
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
              }
              HoverHandler {
                id: notificationBadgeHover
                cursorShape: Qt.PointingHandCursor
              }
              TapHandler { onTapped: root.requestClearNotifications() }
            }

            Rectangle {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: width
              radius: width / 2
              color: refreshHover.hovered ? root.selected : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰑐"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: refreshHover }
              TapHandler { onTapped: root.refresh() }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(40)
            radius: Style.cornerRadius
            color: root.subtle
            border.width: searchField.activeFocus ? 1 : 0
            border.color: root.accent
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(11)
              anchors.verticalCenter: parent.verticalCenter
              text: "󰍉"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            TextField {
              id: searchField
              anchors.left: parent.left
              anchors.leftMargin: Style.space(35)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              text: root.searchText
              onTextChanged: root.searchText = text
              placeholderText: "Search recent chats"
              color: root.foreground
              placeholderTextColor: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
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
            linkBusy: !!root.service && root.service.accountOperations.linkBusy
            avatarBusy: !!root.service && root.service.accountOperations.avatarBusy
            statusMessage: root.service
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

              delegate: Item {
                id: chatRow
                required property var modelData
                required property int index
                width: chatList.width
                height: root.rowHeight
                Rectangle {
                  anchors.fill: parent
                  anchors.margins: Style.space(2)
                  radius: Style.cornerRadius
                  color: chatRow.index === root.selectedIndex || rowHover.hovered
                    ? root.selected : "transparent"
                }
                ChatAvatar {
                  id: avatar
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(9)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(38)
                  height: width
                  chat: chatRow.modelData
                  selected: chatRow.index === root.selectedIndex
                  foreground: root.foreground
                  background: root.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                }
                Column {
                  anchors.left: avatar.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: rowMeta.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: String(chatRow.modelData.name || "WhatsApp chat")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.weight: Number(chatRow.modelData.notification_unread || 0) > 0
                      ? Font.DemiBold : Font.Normal
                  }
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: AccountModel.previewPrefix(chatRow.modelData, root.multiAccount)
                      + String(chatRow.modelData.preview || "No local messages yet")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                Column {
                  id: rowMeta
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)
                  Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    text: root.timeLabel(chatRow.modelData.timestamp)
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Rectangle {
                    visible: Number(chatRow.modelData.notification_unread || 0) > 0
                    anchors.right: parent.right
                    width: Math.max(Style.space(20), rowUnread.implicitWidth + Style.space(8))
                    height: Style.space(20)
                    radius: height / 2
                    color: root.accent
                    Text {
                      textFormat: Text.PlainText
                      id: rowUnread
                      anchors.centerIn: parent
                      text: Number(chatRow.modelData.notification_unread || 0) > 99
                        ? "99+" : String(Number(chatRow.modelData.notification_unread || 0))
                      color: root.background
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.weight: Font.DemiBold
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
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.ready ? "No matching chats" : "OmaWhatsApp is reconnecting"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
              }
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.ready ? "Try a different search" : "Your local archive will appear here"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(42)
            radius: Style.cornerRadius
            color: openAllHover.hovered ? root.selected : root.subtle
            border.width: 1
            border.color: root.selected
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(13)
              anchors.verticalCenter: parent.verticalCenter
              text: "Open full client"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: Style.space(13)
              anchors.verticalCenter: parent.verticalCenter
              text: "O  ·  J/K  ·  /  ·  Enter"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            HoverHandler { id: openAllHover }
            TapHandler { onTapped: root.openFullApp() }
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
              width: Style.space(32)
              height: width
              radius: width / 2
              color: backHover.hovered ? root.selected : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰁍"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: backHover }
              TapHandler { onTapped: root.backToChats() }
            }
            ChatAvatar {
              id: conversationAvatar
              anchors.left: backButton.right
              anchors.leftMargin: Style.space(7)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
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
                font.weight: Font.DemiBold
              }
              Text {
                textFormat: Text.PlainText
                text: root.offline ? "offline · viewing local archive"
                  : (root.sending ? "sending…" : "Enter sends · Shift+Enter adds a line")
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Rectangle {
              id: fullButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: width
              radius: width / 2
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
            spacing: Style.space(7)
            model: root.sourceMessages
            currentIndex: root.messageIndex
            verticalLayoutDirection: ListView.BottomToTop
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
              required property var modelData
              required property int index
              width: messageList.width
              height: compactMessage.height
              MessageBubble {
                id: compactMessage
                width: parent.width
                message: modelData
                foreground: root.foreground
                background: root.background
                accent: root.accent
                dim: root.muted
                dimmer: root.muted
                fontFamily: root.fontFamily
                groupChat: root.currentChat && root.currentChat.kind === "group"
                selected: index === root.messageIndex
                narrow: true
                surfaceActive: root.opened && root.viewMode === "conversation"
                activePlaybackId: root.activePlaybackId
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
                onForwardRequested: root.openFullApp()
                onCopyRequested: function(text) { root.copyText(text) }
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

          Rectangle {
            id: composerCard
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: composerColumn.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: root.subtle
            border.width: composer.activeFocus ? 1 : 0
            border.color: root.accent
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
                    }
                  }
                }
              }
              Row {
                visible: !root.voiceForCurrentChat
                width: parent.width
                height: visible ? implicitHeight : 0
                spacing: Style.space(7)
                Rectangle {
                  width: Style.space(34)
                  height: width
                  radius: width / 2
                  color: pasteHover.hovered ? root.selected : "transparent"
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "󰃦"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  HoverHandler { id: pasteHover }
                  TapHandler { onTapped: root.openFilePicker() }
                }
                Rectangle {
                  width: Style.space(34)
                  height: width
                  radius: width / 2
                  color: clipboardHover.hovered ? root.selected : "transparent"
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "󰅌"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  HoverHandler { id: clipboardHover }
                  TapHandler { onTapped: root.pasteClipboard() }
                }
                TextArea {
                  id: composer
                  width: parent.width - Style.space(123)
                  height: Math.max(Style.space(44), Math.min(implicitHeight, Style.space(96)))
                  placeholderText: root.offline ? "Offline archive is read-only" : "Message"
                  readOnly: root.offline || root.sending
                  color: root.foreground
                  placeholderTextColor: root.muted
                  selectionColor: root.accent
                  selectedTextColor: root.background
                  wrapMode: TextEdit.Wrap
                  selectByMouse: true
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  background: null
                  Keys.onPressed: function(event) {
                    if ((event.modifiers & Qt.ControlModifier)
                        && (event.modifiers & Qt.ShiftModifier)
                        && event.key === Qt.Key_V) {
                      root.toggleVoiceRecording()
                      event.accepted = true
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                      root.pasteClipboard()
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
                               && !(event.modifiers & Qt.ShiftModifier)) {
                      root.sendDraft()
                      event.accepted = true
                    }
                  }
                }
                Rectangle {
                  width: Style.space(34)
                  height: width
                  radius: width / 2
                  color: root.sending ? root.subtle : root.accent
                  opacity: root.sending ? 0.5 : 1
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.sending ? "…"
                      : (String(composer.text || "").trim() !== ""
                          || root.pendingAttachments.length > 0 ? "󰒊" : "󰍬")
                    color: root.sending ? root.muted : root.background
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  TapHandler {
                    enabled: !root.sending
                    onTapped: {
                      if (String(composer.text || "").trim() !== ""
                          || root.pendingAttachments.length > 0) root.sendDraft()
                      else root.toggleVoiceRecording()
                    }
                  }
                }
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
