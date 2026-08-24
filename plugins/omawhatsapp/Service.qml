import QtQuick
import Quickshell
import Quickshell.Io

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
  property bool loadingChats: false
  property bool loadingMessages: false
  property bool loadingMembers: false
  property bool writing: false
  property bool windowOpen: false
  property bool messagesPending: false
  property string activeWriteKind: ""
  property string activeWriteChatJid: ""
  property string selectedChatJid: ""
  property string selectedChatName: ""
  property string selectedChatKind: "unknown"
  property string query: ""
  property string selectedId: ""
  property string mediaDownloadId: ""
  property string errorText: ""
  property var chats: []
  property var messages: []
  property var members: []

  readonly property string helper: Quickshell.env("HOME") + "/.local/bin/omawhatsapp"
  readonly property int unreadCount: chats.reduce(function(total, chat) {
    return total + Number(chat.unread || 0)
  }, 0)
  readonly property string barTooltip: ready
    ? "OmaWhatsApp · " + unreadCount + " unread"
    : "OmaWhatsApp · reconnecting"

  signal textPasted(string text, string jid)
  signal attachmentPasted(string path, string jid)
  signal writeCompleted(string kind, string jid)
  signal writeFailed(string message, string jid)

  function parseJson(raw) {
    try { return JSON.parse(String(raw || "{}")) } catch (error) { return null }
  }

  function refresh() {
    refreshStatus()
    refreshChats()
    refreshMessages()
    refreshMembers()
  }
  function refreshStatus() {
    if (!statusProcess.running) statusProcess.running = true
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
    messagesProcess.payload = JSON.stringify({ jid: selectedChatJid, query: query })
    messagesProcess.stdinEnabled = true
    messagesProcess.running = true
  }
  function refreshMembers() {
    if (selectedChatJid === "" || selectedChatKind !== "group" || membersProcess.running) {
      if (selectedChatKind !== "group") members = []
      return
    }
    loadingMembers = true
    membersProcess.payload = JSON.stringify({ jid: selectedChatJid })
    membersProcess.stdinEnabled = true
    membersProcess.running = true
  }
  function selectChat(chat) {
    if (!chat || !chat.jid) return
    var next = String(chat.jid)
    if (next === selectedChatJid) return
    selectedChatJid = next
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
  function search(value) {
    var next = String(value || "").trim()
    if (next === query) return
    query = next
    refreshMessages()
  }
  function selectItem(id) { selectedId = String(id || "") }
  function runWrite(kind, payload) {
    if (writing || writeProcess.running || selectedChatJid === "") return false
    writing = true
    activeWriteKind = kind
    activeWriteChatJid = selectedChatJid
    errorText = ""
    writeProcess.kind = kind
    writeProcess.payload = JSON.stringify(payload || ({}))
    writeProcess.command = [helper, kind]
    writeProcess.stdinEnabled = true
    writeProcess.running = true
    return true
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

  Timer {
    interval: 12000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshChats()
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

  Process {
    id: statusProcess
    command: [root.helper, "status"]
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
      var payload = root.parseJson(chatsOutput.text)
      if (!payload || payload.ok !== true) {
        root.errorText = (payload && payload.error) || String(chatsError.text || "Chats could not be read.").trim()
        return
      }
      root.chats = Array.isArray(payload.chats) ? payload.chats : []
      if (root.chats.length === 0) return
      var selected = null
      for (var i = 0; i < root.chats.length; i++)
        if (String(root.chats[i].jid) === root.selectedChatJid) selected = root.chats[i]
      if (!selected) {
        selected = root.chats[0]
        root.selectedChatJid = String(selected.jid)
        root.query = ""
        root.messages = []
        root.members = []
      }
      root.selectedChatName = String(selected.name || "WhatsApp chat")
      root.selectedChatKind = String(selected.kind || "unknown")
      if (root.messages.length === 0) root.refreshMessages()
      if (root.selectedChatKind === "group" && root.members.length === 0) root.refreshMembers()
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
      root.activeWriteKind = ""
      root.activeWriteChatJid = ""
      var payload = root.parseJson(writeOutput.text)
      if (exitCode !== 0 || !payload || payload.ok !== true) {
        var message = (payload && payload.error) || String(writeError.text || "WhatsApp could not complete that request.").trim()
        root.errorText = message
        if (finishedKind === "media") root.mediaDownloadId = ""
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
