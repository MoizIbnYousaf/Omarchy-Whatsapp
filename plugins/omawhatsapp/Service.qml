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
  property bool storeRefreshPending: false
  property string activeWriteKind: ""
  property string activeWriteChatJid: ""
  property string activeWriteAccount: ""
  property string selectedChatJid: ""
  property string selectedChatAccount: ""
  property string selectedChatName: ""
  property string selectedChatKind: "unknown"
  property string query: ""
  property string selectedId: ""
  property string mediaDownloadId: ""
  property string errorText: ""
  property var chats: []
  property var accounts: []
  property var messages: []
  property var members: []

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

  readonly property bool windowOpen: appOpen || dropdownOpen
  readonly property bool multiAccount: AccountModel.isMultiAccount(accounts)
  readonly property var storeDirectories:
    AccountModel.storeDirectories(accounts, storeDirectory)
  function sameChat(chat, account, jid) {
    return AccountModel.sameChat(chat, account, jid)
  }
  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.moizibnyousaf.omawhatsapp"
  property string pendingAppPayload: ""

  readonly property string helper: Quickshell.env("HOME") + "/.local/bin/omawhatsapp"
  readonly property string storeDirectory: {
    var configured = String(Quickshell.env("WACLI_STORE_DIR") || "").trim()
    if (configured !== "") return configured
    var stateHome = String(Quickshell.env("XDG_STATE_HOME") || "").trim()
    if (stateHome === "") stateHome = Quickshell.env("HOME") + "/.local/state"
    return stateHome + "/wacli"
  }
  readonly property int unreadCount: chats.reduce(function(total, chat) {
    return total + Number(chat.unread || 0)
  }, 0)
  readonly property int notificationUnreadCount: chats.reduce(function(total, chat) {
    return total + Number(chat.notification_unread || 0)
  }, 0)
  readonly property string barTooltip: ready
    ? (offlineMode ? "OmaWhatsApp · offline archive"
      : "OmaWhatsApp · " + notificationUnreadCount + " new · middle-click to dismiss")
    : "OmaWhatsApp · reconnecting"

  signal textPasted(string text, string jid)
  signal attachmentPasted(string path, string jid)
  signal writeCompleted(string kind, string jid)
  signal writeFailed(string message, string jid)
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
    if (!ready || !notificationsEnabled || notifyProcess.running) return
    notifyProcess.payload = JSON.stringify({
      account: selectedChatAccount,
      skip_jid: windowOpen ? selectedChatJid : ""
    })
    notifyProcess.stdinEnabled = true
    notifyProcess.running = true
  }
  function knownAccount(name) {
    var target = String(name || "")
    if (target === "") return ""
    for (var i = 0; i < accounts.length; i++)
      if (String(accounts[i].account || "") === target) return target
    return ""
  }
  function refreshStatus() {
    if (statusProcess.running) return
    statusProcess.command = [helper, "status", "--account",
                             knownAccount(selectedChatAccount)]
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
    messagesProcess.payload = JSON.stringify({
      account: selectedChatAccount, jid: selectedChatJid, query: query
    })
    messagesProcess.stdinEnabled = true
    messagesProcess.running = true
  }
  function refreshMembers() {
    if (selectedChatJid === "" || selectedChatKind !== "group" || membersProcess.running) {
      if (selectedChatKind !== "group") members = []
      return
    }
    loadingMembers = true
    membersProcess.payload = JSON.stringify({
      account: selectedChatAccount, jid: selectedChatJid
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
    // Reading stays private unless the user explicitly opts in. Local badge
    // acknowledgement above never talks to WhatsApp; this action does.
    if (SettingsPolicy.shouldSendAutomaticReceipt(sendReadReceipts, offlineMode, writing))
      Qt.callLater(function() { root.chatAction("read") })
  }
  function search(value) {
    var next = String(value || "").trim()
    if (next === query) return
    query = next
    refreshMessages()
  }
  function selectItem(id) { selectedId = String(id || "") }
  function runWriteForChat(kind, payload, jid, account) {
    var target = String(jid || "")
    var scope = account === undefined
      ? String(selectedChatAccount || "") : String(account || "")
    if (writing || writeProcess.running || target === "") return false
    if (offlineMode && kind !== "paste") {
      var message = "Offline mode is on. Go online before sending or changing WhatsApp state."
      errorText = message
      writeFailed(message, target)
      return false
    }
    writing = true
    activeWriteKind = kind
    activeWriteChatJid = target
    activeWriteAccount = scope
    errorText = ""
    var request = Object.assign({}, payload || ({}))
    request.jid = target
    writeProcess.kind = kind
    request.account = scope
    writeProcess.payload = JSON.stringify(request)
    writeProcess.command = [helper, kind]
    writeProcess.stdinEnabled = true
    writeProcess.running = true
    return true
  }
  function runWrite(kind, payload) {
    return runWriteForChat(kind, payload, selectedChatJid, selectedChatAccount)
  }
  function sendText(text, replyId, mentions) {
    var value = String(text || "").trim()
    return value !== "" && runWrite("send", {
      jid: selectedChatJid,
      text: value,
      reply_id: String(replyId || ""),
      mentions: Array.isArray(mentions) ? mentions : []
    })
  }
  function pasteClipboard() {
    return runWrite("paste", { jid: selectedChatJid })
  }
  function sendFiles(paths, caption) {
    return runWrite("files", {
      jid: selectedChatJid,
      paths: Array.isArray(paths) ? paths : [],
      caption: String(caption || "").trim()
    })
  }
  function sendFilesReply(paths, caption, replyId) {
    return runWrite("files", {
      jid: selectedChatJid,
      paths: Array.isArray(paths) ? paths : [],
      caption: String(caption || "").trim(),
      reply_id: String(replyId || "")
    })
  }
  function toggleVoice(account, jid, chatName, replyId) {
    return voiceRecorder.toggle(String(account || ""), String(jid || ""), String(chatName || ""),
      String(replyId || ""))
  }
  function stopVoiceRecording() { return voiceRecorder.stopToReview() }
  function stopVoiceForSurfaceClose() { voiceRecorder.stopForSurfaceClose() }
  function discardVoice() { return voiceRecorder.discard() }
  function sendVoiceDraft() { return voiceRecorder.requestSend() }
  function toggleVoicePlayback() { return voiceRecorder.playPause() }
  function sendSticker(path, replyId) {
    return runWrite("sticker", {
      jid: selectedChatJid,
      path: String(path || ""),
      reply_id: String(replyId || "")
    })
  }
  function sendPoll(question, options, multi) {
    return runWrite("poll", {
      jid: selectedChatJid,
      question: String(question || ""),
      options: Array.isArray(options) ? options : [],
      multi: Number(multi || 1)
    })
  }
  function downloadMedia(item) {
    if (!item || !item.id) return false
    var id = String(item.id)
    var started = runWrite("media", { jid: selectedChatJid, id: id })
    if (started) mediaDownloadId = id
    return started
  }
  function reactTo(item, emoji) {
    if (!item || !item.id) return false
    return runWrite("react", {
      jid: selectedChatJid, id: String(item.id), emoji: String(emoji || "")
    })
  }
  function editMessage(item, text) {
    if (!item || !item.id) return false
    return runWrite("edit", {
      jid: selectedChatJid, id: String(item.id), text: String(text || "")
    })
  }
  function deleteMessage(item, forMe) {
    if (!item || !item.id) return false
    return runWrite("delete", {
      jid: selectedChatJid, id: String(item.id), for_me: forMe === true
    })
  }
  function forwardMessage(item, targetJid) {
    if (!item || !item.id || String(targetJid || "") === "") return false
    return runWrite("forward", {
      jid: selectedChatJid, id: String(item.id), to_jid: String(targetJid)
    })
  }
  function selectOption(item, index) {
    if (!item || !item.id) return false
    return runWrite("select", {
      jid: selectedChatJid, id: String(item.id), index: Number(index)
    })
  }
  function chatAction(action) {
    return runWrite("chat-action", {
      jid: selectedChatJid, action: String(action || "")
    })
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
    if (controlProcess.running) return false
    var target = String(jid || "")
    // An empty JID clears the aggregated badge across every account.
    var scope = target === "" ? "" : String(account || "")
    clearNotificationCount(target, scope)
    controlWriting = true
    controlProcess.kind = "acknowledge"
    controlProcess.payload = JSON.stringify({ account: scope, jid: target })
    controlProcess.command = [helper, "acknowledge"]
    controlProcess.stdinEnabled = true
    controlProcess.running = true
    return true
  }
  function setNotifications(enabled, preview) {
    if (controlProcess.running || writing) return false
    var request = ({})
    if (enabled !== undefined && enabled !== null) request.enabled = enabled === true
    if (preview !== undefined && preview !== null) request.preview = preview === true
    controlWriting = true
    controlProcess.kind = "notify-mode"
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
    controlProcess.payload = JSON.stringify({
      account: root.selectedChatAccount, online: online === true
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
    settingsProcess.payload = JSON.stringify({
      account: root.selectedChatAccount, settings: settings
    })
    settingsProcess.stdinEnabled = true
    settingsProcess.running = true
    return true
  }

  VoiceRecorder {
    id: voiceRecorder
    helper: root.helper
    onNotice: function(message) { root.errorText = String(message || "") }
    onSendRequested: function(account, jid, path, replyId) {
      var started = root.runWriteForChat("voice", {
        jid: String(jid || ""),
        path: String(path || ""),
        reply_id: String(replyId || "")
      }, jid, account)
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
        ready: root.ready,
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
  onSelectedChatAccountChanged: refreshStatus()

  Process {
    id: statusProcess
    command: [root.helper, "status", "--account", ""]
    stdout: StdioCollector { id: statusOutput }
    stderr: StdioCollector { id: statusError }
    onExited: function(exitCode) {
      var payload = root.parseJson(statusOutput.text)
      if (!payload || payload.ok !== true) {
        root.ready = false
        root.errorText = (payload && payload.error) || String(statusError.text || "OmaWhatsApp could not connect.").trim()
        return
      }
      root.authenticated = payload.authenticated === true
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
      root.ready = root.authenticated && payload.database_ready === true
      if (root.ready) root.errorText = ""
    }
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
      if (finishedKind === "sync-mode") {
        root.offlineMode = payload.online !== true
        root.syncActive = payload.online === true
      }
      if (finishedKind === "notify-mode" && payload.notifications) {
        root.notificationsEnabled = payload.notifications.enabled === true
        root.notificationsPreview = payload.notifications.preview !== false
      }
      root.controlCompleted(finishedKind)
      root.refreshStatus()
      root.refreshChats()
    }
  }

  Process {
    id: settingsProcess
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
      root.sendReadReceipts = payload.send_read_receipts === true
      root.showUnreadCount = payload.show_unread_count !== false
      root.dropdownRows = [5, 7, 9].indexOf(Number(payload.dropdown_rows)) >= 0
        ? Number(payload.dropdown_rows) : 7
      root.errorText = ""
      root.settingsCompleted()
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
    id: messagesProcess
    property string payload: ""
    command: [root.helper, "messages", "--limit", "240"]
    stdinEnabled: true
    stdout: StdioCollector { id: messagesOutput }
    stderr: StdioCollector { id: messagesError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.loadingMessages = false
      var payload = root.parseJson(messagesOutput.text)
      if (!payload || payload.ok !== true) {
        root.errorText = (payload && payload.error) || String(messagesError.text || "Messages could not be read.").trim()
      } else if (payload.chat && String(payload.chat.jid || "") === root.selectedChatJid) {
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
    command: [root.helper, "members"]
    stdinEnabled: true
    stdout: StdioCollector { id: membersOutput }
    stderr: StdioCollector { id: membersError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.loadingMembers = false
      var payload = root.parseJson(membersOutput.text)
      if (!payload || payload.ok !== true) {
        root.errorText = (payload && payload.error)
          || String(membersError.text || "Group members could not be read.").trim()
      } else if (payload.chat && String(payload.chat.jid || "") === root.selectedChatJid) {
        root.members = Array.isArray(payload.members) ? payload.members : []
      }
    }
  }

  Process {
    id: writeProcess
    property string kind: ""
    property string payload: ""
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: writeOutput }
    stderr: StdioCollector { id: writeError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.writing = false
      var finishedKind = kind
      var finishedJid = root.activeWriteChatJid
      var finishedAccount = root.activeWriteAccount
      root.activeWriteKind = ""
      root.activeWriteChatJid = ""
      root.activeWriteAccount = ""
      var payload = root.parseJson(writeOutput.text)
      if (exitCode !== 0 || !payload || payload.ok !== true) {
        var message = (payload && payload.error) || String(writeError.text || "WhatsApp could not complete that request.").trim()
        root.errorText = message
        if (finishedKind === "media") root.mediaDownloadId = ""
        if (finishedKind === "voice")
          voiceRecorder.markSendFailed(message, finishedAccount, finishedJid)
        root.writeFailed(message, finishedJid)
        return
      }
      if (kind === "paste" && payload.kind === "text") {
        root.textPasted(String(payload.text || ""), finishedJid)
        return
      }
      if (kind === "paste" && (payload.kind === "file" || payload.kind === "image")) {
        root.errorText = ""
        root.attachmentPasted(String(payload.path || ""), finishedJid)
        return
      }
      root.errorText = ""
      if (finishedKind === "media") root.mediaDownloadId = ""
      if (finishedKind === "voice") voiceRecorder.markSent(finishedAccount, finishedJid)
      root.writeCompleted(finishedKind, finishedJid)
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
