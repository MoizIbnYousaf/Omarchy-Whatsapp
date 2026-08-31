import QtQuick
import Quickshell
import Quickshell.Io
import "SettingsPolicy.js" as SettingsPolicy
import "AccountModel.js" as AccountModel

// Resident state keeps the chat rail warm while the window is closed.
Item {
  id: root
  visible: false
  width: 0
  height: 0
  property var shell: null
  property var manifest: null
  property bool ready: false
  property bool railReady: false
  property bool authenticated: false
  property bool syncActive: false
  property bool offlineMode: false
  property bool notificationsEnabled: false
  property bool notificationsPreview: true
  property bool notifyAvailable: true
  property bool loadingChats: false
  property bool loadingMessages: false
  property bool loadingMembers: false
  property bool writing: false
  property bool controlWriting: false
  property bool settingsWriting: false
  property bool sendReadReceipts: false
  property bool showUnreadCount: true
  property int dropdownRows: 7
  property bool appOpen: false
  property bool dropdownOpen: false
  property bool messagesPending: false
  property bool membersPending: false
  property bool statusPending: false
  property bool statusReady: false
  property bool storeRefreshPending: false
  property string activeWriteKind: ""
  property string activeWriteChatJid: ""
  property string activeWriteAccount: ""
  property string activeWriteOwner: ""
  property string voiceOwner: "service"
  property string selectedChatJid: ""
  property string selectedChatAccount: ""
  property string selectedChatName: ""
  property string selectedChatKind: "unknown"
  property string statusAccount: ""
  property var pendingReceiptRef: ({ account: "", jid: "", key: "" })
  property string query: ""
  property string selectedId: ""
  property string mediaDownloadId: ""
  property string errorText: ""
  property var chats: []
  property var accounts: []
  property var messages: []
  property var members: []
  property var discardQueue: []
  readonly property string voiceState: voiceRecorder.state
  readonly property string voiceDraftAccount: voiceRecorder.chatAccount
  readonly property string voiceDraftJid: voiceRecorder.chatJid
  readonly property string voiceDraftChatName: voiceRecorder.chatName
  readonly property string voiceDraftPath: voiceRecorder.draftPath
  readonly property string voiceErrorText: voiceRecorder.errorText
  readonly property int voiceDurationMs: voiceRecorder.durationMs
  readonly property int voicePlaybackPosition: voiceRecorder.playbackPosition
  readonly property bool voicePlaying: voiceRecorder.playing
  readonly property bool voiceCapturing: voiceRecorder.capturing
  readonly property alias playback: playbackCoordinator
  readonly property alias accountOperations: accountOperations

  readonly property bool windowOpen: appOpen || dropdownOpen
  readonly property bool multiAccount: AccountModel.isMultiAccount(accounts)
  readonly property var storeDirectories:
    AccountModel.storeDirectories(accounts, storeDirectory)
  function sameChat(chat, account, jid) {
    return AccountModel.sameChat(chat, account, jid)
  }
  function selectedChatRef() {
    return AccountModel.chatRef(selectedChatAccount, selectedChatJid)
  }
  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.moizibnyousaf.omawhatsapp"
  property string pendingAppPayload: ""
  PlaybackCoordinator { id: playbackCoordinator }
  AccountOperations {
    id: accountOperations
    helper: root.helper
    accounts: root.accounts
    onRefreshRequested: { root.refreshStatus(); root.refreshChats() }
  }
  readonly property string helper: Quickshell.env("HOME") + "/.local/bin/omawhatsapp"
  readonly property string storeDirectory: AccountModel.defaultStoreDirectory(
    Quickshell.env("WACLI_STORE_DIR"), Quickshell.env("XDG_STATE_HOME"),
    Quickshell.env("HOME"))
  readonly property int unreadCount: chats.reduce(function(total, chat) {
    return total + Number(chat.unread || 0)
  }, 0)
  readonly property int notificationUnreadCount: chats.reduce(function(total, chat) {
    return total + Number(chat.notification_unread || 0)
  }, 0)
  readonly property string barTooltip: railReady
    ? (offlineMode ? "OmaWhatsApp · offline archive"
      : "OmaWhatsApp · " + notificationUnreadCount + " new · middle-click to dismiss")
    : "OmaWhatsApp · reconnecting"

  signal textPasted(string text, var chatRef, string owner)
  signal attachmentPasted(string path, var chatRef, string owner)
  signal writeCompleted(string kind, var chatRef, var request, string owner)
  signal writeFailed(string message, var chatRef, var details, string owner)
  signal controlCompleted(string kind)
  signal controlFailed(string message)
  signal settingsCompleted()
  signal settingsFailed(string message)

  function injectApp() {
    var target = appLoader.item
    if (!target) return
    if ("shell" in target) target.shell = root.shell
    if ("manifest" in target) target.manifest = root.manifest
    if ("service" in target) target.service = root
  }

  function openApp(payloadJson) {
    pendingAppPayload = String(payloadJson || "{}")
    injectApp()
    if (!appLoader.item) return false
    var payload = pendingAppPayload
    pendingAppPayload = ""
    appLoader.item.open(payload)
    return true
  }

  function closeApp() {
    pendingAppPayload = ""
    voiceRecorder.stopForSurfaceClose()
    if (appLoader.item && typeof appLoader.item.close === "function")
      appLoader.item.close()
  }

  function toggleApp(payloadJson) {
    if (!appLoader.item && pendingAppPayload !== "") {
      pendingAppPayload = ""
      return
    }
    if (appLoader.item && appLoader.item.opened === true) closeApp()
    else openApp(payloadJson)
  }

  function parseJson(raw) {
    try { return JSON.parse(String(raw || "{}")) } catch (error) { return null }
  }

  function refresh() {
    refreshStatus()
    refreshChats()
    refreshMessages()
    refreshMembers()
  }
  function runNotify() {
    if (!railReady || !notificationsEnabled || notifyProcess.running) return
    notifyProcess.payload = JSON.stringify({
      account: selectedChatAccount,
      skip_jid: windowOpen ? selectedChatJid : ""
    })
    notifyProcess.stdinEnabled = true
    notifyProcess.running = true
  }
  function refreshStatus() {
    // The selected account comes from the helper's merged rail. Passing it
    // directly also lets startup load a non-default first chat before the
    // initial status response has populated the account list.
    var account = String(selectedChatAccount || "")
    if (statusProcess.running) {
      statusPending = true
      return
    }
    statusProcess.requestedAccount = account
    statusProcess.command = [helper, "status", "--account", account]
    statusProcess.running = true
  }
  function refreshFromStore() {
    storeRefreshPending = true
    storeRefreshDebounce.restart()
  }
  function refreshChats() {
    if (chatsProcess.running) return
    loadingChats = true
    chatsProcess.payload = "{}"
    chatsProcess.stdinEnabled = true
    chatsProcess.running = true
  }
  function refreshMessages() {
    if (selectedChatJid === "") return
    if (messagesProcess.running) { messagesPending = true; return }
    loadingMessages = true
    messagesProcess.chatRef = selectedChatRef()
    messagesProcess.requestedQuery = query
    messagesProcess.payload = JSON.stringify({
      account: messagesProcess.chatRef.account,
      jid: messagesProcess.chatRef.jid,
      query: messagesProcess.requestedQuery
    })
    messagesProcess.stdinEnabled = true
    messagesProcess.running = true
  }
  function refreshMembers() {
    if (selectedChatJid === "" || selectedChatKind !== "group") {
      if (selectedChatKind !== "group") members = []
      return
    }
    if (membersProcess.running) { membersPending = true; return }
    loadingMembers = true
    membersProcess.chatRef = selectedChatRef()
    membersProcess.payload = JSON.stringify({
      account: membersProcess.chatRef.account, jid: membersProcess.chatRef.jid
    })
    membersProcess.stdinEnabled = true
    membersProcess.running = true
  }
  function selectChat(chat) {
    if (!chat || !chat.jid) return
    var next = String(chat.jid)
    var nextAccount = String(chat.account || "")
    voiceRecorder.stopForChatChange(nextAccount, next)
    dismissNotifications(next, nextAccount)
    if (next !== selectedChatJid || nextAccount !== selectedChatAccount) {
      selectedChatJid = next
      selectedChatAccount = nextAccount
      selectedChatName = String(chat.name || "WhatsApp chat")
      selectedChatKind = String(chat.kind || "unknown")
      selectedId = ""
      query = ""
      messages = []
      members = []
      errorText = ""
      refreshMessages()
      refreshMembers()
    }
    // Local badge acknowledgement above never talks to WhatsApp. The receipt
    // decision waits for this exact account's status, then retains this exact
    // target across the deferred callback.
    pendingReceiptRef = AccountModel.chatRef(nextAccount, next)
    maybeSendAutomaticReceipt()
  }

  function maybeSendAutomaticReceipt() {
    var target = pendingReceiptRef
    if (!AccountModel.sameRef(target, selectedChatRef())) {
      pendingReceiptRef = AccountModel.chatRef("", "")
      return
    }
    if (!statusReady || statusAccount !== String(target.account || "")) {
      refreshStatus()
      return
    }
    if (!ready) {
      pendingReceiptRef = AccountModel.chatRef("", "")
      return
    }
    // A concurrent write is temporary; retain this exact target and retry
    // after the process settles. A disabled receipt policy or offline mode is
    // an intentional boundary, so those clear the pending request.
    if (writing) return
    if (!SettingsPolicy.shouldSendAutomaticReceipt(
          sendReadReceipts, offlineMode, false)) {
      pendingReceiptRef = AccountModel.chatRef("", "")
      return
    }
    Qt.callLater(function() {
      if (!AccountModel.sameRef(target, root.selectedChatRef())) return
      if (!root.statusReady || root.statusAccount !== String(target.account || "")) return
      if (!root.ready) return
      if (root.writing) return
      if (!SettingsPolicy.shouldSendAutomaticReceipt(
            root.sendReadReceipts, root.offlineMode, false)) {
        root.pendingReceiptRef = AccountModel.chatRef("", "")
        return
      }
      if (root.chatAction(target, "read"))
        root.pendingReceiptRef = AccountModel.chatRef("", "")
    })
  }

  onWritingChanged: {
    if (!writing) {
      if (String(pendingReceiptRef.jid || "") !== "") receiptRetry.restart()
      runNextDiscard()
    }
  }
  function search(value) {
    var next = String(value || "").trim()
    if (next === query) return
    query = next
    refreshMessages()
  }
  function selectItem(id) { selectedId = String(id || "") }
  function runWriteForChat(kind, payload, chatRef, owner) {
    var targetRef = AccountModel.chatRef(
      chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
    var target = targetRef.jid
    var scope = targetRef.account
    var origin = ["app", "dropdown", "service"].indexOf(String(owner || "")) >= 0
      ? String(owner) : "service"
    if (writing || writeProcess.running || target === "") return false
    if (!statusReady || statusAccount !== scope) {
      var waiting = "That account is still loading. Try again in a moment."
      errorText = waiting
      writeFailed(waiting, targetRef, ({}), origin)
      refreshStatus()
      return false
    }
    if (!ready) {
      var unavailable = "That account is not linked or its local archive is not ready."
      errorText = unavailable
      writeFailed(unavailable, targetRef, ({}), origin)
      return false
    }
    if (offlineMode && kind !== "paste") {
      var message = "Offline mode is on. Go online before sending or changing WhatsApp state."
      errorText = message
      writeFailed(message, targetRef, ({}), origin)
      return false
    }
    writing = true
    activeWriteKind = kind
    activeWriteChatJid = target
    activeWriteAccount = scope
    activeWriteOwner = origin
    errorText = ""
    var request = Object.assign({}, payload || ({}))
    request.jid = target
    writeProcess.kind = kind
    writeProcess.chatRef = targetRef
    writeProcess.request = request
    writeProcess.owner = origin
    request.account = scope
    writeProcess.payload = JSON.stringify(request)
    writeProcess.command = [helper, kind]
    writeProcess.stdinEnabled = true
    writeProcess.running = true
    return true
  }
  function sendText(chatRef, text, replyId, mentions, owner) {
    var value = String(text || "").trim()
    return value !== "" && runWriteForChat("send", {
      text: value,
      reply_id: String(replyId || ""),
      mentions: Array.isArray(mentions) ? mentions : []
    }, chatRef, owner)
  }
  function pasteClipboard(chatRef, owner) {
    return runWriteForChat("paste", {}, chatRef, owner)
  }
  function discardStages(paths) {
    var values = Array.isArray(paths) ? paths : []
    var next = discardQueue.slice()
    for (var i = 0; i < values.length; i++) {
      var value = String(values[i] || "")
      if (value !== "" && next.indexOf(value) < 0) next.push(value)
    }
    discardQueue = next
    runNextDiscard()
  }
  function discardStage(path) { discardStages([path]) }
  function runNextDiscard() {
    if (discardProcess.running || discardQueue.length === 0) return
    // A file send prevalidates its paths before wacli opens them. Never race
    // that process by unlinking a staged attachment from another surface.
    if (writing && activeWriteKind === "files") return
    var next = discardQueue.slice()
    var path = next.shift()
    discardQueue = next
    discardProcess.payload = JSON.stringify({ path: path })
    discardProcess.stdinEnabled = true
    discardProcess.running = true
  }
  function sendFiles(chatRef, paths, caption, owner) {
    return runWriteForChat("files", {
      paths: Array.isArray(paths) ? paths : [],
      caption: String(caption || "").trim()
    }, chatRef, owner)
  }
  function sendFilesReply(chatRef, paths, caption, replyId, owner) {
    return runWriteForChat("files", {
      paths: Array.isArray(paths) ? paths : [],
      caption: String(caption || "").trim(),
      reply_id: String(replyId || "")
    }, chatRef, owner)
  }
  function toggleVoice(account, jid, chatName, replyId, owner) {
    var origin = ["app", "dropdown"].indexOf(String(owner || "")) >= 0
      ? String(owner) : "service"
    var changed = voiceRecorder.toggle(
      String(account || ""), String(jid || ""), String(chatName || ""),
      String(replyId || ""))
    if (changed) voiceOwner = origin
    return changed
  }
  function stopVoiceRecording() { return voiceRecorder.stopToReview() }
  function stopVoiceForSurfaceClose() { voiceRecorder.stopForSurfaceClose() }
  function discardVoice() { return voiceRecorder.discard() }
  function sendVoiceDraft(owner) {
    var previous = voiceOwner
    voiceOwner = ["app", "dropdown"].indexOf(String(owner || "")) >= 0
      ? String(owner) : "service"
    var requested = voiceRecorder.requestSend()
    if (!requested) voiceOwner = previous
    return requested
  }
  function toggleVoicePlayback() { return voiceRecorder.playPause() }
  function sendSticker(chatRef, path, replyId, owner) {
    return runWriteForChat("sticker", {
      path: String(path || ""),
      reply_id: String(replyId || "")
    }, chatRef, owner)
  }
  function sendPoll(chatRef, question, options, multi, owner) {
    return runWriteForChat("poll", {
      question: String(question || ""),
      options: Array.isArray(options) ? options : [],
      multi: Number(multi || 1)
    }, chatRef, owner)
  }
  function downloadMedia(chatRef, item, owner) {
    if (!item || !item.id) return false
    var id = String(item.id)
    var started = runWriteForChat("media", { id: id }, chatRef, owner)
    if (started) mediaDownloadId = id
    return started
  }
  function reactTo(chatRef, item, emoji, owner) {
    if (!item || !item.id) return false
    return runWriteForChat("react", {
      id: String(item.id), emoji: String(emoji || "")
    }, chatRef, owner)
  }
  function editMessage(chatRef, item, text, owner) {
    if (!item || !item.id) return false
    return runWriteForChat("edit", {
      id: String(item.id), text: String(text || "")
    }, chatRef, owner)
  }
  function deleteMessage(chatRef, item, forMe, owner) {
    if (!item || !item.id) return false
    return runWriteForChat("delete", {
      id: String(item.id), for_me: forMe === true
    }, chatRef, owner)
  }
  function forwardMessage(chatRef, item, targetJid, owner) {
    if (!item || !item.id || String(targetJid || "") === "") return false
    return runWriteForChat("forward", {
      id: String(item.id), to_jid: String(targetJid)
    }, chatRef, owner)
  }
  function selectOption(chatRef, item, index, owner) {
    if (!item || !item.id) return false
    return runWriteForChat("select", {
      id: String(item.id), index: Number(index)
    }, chatRef, owner)
  }
  function chatAction(chatRef, action, owner) {
    return runWriteForChat("chat-action", {
      action: String(action || "")
    }, chatRef, owner)
  }
  function clearNotificationCount(jid, account) {
    var target = String(jid || "")
    root.chats = root.chats.map(function(chat) {
      if (target !== "" && !root.sameChat(chat, account, target)) return chat
      var next = Object.assign({}, chat)
      next.notification_unread = 0
      return next
    })
  }
  function dismissNotifications(jid, account) {
    var target = String(jid || "")
    // An empty JID clears the aggregated badge across every account.
    var scope = target === "" ? "" : String(account || "")
    clearNotificationCount(target, scope)
    return acknowledgementQueue.enqueue(scope, target)
  }
  function setNotifications(enabled, preview) {
    if (controlProcess.running || writing) return false
    var request = ({})
    if (enabled !== undefined && enabled !== null) request.enabled = enabled === true
    if (preview !== undefined && preview !== null) request.preview = preview === true
    controlWriting = true
    controlProcess.kind = "notify-mode"
    controlProcess.account = ""
    controlProcess.payload = JSON.stringify(request)
    controlProcess.command = [helper, "notify-mode"]
    controlProcess.stdinEnabled = true
    controlProcess.running = true
    return true
  }
  function setOnline(online) {
    if (controlProcess.running || writing) return false
    controlWriting = true
    controlProcess.kind = "sync-mode"
    controlProcess.account = root.selectedChatAccount
    controlProcess.payload = JSON.stringify({
      account: controlProcess.account, online: online === true
    })
    controlProcess.command = [helper, "sync-mode"]
    controlProcess.stdinEnabled = true
    controlProcess.running = true
    return true
  }
  function setPreference(key, value) {
    if (settingsProcess.running) return false
    var settings = ({})
    settings[String(key || "")] = value
    settingsWriting = true
    settingsProcess.account = root.selectedChatAccount
    settingsProcess.payload = JSON.stringify({
      account: settingsProcess.account, settings: settings
    })
    settingsProcess.stdinEnabled = true
    settingsProcess.running = true
    return true
  }

  AcknowledgementQueue {
    id: acknowledgementQueue
    helper: root.helper
    onCompleted: function(chatRef) {
      root.refreshChats()
    }
    onFailed: function(message, chatRef) {
      root.errorText = String(message || "Notification acknowledgement failed.")
      root.refreshChats()
    }
  }

  VoiceRecorder {
    id: voiceRecorder
    helper: root.helper
    playback: playbackCoordinator
    onNotice: function(message) { root.errorText = String(message || "") }
    onSendRequested: function(account, jid, path, replyId) {
      var started = root.runWriteForChat("voice", {
        path: String(path || ""),
        reply_id: String(replyId || "")
      }, AccountModel.chatRef(account, jid), root.voiceOwner)
      if (started) voiceRecorder.markSending(account, jid)
      else voiceRecorder.markSendFailed(root.errorText, account, jid)
    }
  }
  // The full window belongs to the one resident service, while the bar owns
  // the anchored dropdown. This avoids duplicate per-monitor app windows and
  // keeps a bar click on the compact surface.
  Loader {
    id: appLoader
    active: true
    asynchronous: true
    source: Qt.resolvedUrl("App.qml")
    onLoaded: {
      root.injectApp()
      if (root.pendingAppPayload !== "") Qt.callLater(function() {
        root.openApp(root.pendingAppPayload)
      })
    }
  }

  IpcHandler {
    target: root.pluginId

    function status(): string {
      return JSON.stringify({
        appOpen: root.appOpen,
        dropdownOpen: root.dropdownOpen,
        ready: root.railReady,
        privateReading: !root.sendReadReceipts
      })
    }

    function openApp(payload: string): string {
      return root.openApp(payload) ? "ok" : "loading"
    }

    function closeApp(): string {
      root.closeApp()
      return "ok"
    }

    function toggleApp(payload: string): string {
      root.toggleApp(payload)
      return "ok"
    }
  }

  // One watcher per account store; they share the debounce below.
  Instantiator {
    id: storeWatchers
    model: root.storeDirectories
    delegate: Process {
      required property string modelData
      running: true
      command: [
        "setpriv", "--pdeathsig", "TERM",
        "inotifywait", "-m", "-q",
        "-e", "close_write,create,delete,move,modify",
        "--format", "%f", modelData
      ]
      stdout: SplitParser {
        splitMarker: "\n"
        onRead: function(fileName) {
          var name = String(fileName || "").trim()
          if (name === "wacli.db" || name === "wacli.db-wal")
            root.refreshFromStore()
        }
      }
      onExited: storeWatchRestart.restart()
    }
  }

  Timer {
    id: storeWatchRestart
    interval: 1500
    repeat: false
    onTriggered: {
      for (var i = 0; i < storeWatchers.count; i++) {
        var watcher = storeWatchers.objectAt(i)
        if (watcher && !watcher.running) watcher.running = true
      }
    }
  }

  Timer {
    id: storeRefreshDebounce
    interval: 160
    repeat: false
    onTriggered: {
      if (chatsProcess.running) return
      root.storeRefreshPending = false
      root.refreshChats()
      if (root.windowOpen) {
        root.refreshMessages()
        root.refreshMembers()
      }
    }
  }

  Timer {
    interval: 12000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshChats()
      root.runNotify()
      if (root.windowOpen) root.refreshMessages()
    }
  }
  Timer {
    interval: 120000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  // Switching to a chat in another account changes which account the header
  // pills and the receipt preference describe.
  onSelectedChatAccountChanged: {
    if (statusAccount !== String(selectedChatAccount || "")) statusReady = false
    refreshStatus()
  }

  Process {
    id: statusProcess
    property string requestedAccount: ""
    command: [root.helper, "status", "--account", ""]
    stdout: StdioCollector { id: statusOutput }
    stderr: StdioCollector { id: statusError }
    onExited: function(exitCode) {
      var payload = root.parseJson(statusOutput.text)
      var responseAccount = payload && payload.ok === true
        ? String(payload.account || "") : requestedAccount
      var selectedAccount = String(root.selectedChatAccount || "")
      var applies = selectedAccount === "" || responseAccount === selectedAccount
      if (!payload || payload.ok !== true) {
        if (applies) {
          root.statusReady = false
          root.ready = false
          root.railReady = false
          root.errorText = (payload && payload.error)
            || String(statusError.text || "OmaWhatsApp could not connect.").trim()
        }
      } else if (applies) {
        var readiness = AccountModel.statusReadiness(payload)
        root.statusAccount = responseAccount
        root.statusReady = true
        root.authenticated = readiness.authenticated
        root.railReady = readiness.railReady
        root.syncActive = payload.sync_active === true
        root.offlineMode = payload.offline_mode === true
        var notifications = payload.notifications
        root.notificationsEnabled = !!notifications && notifications.enabled === true
        root.notificationsPreview = !notifications || notifications.preview !== false
        root.notifyAvailable = payload.notify_available !== false
        root.accounts = Array.isArray(payload.accounts) ? payload.accounts : []
        root.sendReadReceipts = payload.send_read_receipts === true
        root.showUnreadCount = payload.show_unread_count !== false
        root.dropdownRows = [5, 7, 9].indexOf(Number(payload.dropdown_rows)) >= 0
          ? Number(payload.dropdown_rows) : 7
        root.ready = readiness.accountReady
        if (root.ready) root.errorText = ""
        root.maybeSendAutomaticReceipt()
      }
      // Only an event that arrived while this request was running earns one
      // follow-up. A failed response must never self-schedule forever merely
      // because statusAccount has not been populated yet.
      var shouldRefresh = root.statusPending
      root.statusPending = false
      if (shouldRefresh) statusRefreshDelay.restart()
    }
  }

  Timer {
    id: statusRefreshDelay
    interval: 250
    repeat: false
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: receiptRetry
    interval: 100
    repeat: false
    onTriggered: root.maybeSendAutomaticReceipt()
  }

  Process {
    id: chatsProcess
    property string payload: ""
    command: [root.helper, "chats", "--limit", "500"]
    stdinEnabled: true
    stdout: StdioCollector { id: chatsOutput }
    stderr: StdioCollector { id: chatsError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.loadingChats = false
      if (root.storeRefreshPending) storeRefreshDebounce.restart()
      var payload = root.parseJson(chatsOutput.text)
      if (!payload || payload.ok !== true) {
        root.errorText = (payload && payload.error) || String(chatsError.text || "Chats could not be read.").trim()
        return
      }
      root.chats = Array.isArray(payload.chats) ? payload.chats : []
      if (root.chats.length === 0) return
      var selected = null
      for (var i = 0; i < root.chats.length; i++)
        if (root.sameChat(root.chats[i], root.selectedChatAccount, root.selectedChatJid))
          selected = root.chats[i]
      if (!selected) {
        selected = root.chats[0]
        root.selectedChatJid = String(selected.jid)
        root.selectedChatAccount = String(selected.account || "")
        root.query = ""
        root.messages = []
        root.members = []
        if (root.windowOpen)
          root.dismissNotifications(root.selectedChatJid, root.selectedChatAccount)
      }
      root.selectedChatName = String(selected.name || "WhatsApp chat")
      root.selectedChatKind = String(selected.kind || "unknown")
      if (root.messages.length === 0) root.refreshMessages()
      if (root.selectedChatKind === "group" && root.members.length === 0) root.refreshMembers()
    }
  }

  Process {
    id: controlProcess
    property string kind: ""
    property string account: ""
    property string payload: ""
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: controlOutput }
    stderr: StdioCollector { id: controlError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.controlWriting = false
      var finishedKind = kind
      var payload = root.parseJson(controlOutput.text)
      if (exitCode !== 0 || !payload || payload.ok !== true) {
        var message = (payload && payload.error)
          || String(controlError.text || "OmaWhatsApp could not change that setting.").trim()
        root.errorText = message
        root.controlFailed(message)
        root.refreshStatus()
        root.refreshChats()
        return
      }
      root.errorText = ""
      var accountIsCurrent = account === String(root.selectedChatAccount || "")
      if (finishedKind === "sync-mode" && accountIsCurrent) {
        root.offlineMode = payload.online !== true
        root.syncActive = payload.online === true
      }
      if (finishedKind === "notify-mode" && payload.notifications) {
        root.notificationsEnabled = payload.notifications.enabled === true
        root.notificationsPreview = payload.notifications.preview !== false
      }
      if (finishedKind !== "sync-mode" || accountIsCurrent)
        root.controlCompleted(finishedKind)
      root.refreshStatus()
      root.refreshChats()
    }
  }

  Process {
    id: settingsProcess
    property string account: ""
    property string payload: ""
    command: [root.helper, "settings"]
    stdinEnabled: true
    stdout: StdioCollector { id: settingsOutput }
    stderr: StdioCollector { id: settingsError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.settingsWriting = false
      var payload = root.parseJson(settingsOutput.text)
      if (exitCode !== 0 || !payload || payload.ok !== true) {
        var message = (payload && payload.error)
          || String(settingsError.text || "OmaWhatsApp settings could not be saved.").trim()
        root.errorText = message
        root.settingsFailed(message)
        root.refreshStatus()
        return
      }
      // Receipt preference is account-scoped; badge visibility and dropdown
      // density are one global UI preference shared by every account.
      if (account === String(root.selectedChatAccount || ""))
        root.sendReadReceipts = payload.send_read_receipts === true
      root.showUnreadCount = payload.show_unread_count !== false
      root.dropdownRows = [5, 7, 9].indexOf(Number(payload.dropdown_rows)) >= 0
        ? Number(payload.dropdown_rows) : 7
      root.errorText = ""
      root.settingsCompleted()
      root.refreshStatus()
    }
  }

  Process {
    id: notifyProcess
    property string payload: ""
    command: [root.helper, "notify"]
    stdinEnabled: true
    stdout: StdioCollector { id: notifyOutput }
    stderr: StdioCollector { }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var payload = root.parseJson(notifyOutput.text)
      if (payload && payload.ok === true && payload.available === false)
        root.notifyAvailable = false
    }
  }

  Process {
    id: discardProcess
    property string payload: ""
    command: [root.helper, "discard-stage"]
    stdinEnabled: true
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) { Qt.callLater(root.runNextDiscard) }
  }

  Process {
    id: messagesProcess
    property string payload: ""
    property var chatRef: ({ account: "", jid: "", key: "" })
    property string requestedQuery: ""
    command: [root.helper, "messages", "--limit", "240"]
    stdinEnabled: true
    stdout: StdioCollector { id: messagesOutput }
    stderr: StdioCollector { id: messagesError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.loadingMessages = false
      var payload = root.parseJson(messagesOutput.text)
      var requestIsCurrent = AccountModel.sameRef(chatRef, root.selectedChatRef())
        && requestedQuery === root.query
      var responseIsCurrent = requestIsCurrent && AccountModel.responseMatches(
        payload ? payload.chat : null, chatRef, root.selectedChatRef())
      if ((!payload || payload.ok !== true) && requestIsCurrent) {
        root.errorText = (payload && payload.error) || String(messagesError.text || "Messages could not be read.").trim()
      } else if (payload && payload.ok === true && responseIsCurrent) {
        root.messages = Array.isArray(payload.messages) ? payload.messages : []
        root.selectedChatName = String(payload.chat.name || root.selectedChatName)
        root.selectedChatKind = String(payload.chat.kind || root.selectedChatKind)
      }
      if (root.messagesPending) { root.messagesPending = false; Qt.callLater(root.refreshMessages) }
    }
  }

  Process {
    id: membersProcess
    property string payload: ""
    property var chatRef: ({ account: "", jid: "", key: "" })
    command: [root.helper, "members"]
    stdinEnabled: true
    stdout: StdioCollector { id: membersOutput }
    stderr: StdioCollector { id: membersError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.loadingMembers = false
      var payload = root.parseJson(membersOutput.text)
      var requestIsCurrent = AccountModel.sameRef(chatRef, root.selectedChatRef())
      var responseIsCurrent = requestIsCurrent && AccountModel.responseMatches(
        payload ? payload.chat : null, chatRef, root.selectedChatRef())
      if ((!payload || payload.ok !== true) && requestIsCurrent) {
        root.errorText = (payload && payload.error)
          || String(membersError.text || "Group members could not be read.").trim()
      } else if (payload && payload.ok === true && responseIsCurrent) {
        root.members = Array.isArray(payload.members) ? payload.members : []
      }
      if (root.membersPending) {
        root.membersPending = false
        Qt.callLater(root.refreshMembers)
      }
    }
  }

  Process {
    id: writeProcess
    property string kind: ""
    property string payload: ""
    property var chatRef: ({ account: "", jid: "", key: "" })
    property var request: ({})
    property string owner: "service"
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: writeOutput }
    stderr: StdioCollector { id: writeError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.writing = false
      var finishedKind = kind
      var finishedChat = chatRef
      var finishedRequest = request
      var finishedOwner = owner
      request = ({})
      owner = "service"
      var finishedJid = String(finishedChat.jid || "")
      var finishedAccount = String(finishedChat.account || "")
      root.activeWriteKind = ""
      root.activeWriteChatJid = ""
      root.activeWriteAccount = ""
      root.activeWriteOwner = ""
      var payload = root.parseJson(writeOutput.text)
      if (exitCode !== 0 || !payload || payload.ok !== true) {
        var message = (payload && payload.error) || String(writeError.text || "WhatsApp could not complete that request.").trim()
        if (AccountModel.sameRef(finishedChat, root.selectedChatRef()))
          root.errorText = message
        if (finishedKind === "media") root.mediaDownloadId = ""
        if (finishedKind === "voice")
          voiceRecorder.markSendFailed(message, finishedAccount, finishedJid)
        if (finishedKind === "voice") root.voiceOwner = "service"
        var details = Object.assign({},
          payload && payload.partial ? payload.partial : ({}))
        details.kind = finishedKind
        details.request = finishedRequest
        root.writeFailed(message, finishedChat, details, finishedOwner)
        return
      }
      if (kind === "paste" && payload.kind === "text") {
        if (AccountModel.sameRef(finishedChat, root.selectedChatRef()))
          root.errorText = ""
        root.textPasted(String(payload.text || ""), finishedChat, finishedOwner)
        return
      }
      if (kind === "paste" && (payload.kind === "file" || payload.kind === "image")) {
        if (AccountModel.sameRef(finishedChat, root.selectedChatRef()))
          root.errorText = ""
        root.attachmentPasted(String(payload.path || ""), finishedChat, finishedOwner)
        return
      }
      if (AccountModel.sameRef(finishedChat, root.selectedChatRef()))
        root.errorText = ""
      if (finishedKind === "media") root.mediaDownloadId = ""
      if (finishedKind === "voice") {
        voiceRecorder.markSent(finishedAccount, finishedJid)
        root.voiceOwner = "service"
      }
      root.writeCompleted(finishedKind, finishedChat, finishedRequest, finishedOwner)
      refreshDelay.restart()
    }
  }

  Timer {
    id: refreshDelay
    interval: 220
    repeat: false
    onTriggered: { root.refreshChats(); root.refreshMessages() }
  }
}
