import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "SettingsPolicy.js" as SettingsPolicy
import "AccountModel.js" as AccountModel
import "ComposerModel.js" as ComposerModel

// OmaWhatsApp keeps chat state resident, renders a responsive native timeline,
// and follows Omarchy's semantic theme. All chats come from wacli's local mirror.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false
  property bool demoMode: false
  property string contentFilter: "all"
  property alias cursorIndex: keyboardNavigation.messageIndex
  property alias chatCursorIndex: keyboardNavigation.chatIndex
  readonly property alias keyboardContext: keyboardNavigation.context
  property var pendingComposerSnapshot: null
  property string pendingWriteKind: ""
  property bool narrowConversation: false
  property bool narrowSearchOpen: false
  property bool sidebarCollapsed: false
  property bool settingsOpen: false
  property var replyTarget: null
  property var editTarget: null
  property var deleteTarget: null
  property var deleteOriginRef: AccountModel.chatRef("", "")
  property bool deleteForMe: true
  property var forwardTarget: null
  property var forwardOriginRef: AccountModel.chatRef("", "")
  property var pollOriginRef: AccountModel.chatRef("", "")
  property var pendingAttachments: []
  property string attachmentError: ""
  property string pendingStickerPath: ""
  property var composerStates: ({})
  property string composerChatKey: ""
  property string draftBeforeEdit: ""
  property var draftMentionsBeforeEdit: []
  property var selectedMentions: []
  property int mentionStart: -1
  property int mentionSelection: 0
  property string mentionQuery: ""
  property string pendingWriteChatKey: ""
  property bool pollMultiple: false
  property bool copyToastVisible: false
  property string demoTimelinePlaybackId: ""
  property string toastText: ""
  property string pendingOpenChatJid: ""
  property string pendingOpenChatAccount: ""
  property string demoSelectedJid: "demo-lab"
  property string demoSelectedAccount: "work"
  property string demoVoiceState: "idle"
  property string accountScope: ""
  property var demoChats: [
    { jid: "demo-lab", name: "OmaWhatsApp Lab", kind: "group", account: "work", account_label: "work", avatar_path: "__demo_avatar__", preview: "OmaWhatsApp is instant and native", timestamp: 1787539920, unread: 0, pinned: true },
    { jid: "demo-team", name: "Design team", kind: "group", account: "work", account_label: "work", avatar_path: "", preview: "The interaction pass is ready", timestamp: 1787539000, unread: 3, pinned: false },
    { jid: "demo-alex", name: "Alex", kind: "dm", account: "personal", account_label: "personal", avatar_path: "__demo_avatar__", preview: "Looks perfect — ship it", timestamp: 1787538200, unread: 1, pinned: false }
  ]
  property var demoItems: [
    { id: "demo-5", text: "Yep — shipped.", sender: "Sam Rivera", sender_jid: "sam@s.whatsapp.net", timestamp: 1787540100, from_me: false, done: false, media_type: "", mime_type: "", local_path: "", tags: [] },
    { id: "demo-1", text: "OmaWhatsApp is instant, native, and private #design", sender: "You", sender_jid: "", timestamp: 1787539920, from_me: true, done: false, media_type: "", mime_type: "", local_path: "", tags: ["design"], reactions: [{ emoji: "🔥", from_me: false }, { emoji: "🔥", from_me: true }], starred: true },
    { id: "demo-2a", text: "Two photos, one smooth send #capture", sender: "You", sender_jid: "", timestamp: 1787539200, from_me: true, done: false, media_type: "album", mime_type: "image/svg+xml", local_path: "__demo__", album_id: "demo-album", album_count: 2, tags: ["capture"], album_items: [
      { id: "demo-2a", text: "Two photos, one smooth send #capture", sender: "You", sender_jid: "", timestamp: 1787539200, from_me: true, media_type: "image", mime_type: "image/svg+xml", local_path: "__demo__", album_id: "demo-album", album_index: 0, album_count: 2 },
      { id: "demo-2b", text: "", sender: "You", sender_jid: "", timestamp: 1787539199, from_me: true, media_type: "image", mime_type: "image/svg+xml", local_path: "__demo_photo__", album_id: "demo-album", album_index: 1, album_count: 2 }
    ] },
    { id: "demo-3", text: "Review the private repo README and release checklist #ship", sender: "You", sender_jid: "", timestamp: 1787538000, from_me: true, done: false, media_type: "", mime_type: "", local_path: "", tags: ["ship"], quoted_id: "demo-1", quoted_sender: "You", quoted_text: "OmaWhatsApp is instant, native, and private #design" },
    { id: "demo-4", text: "https://github.com/openclaw/wacli #reference", sender: "You", sender_jid: "", timestamp: 1787536800, from_me: true, done: true, media_type: "", mime_type: "", local_path: "", tags: ["reference"] }
  ]
  property var demoMembers: [
    { jid: "sam@s.whatsapp.net", name: "Sam Rivera", phone: "+1 555 123 4567", role: "admin" },
    { jid: "alex@s.whatsapp.net", name: "Alex Kim", phone: "+1 555 765 4321", role: "member" },
    { jid: "nora@s.whatsapp.net", name: "Nora Ali", phone: "+1 555 246 8101", role: "member" }
  ]

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.moizibnyousaf.omawhatsapp"
  readonly property string helper: Quickshell.env("HOME") + "/.local/bin/omawhatsapp"
  readonly property bool notifyOn: !!root.service && root.service.notificationsEnabled
  readonly property bool notifyPreviewOn: !root.service || root.service.notificationsPreview
  readonly property bool notifyAvailable: !root.service || root.service.notifyAvailable
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property string fontFamily: Style.font.family
  readonly property color dim: Qt.rgba(
    foreground.r * 0.68 + background.r * 0.32,
    foreground.g * 0.68 + background.g * 0.32,
    foreground.b * 0.68 + background.b * 0.32, 1)
  readonly property color dimmer: Qt.rgba(
    foreground.r * 0.45 + background.r * 0.55,
    foreground.g * 0.45 + background.g * 0.55,
    foreground.b * 0.45 + background.b * 0.55, 1)
  readonly property bool narrow: window.width < Style.space(640)
  readonly property bool compact: window.width < Style.space(900)
  readonly property bool textEntryActive: composer.activeFocus
    || messageSearchField.activeFocus || chatSearchField.activeFocus
  readonly property var sourceItems: root.demoMode
    ? root.demoItems : (root.service ? root.service.messages : [])
  readonly property var sourceChats: root.demoMode
    ? root.demoChats : (root.service ? root.service.chats : [])
  readonly property var accountEntries: root.demoMode
    ? [{ account: "work", label: "work" },
       { account: "personal", label: "personal" }]
    : (root.service && Array.isArray(root.service.accounts)
      ? root.service.accounts : [])
  readonly property string displayGroupName: root.demoMode
    ? (root.demoChats.find(function(chat) { return chat.jid === root.demoSelectedJid }) || root.demoChats[0]).name
    : (root.service ? root.service.selectedChatName : "WhatsApp")
  readonly property string displayKind: root.demoMode
    ? (root.demoChats.find(function(chat) { return chat.jid === root.demoSelectedJid }) || root.demoChats[0]).kind
    : (root.service ? root.service.selectedChatKind : "chat")
  readonly property string selectedAccount: root.demoMode
    ? String(root.demoSelectedAccount || "")
    : String(root.service ? root.service.selectedChatAccount || "" : "")
  readonly property bool selectedStatusReady: root.demoMode || (!!root.service
    && root.service.statusReady
    && String(root.service.statusAccount || "") === root.selectedAccount)
  readonly property bool offlineForSelectedAccount: !root.demoMode
    && root.selectedStatusReady && root.service.offlineMode
  readonly property bool multiAccount: root.demoMode
    ? true : !!root.service && root.service.multiAccount === true
  readonly property var selectedChat: {
    var jid = root.demoMode ? root.demoSelectedJid
      : (root.service ? root.service.selectedChatJid : "")
    var account = root.selectedAccount
    return AccountModel.findChat(root.sourceChats, AccountModel.chatRef(account, jid))
  }
  readonly property var forwardCandidates: AccountModel.forwardTargetsForRef(
    root.sourceChats, root.forwardOriginRef)
  readonly property var visibleChats: {
    var needle = chatSearchField ? String(chatSearchField.text || "").trim().toLowerCase() : ""
    var scope = AccountModel.normalizeScope(root.accountScope, root.accountEntries)
    return AccountModel.filterChats(root.sourceChats, scope, needle, 0)
  }
  readonly property var visibleMessages: {
    var needle = messageSearchField ? String(messageSearchField.text || "").trim().toLowerCase() : ""
    var filtered = sourceItems.filter(function(item) {
      if (root.contentFilter === "media" && !item.media_type) return false
      if (root.contentFilter === "links" && String(item.text || "").indexOf("http") < 0) return false
      if (needle !== "" && String(item.text || "").toLowerCase().indexOf(needle) < 0) return false
      return true
    })
    return root.groupMediaAlbums(filtered)
  }
  readonly property var mediaGallery: {
    var values = []
    root.visibleMessages.forEach(function(item) {
      var candidates = item && item.album_items
          && typeof item.album_items.length === "number" ? item.album_items : [item]
      candidates.forEach(function(candidate) {
        if (!candidate || String(candidate.local_path || "") === "") return
        var media = String(candidate.media_type || "").toLowerCase()
        var mime = String(candidate.mime_type || "").toLowerCase()
        if (media === "image" || media === "video" || media === "gif"
            || media === "sticker" || mime.indexOf("image/") === 0
            || mime.indexOf("video/") === 0) values.push(candidate)
      })
    })
    return values
  }
  readonly property var mentionCandidates: {
    var source = root.demoMode ? root.demoMembers
      : (root.service && Array.isArray(root.service.members) ? root.service.members : [])
    var needle = String(root.mentionQuery || "").toLowerCase()
    return source.filter(function(member) {
      return needle === "" || String(member.name || "").toLowerCase().indexOf(needle) >= 0
        || String(member.phone || "").toLowerCase().indexOf(needle) >= 0
    }).slice(0, 8)
  }
  readonly property bool mentionCompletionVisible: root.mentionStart >= 0
    && root.displayKind === "group" && root.mentionCandidates.length > 0
  readonly property bool writeForCurrentChat: !root.demoMode && root.service
    && root.service.writing && AccountModel.sameRef(
      AccountModel.chatRef(root.service.activeWriteAccount,
                           root.service.activeWriteChatJid),
      root.currentChatRef())
  readonly property bool sendingAttachments: root.writeForCurrentChat
    && root.service.activeWriteKind === "files"
  readonly property bool voiceForCurrentChat: root.demoMode
    ? root.demoVoiceState !== "idle"
    : (root.service && AccountModel.sameRef(
        AccountModel.chatRef(root.service.voiceDraftAccount, root.service.voiceDraftJid),
        root.currentChatRef())
      && String(root.service.voiceState || "idle") !== "idle")
  readonly property var playbackCoordinator: root.service
    ? root.service.playback : null
  readonly property string activeTimelinePlaybackId: root.demoMode
    ? root.demoTimelinePlaybackId
    : (root.playbackCoordinator
      ? root.playbackCoordinator.messageFor(
          "app-timeline", root.currentChatRef()) : "")
  readonly property bool timelineMediaActive: root.opened && !mediaViewer.opened
  onTimelineMediaActiveChanged: if (!timelineMediaActive) {
    demoTimelinePlaybackId = ""
    if (playbackCoordinator)
      playbackCoordinator.releaseSurface("app-timeline")
  }

  KeyboardNavigation { id: keyboardNavigation }

  function groupMediaAlbums(items) {
    var albums = ({})
    items.forEach(function(item) {
      var albumId = String(item && item.album_id || "")
      if (albumId === "") return
      if (!albums[albumId]) albums[albumId] = []
      albums[albumId].push(item)
    })
    var emitted = ({})
    var output = []
    items.forEach(function(item) {
      var albumId = String(item && item.album_id || "")
      var members = albumId !== "" ? albums[albumId] : null
      if (!members || members.length < 2) {
        output.push(item)
        return
      }
      if (emitted[albumId]) return
      emitted[albumId] = true
      members.sort(function(left, right) {
        return Number(left.album_index || 0) - Number(right.album_index || 0)
      })
      var grouped = Object.assign({}, members[0])
      grouped.media_type = "album"
      grouped.album_items = members
      grouped.album_count = Math.max(Number(grouped.album_count || 0), members.length)
      output.push(grouped)
    })
    return output
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (error) {}
    var previousDemo = demoMode
    closingFromHost = false
    opened = true
    demoMode = payload.demo === true
    demoVoiceState = demoMode && payload.voice === true ? "review" : "idle"
    pendingOpenChatAccount = String(payload.account || "")
    pendingOpenChatJid = String(payload.jid || "")
    narrowConversation = payload.conversation === true
    narrowSearchOpen = false
    settingsOpen = false
    replyTarget = null
    editTarget = null
    keyboardNavigation.enterComposer()
    mediaViewer.closeViewer()
    var selectedFromPayload = false
    if (pendingOpenChatJid !== "") selectedFromPayload = selectPendingOpenChat()
    if (demoMode && payload.attachments === true) {
      pendingStickerPath = ""
      pendingAttachments = [
        String(Qt.resolvedUrl("assets/demo-capture.svg")),
        "file:///tmp/omawhatsapp-release-notes.pdf"
      ]
    } else if (demoMode || previousDemo) {
      pendingAttachments = []
      pendingStickerPath = ""
    }
    if (service) {
      service.appOpen = true
      if (!demoMode) {
        service.refresh()
        if (SettingsPolicy.shouldSelectWarmChat(
              demoMode, selectedFromPayload, pendingOpenChatJid, service.selectedChatJid)) {
          var warmChat = Array.isArray(service.chats)
            ? service.chats.find(function(chat) {
                return String(chat.jid || "") === String(service.selectedChatJid || "")
                  && String(chat.account || "") === String(service.selectedChatAccount || "")
              }) : null
          if (warmChat) service.selectChat(warmChat)
          else service.dismissNotifications(service.selectedChatJid,
                                            service.selectedChatAccount)
        }
      }
    }
    composerChatKey = currentChatKey()
    Qt.callLater(function() {
      if (demoMode && payload.viewer === true && root.mediaGallery.length > 0)
        mediaViewer.openAt(0)
      else if (demoMode && payload.mention === true) {
        composer.text = "@"
        composer.cursorPosition = composer.length
        root.updateMentionCompletion()
        root.focusComposer()
      }
      else root.focusComposer()
    })
  }

  function selectPendingOpenChat() {
    var account = String(pendingOpenChatAccount || "")
    var jid = String(pendingOpenChatJid || "")
    if (jid === "") return false
    var target = AccountModel.findChat(sourceChats, AccountModel.chatRef(account, jid))
    if (!target) return false
    pendingOpenChatAccount = ""
    pendingOpenChatJid = ""
    selectChat(target, "composer")
    return true
  }

  function close() {
    saveComposerState()
    closingFromHost = true
    settingsOpen = false
    mediaViewer.closeViewer()
    opened = false
    if (service) service.appOpen = false
    closingFromHost = false
  }

  function requestClose() {
    if (service && typeof service.closeApp === "function") service.closeApp()
    else close()
  }

  function currentChatIndex() {
    var ref = root.currentChatRef()
    for (var i = 0; i < root.visibleChats.length; i++) {
      if (AccountModel.sameRef(AccountModel.refOf(root.visibleChats[i]), ref)) return i
    }
    return -1
  }

  function focusComposer() {
    keyboardNavigation.enterComposer()
    composer.forceActiveFocus()
  }

  function focusMessages() {
    keyboardNavigation.enterMessages(root.visibleMessages.length)
    if (root.narrow && root.currentChatKey() !== "") root.narrowConversation = true
    keyboardHome.forceActiveFocus()
    if (root.visibleMessages.length > 0)
      messageList.positionViewAtIndex(root.cursorIndex, ListView.Contain)
  }

  function focusChats() {
    if (root.narrow) {
      root.narrowConversation = false
      root.narrowSearchOpen = false
    } else if (root.sidebarCollapsed) {
      root.sidebarCollapsed = false
    }
    keyboardNavigation.enterChats(root.visibleChats.length, root.currentChatIndex())
    keyboardHome.forceActiveFocus()
    if (root.visibleChats.length > 0)
      chatList.positionViewAtIndex(root.chatCursorIndex, ListView.Contain)
  }

  function focusChatSearch() {
    if (root.narrow) {
      root.narrowConversation = false
      root.narrowSearchOpen = false
    } else if (root.sidebarCollapsed) {
      root.sidebarCollapsed = false
    }
    keyboardNavigation.enterChatSearch()
    chatSearchField.forceActiveFocus()
    chatSearchField.selectAll()
  }

  function goBack() {
    if (root.voiceForCurrentChat && root.service
        && (root.service.voiceState === "recording"
            || root.service.voiceState === "preparing")) {
      root.service.stopVoiceRecording()
      return
    }
    if (settingsOpen) {
      settingsOpen = false
      root.focusComposer()
      return
    }
    if (messageSearchField.activeFocus) {
      if (messageSearchField.text !== "") messageSearchField.text = ""
      root.focusMessages()
      return
    }
    if (chatSearchField.activeFocus) {
      if (chatSearchField.text !== "") chatSearchField.text = ""
      root.focusChats()
      return
    }
    if (root.replyTarget || root.editTarget) {
      root.cancelComposerContext()
      return
    }
    var target = keyboardNavigation.backTarget()
    if (target === "messages") root.focusMessages()
    else if (target === "chats") root.focusChats()
    else root.requestClose()
  }

  function sendDraft() {
    var value = composer.text.trim()
    if (value === "" && pendingAttachments.length === 0) return
    if (demoMode) {
      demoItems = [{ id: "demo-" + Date.now(), text: value, sender: "You", sender_jid: "", timestamp: Math.floor(Date.now() / 1000), from_me: true, done: false, media_type: "", mime_type: "", local_path: "", tags: [] }].concat(demoItems)
      composer.text = ""
      pendingAttachments = []
      pendingStickerPath = ""
      selectedMentions = []
      closeMentionCompletion()
      attachmentError = ""
      cancelComposerContext(false)
      return
    }
    if (!service || service.writing) return
    pendingWriteChatKey = currentChatKey()
    var chatRef = currentChatRef()
    var mentionJids = activeMentionJids()
    var snapshot = liveComposerState()
    var request = ({})
    var kind = ""
    var started = false
    if (pendingStickerPath !== "") {
      if (value !== "") {
        attachmentError = "Stickers cannot have captions; send the text separately."
        return
      }
      kind = "sticker"
      request = {
        path: String(pendingStickerPath || ""),
        reply_id: replyTarget ? String(replyTarget.id || "") : ""
      }
      pendingComposerSnapshot = snapshot
      pendingWriteKind = kind
      started = service.sendSticker(chatRef, request.path, request.reply_id, "app")
      if (started) applyLiveComposerState(
        ComposerModel.startedState(snapshot, kind, request))
      else {
        pendingComposerSnapshot = null
        pendingWriteKind = ""
        pendingWriteChatKey = ""
      }
      return
    }
    if (pendingAttachments.length > 0) {
      if (mentionJids.length > 0) {
        attachmentError = "Send mentions as a text message; attachment captions cannot tag people yet."
        return
      }
      kind = "files"
      request = {
        paths: pendingAttachments.slice(),
        caption: value,
        reply_id: replyTarget ? String(replyTarget.id || "") : ""
      }
      pendingComposerSnapshot = snapshot
      pendingWriteKind = kind
      started = service.sendFilesReply(chatRef, request.paths, request.caption,
        request.reply_id, "app")
      if (started) applyLiveComposerState(
        ComposerModel.startedState(snapshot, kind, request))
      else {
        pendingComposerSnapshot = null
        pendingWriteKind = ""
        pendingWriteChatKey = ""
      }
      return
    }
    kind = editTarget ? "edit" : "send"
    request = editTarget ? {
      id: String(editTarget.id || ""), text: value
    } : {
      text: value,
      reply_id: replyTarget ? String(replyTarget.id || "") : "",
      mentions: mentionJids.slice()
    }
    pendingComposerSnapshot = snapshot
    pendingWriteKind = kind
    started = editTarget
      ? service.editMessage(chatRef, editTarget, value, "app")
      : service.sendText(chatRef, value, request.reply_id,
          request.mentions, "app")
    if (started) applyLiveComposerState(
      ComposerModel.startedState(snapshot, kind, request))
    else {
      pendingComposerSnapshot = null
      pendingWriteKind = ""
      pendingWriteChatKey = ""
    }
  }

  function toggleVoiceRecording() {
    if (demoMode) {
      root.showToast("voice notes record only in a real chat")
      return false
    }
    if (!service || currentChatKey() === "") return false
    if (service.writing) {
      attachmentError = "Finish the current WhatsApp action before recording."
      return false
    }
    if (String(service.voiceState || "idle") === "idle"
        && (composer.text.trim() !== "" || pendingAttachments.length > 0
            || pendingStickerPath !== "" || editTarget !== null)) {
      attachmentError = "Send or clear the current draft before recording a voice note."
      return false
    }
    attachmentError = ""
    return service.toggleVoice(selectedAccount, currentJid(), displayGroupName,
      replyTarget ? replyTarget.id : "", "app")
  }

  function closeMentionCompletion() {
    mentionStart = -1
    mentionQuery = ""
    mentionSelection = 0
  }

  function updateMentionCompletion() {
    if (displayKind !== "group" || editTarget !== null) {
      closeMentionCompletion()
      return
    }
    var cursor = composer.cursorPosition
    var before = String(composer.text || "").slice(0, cursor)
    var match = before.match(/(^|\s)@([^@\s]*)$/)
    if (!match) {
      closeMentionCompletion()
      return
    }
    mentionQuery = String(match[2] || "")
    mentionStart = cursor - mentionQuery.length - 1
    mentionSelection = Math.min(mentionSelection, Math.max(0, mentionCandidates.length - 1))
  }

  function chooseMention(index) {
    var candidate = mentionCandidates[Math.max(0, Math.min(index, mentionCandidates.length - 1))]
    if (!candidate || mentionStart < 0) return
    var cursor = composer.cursorPosition
    var insertion = "@" + String(candidate.name || candidate.phone || "WhatsApp member") + " "
    var value = String(composer.text || "")
    composer.text = value.slice(0, mentionStart) + insertion + value.slice(cursor)
    composer.cursorPosition = mentionStart + insertion.length
    var next = selectedMentions.slice()
    if (!next.some(function(member) { return String(member.jid) === String(candidate.jid) }))
      next.push({ jid: String(candidate.jid), name: String(candidate.name || "") })
    selectedMentions = next
    closeMentionCompletion()
    root.focusComposer()
  }

  function activeMentionJids() {
    var value = String(composer.text || "")
    return selectedMentions.filter(function(member) {
      return value.indexOf("@" + String(member.name || "")) >= 0
    }).map(function(member) { return String(member.jid || "") })
      .filter(function(jid) { return jid !== "" })
  }

  function pasteDraft() {
    if (demoMode) return
    if (service && !service.writing) {
      pendingWriteChatKey = currentChatKey()
      service.pasteClipboard(currentChatRef(), "app")
    }
  }

  function currentChatRef() {
    var jid = demoMode ? String(demoSelectedJid || "")
      : String(service ? service.selectedChatJid || "" : "")
    return AccountModel.chatRef(root.selectedAccount, jid)
  }

  function currentJid() {
    return currentChatRef().jid
  }

  function currentChatKey() {
    return currentChatRef().key
  }

  function saveComposerState() {
    var key = String(composerChatKey || currentChatKey())
    if (key === "") return
    var states = Object.assign({}, composerStates)
    var hasValue = composer.text !== "" || pendingAttachments.length > 0
      || replyTarget !== null || editTarget !== null || attachmentError !== ""
    if (hasValue) {
      states[key] = {
        text: String(composer.text || ""),
        attachments: pendingAttachments.slice(),
        stickerPath: String(pendingStickerPath || ""),
        reply: replyTarget,
        edit: editTarget,
        draftBeforeEdit: String(draftBeforeEdit || ""),
        draftMentionsBeforeEdit: draftMentionsBeforeEdit.slice(),
        mentions: selectedMentions.slice(),
        error: String(attachmentError || "")
      }
    } else delete states[key]
    composerStates = states
  }

  function clearComposerState(key) {
    var value = String(key || "")
    if (value === "") return
    var states = Object.assign({}, composerStates)
    delete states[value]
    composerStates = states
  }

  function restoreComposerState(key) {
    var value = String(key || "")
    composerChatKey = value
    var state = composerStates[value] || null
    composer.text = state ? String(state.text || "") : ""
    pendingAttachments = state && Array.isArray(state.attachments)
      ? state.attachments.slice() : []
    pendingStickerPath = state ? String(state.stickerPath || "") : ""
    replyTarget = state ? state.reply || null : null
    editTarget = state ? state.edit || null : null
    draftBeforeEdit = state ? String(state.draftBeforeEdit || "") : ""
    draftMentionsBeforeEdit = state && Array.isArray(state.draftMentionsBeforeEdit)
      ? state.draftMentionsBeforeEdit.slice() : []
    selectedMentions = state && Array.isArray(state.mentions) ? state.mentions.slice() : []
    closeMentionCompletion()
    attachmentError = state ? String(state.error || "") : ""
  }

  function liveComposerState() {
    return {
      text: String(composer.text || ""),
      attachments: pendingAttachments.slice(),
      stickerPath: String(pendingStickerPath || ""),
      reply: replyTarget,
      edit: editTarget,
      draftBeforeEdit: String(draftBeforeEdit || ""),
      draftMentionsBeforeEdit: draftMentionsBeforeEdit.slice(),
      mentions: selectedMentions.slice(),
      error: String(attachmentError || "")
    }
  }

  function applyLiveComposerState(state) {
    var value = state || ({})
    composer.text = String(value.text || "")
    pendingAttachments = Array.isArray(value.attachments)
      ? value.attachments.slice() : []
    pendingStickerPath = String(value.stickerPath || "")
    replyTarget = value.reply || null
    editTarget = value.edit || null
    draftBeforeEdit = String(value.draftBeforeEdit || "")
    draftMentionsBeforeEdit = Array.isArray(value.draftMentionsBeforeEdit)
      ? value.draftMentionsBeforeEdit.slice() : []
    selectedMentions = Array.isArray(value.mentions) ? value.mentions.slice() : []
    attachmentError = String(value.error || "")
    closeMentionCompletion()
  }

  function hasComposerValue(state) {
    var value = state || ({})
    return String(value.text || "") !== ""
      || (Array.isArray(value.attachments) && value.attachments.length > 0)
      || String(value.stickerPath || "") !== ""
      || value.reply !== null && value.reply !== undefined
      || value.edit !== null && value.edit !== undefined
      || String(value.error || "") !== ""
  }

  function syncComposerToSelectedChat() {
    if (demoMode) return
    var key = currentChatKey()
    if (key === composerChatKey) return
    saveComposerState()
    restoreComposerState(key)
  }

  function addAttachments(values, kind) {
    var result = ComposerModel.pickedState(
      liveComposerState(), values, kind, 10)
    applyLiveComposerState(result.state)
    if (!demoMode && service && result.rejected.length > 0)
      service.discardStages(result.rejected)
  }

  function acceptFilePickerResult(originRef, values, kind) {
    var target = AccountModel.chatRef(
      originRef ? originRef.account : "", originRef ? originRef.jid : "")
    var incoming = Array.isArray(values) ? values.slice() : []
    if (target.jid === "") {
      if (!demoMode && service) service.discardStages(incoming)
      return false
    }
    // `composerChatKey` owns the mounted fields until the deferred selection
    // sync runs. Routing by the Service selection in that gap would save the
    // picker result and then immediately overwrite it with the mounted draft.
    if (target.key === composerChatKey) {
      addAttachments(incoming, kind)
      return true
    }

    var states = Object.assign({}, composerStates)
    var result = ComposerModel.pickedState(states[target.key] || ({}),
                                           incoming, kind, 10)
    if (hasComposerValue(result.state)) states[target.key] = result.state
    else delete states[target.key]
    composerStates = states
    if (!demoMode && service && result.rejected.length > 0)
      service.discardStages(result.rejected)
    return true
  }

  function removeAttachment(index) {
    var next = pendingAttachments.slice()
    var removed = next.splice(index, 1)
    if (!demoMode && service) service.discardStages(removed)
    pendingAttachments = next
    if (next.indexOf(pendingStickerPath) < 0) pendingStickerPath = ""
    attachmentError = ""
  }

  function attachmentName(url) {
    var parts = String(url || "").split("/")
    try { return decodeURIComponent(parts[parts.length - 1] || "Attachment") }
    catch (error) { return parts[parts.length - 1] || "Attachment" }
  }

  function attachmentIsImage(url) {
    return /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(root.attachmentName(url))
  }

  function localFileUrl(path) {
    return "file://" + String(path || "").split("/")
      .map(function(part) { return encodeURIComponent(part) }).join("/")
  }

  function openFilePicker(kind) {
    var origin = currentChatRef()
    if (filePickerProcess.running || origin.jid === "") return
    var title = "Add documents"
    var command = ["/usr/bin/zenity", "--file-selection", "--multiple",
      "--separator=\n", "--title=" + title]
    if (kind === "media") {
      title = "Add photos and videos"
      command = ["/usr/bin/zenity", "--file-selection", "--multiple",
        "--separator=\n", "--title=" + title,
        "--file-filter=Photos and videos | *.png *.jpg *.jpeg *.webp *.gif *.bmp *.mp4 *.mov *.mkv *.webm",
        "--file-filter=All files | *"]
    } else if (kind === "audio") {
      title = "Add audio"
      command = ["/usr/bin/zenity", "--file-selection", "--multiple",
        "--separator=\n", "--title=" + title,
        "--file-filter=Audio | *.mp3 *.m4a *.aac *.ogg *.opus *.wav *.flac",
        "--file-filter=All files | *"]
    } else if (kind === "sticker") {
      title = "Add a WebP sticker"
      command = ["/usr/bin/zenity", "--file-selection", "--title=" + title,
        "--file-filter=WhatsApp stickers | *.webp"]
    }
    filePickerProcess.kind = kind
    filePickerProcess.originRef = AccountModel.chatRef(origin.account, origin.jid)
    filePickerProcess.command = command
    filePickerProcess.running = true
  }

  function copyText(value) {
    var text = String(value || "")
    if (text === "" || clipboardProcess.running) return
    clipboardProcess.payload = text
    clipboardProcess.stdinEnabled = true
    clipboardProcess.running = true
  }

  function showCopyToast() {
    showToast("copied to clipboard")
  }

  function showToast(message) {
    toastText = String(message || "")
    copyToastVisible = true
    copyToastTimer.restart()
  }

  function selectChat(chat, focusTarget) {
    if (!chat) return
    saveComposerState()
    messageSearchField.text = ""
    cursorIndex = 0
    if (demoMode) {
      demoSelectedAccount = String(chat.account || "")
      demoSelectedJid = String(chat.jid)
    }
    else if (service) service.selectChat(chat)
    restoreComposerState(AccountModel.refOf(chat).key)
    if (narrow) narrowConversation = true
    if (focusTarget === "messages") root.focusMessages()
    else root.focusComposer()
  }

  function selectChatAt(index) {
    var position = Number(index)
    if (position < 0 || position >= visibleChats.length) return
    chatCursorIndex = position
    chatList.positionViewAtIndex(position, ListView.Contain)
    selectChat(visibleChats[position])
  }

  function moveChatCursor(delta) {
    if (visibleChats.length === 0) return
    keyboardNavigation.moveChats(delta, visibleChats.length)
    chatList.currentIndex = chatCursorIndex
    chatList.positionViewAtIndex(chatCursorIndex, ListView.Contain)
  }

  function openChatCursor() {
    if (visibleChats.length === 0) return
    chatCursorIndex = keyboardNavigation.openChat(visibleChats.length)
    selectChat(visibleChats[chatCursorIndex], "composer")
  }

  function toggleSidebar() {
    if (root.narrow) {
      if (root.narrowConversation) root.narrowConversation = false
      else if (root.currentChatKey() !== "") root.narrowConversation = true
    } else {
      root.sidebarCollapsed = !root.sidebarCollapsed
    }
    Qt.callLater(function() {
      if ((root.narrow && root.narrowConversation)
          || (!root.narrow && root.sidebarCollapsed)) root.focusMessages()
      else root.focusChats()
    })
  }

  function startReply(item) {
    replyTarget = item
    editTarget = null
    root.focusComposer()
  }

  function startEdit(item) {
    if (!editTarget) draftBeforeEdit = String(composer.text || "")
    if (!editTarget) draftMentionsBeforeEdit = selectedMentions.slice()
    editTarget = item
    replyTarget = null
    selectedMentions = []
    closeMentionCompletion()
    composer.text = String(item.text || "")
    root.focusComposer()
    composer.cursorPosition = composer.length
  }

  function requestDelete(item, forMe) {
    deleteTarget = item
    deleteOriginRef = currentChatRef()
    deleteForMe = forMe
    deleteConfirm.open()
  }

  function dismissDelete() {
    deleteTarget = null
    deleteOriginRef = AccountModel.chatRef("", "")
    deleteConfirm.close()
  }

  function confirmDelete() {
    var target = deleteTarget
    var origin = deleteOriginRef
    var forMe = deleteForMe
    dismissDelete()
    if (demoMode || !service || !target || String(origin.jid || "") === "")
      return false
    return service.deleteMessage(origin, target, forMe, "app")
  }

  function startForward(item) {
    forwardTarget = item
    forwardOriginRef = currentChatRef()
    forwardSearch.text = ""
    forwardPicker.open()
    Qt.callLater(function() { forwardSearch.forceActiveFocus() })
  }

  function dismissForward() {
    forwardTarget = null
    forwardOriginRef = AccountModel.chatRef("", "")
    forwardPicker.close()
  }

  function forwardTo(chat) {
    var target = AccountModel.refOf(chat)
    var origin = forwardOriginRef
    var item = forwardTarget
    if (demoMode || !service || !item || String(origin.jid || "") === ""
        || String(target.account || "") !== String(origin.account || "")
        || String(target.jid || "") === "") return false
    var started = service.forwardMessage(origin, item, target.jid, "app")
    if (started) dismissForward()
    return started
  }

  function startPoll() {
    pollOriginRef = currentChatRef()
    pollComposer.open()
    Qt.callLater(function() { pollQuestion.forceActiveFocus() })
  }

  function submitPoll(question, options, multiple) {
    var origin = pollOriginRef
    var values = Array.isArray(options) ? options.slice() : []
    if (demoMode || !service || service.writing || String(origin.jid || "") === "")
      return false
    pendingWriteChatKey = String(origin.key || "")
    return service.sendPoll(origin, String(question || ""), values,
      multiple === true ? values.length : 1, "app")
  }

  function cancelComposerContext(restoreDraft) {
    var wasEditing = editTarget !== null
    replyTarget = null
    editTarget = null
    if (wasEditing && restoreDraft !== false) composer.text = draftBeforeEdit
    if (wasEditing && restoreDraft !== false) selectedMentions = draftMentionsBeforeEdit.slice()
    draftBeforeEdit = ""
    draftMentionsBeforeEdit = []
    root.focusComposer()
  }

  function formatTime(seconds) {
    if (!seconds) return ""
    return Qt.formatDateTime(new Date(Number(seconds) * 1000), "ddd h:mm AP")
  }

  function localMediaUrl(path) {
    var value = String(path || "")
    if (value === "__demo__") return Qt.resolvedUrl("assets/demo-capture.svg")
    if (value === "__demo_photo__") return Qt.resolvedUrl("assets/demo-photo.svg")
    return value === "" ? "" : encodeURI("file://" + value)
  }

  function openMedia(path) {
    var value = String(path || "")
    if (value === "") return
    var index = -1
    for (var i = 0; i < root.mediaGallery.length; i++) {
      if (String(root.mediaGallery[i].local_path || "") === value) {
        index = i
        break
      }
    }
    if (index >= 0) mediaViewer.openAt(index)
    else if (value !== "__demo__") Quickshell.execDetached(["/usr/bin/xdg-open", value])
  }

  function requestTimelinePlayback(messageId) {
    if (demoMode || !playbackCoordinator) {
      demoTimelinePlaybackId = String(messageId || "")
      return demoTimelinePlaybackId !== ""
    }
    return playbackCoordinator.acquire(
      "app-timeline", currentChatRef(), messageId)
  }

  function openMediaExternal(path) {
    var value = String(path || "")
    if (value === "" || value === "__demo__" || mediaOpenProcess.running) return
    mediaOpenProcess.payload = JSON.stringify({ path: value })
    mediaOpenProcess.command = [root.helper, "open-media"]
    mediaOpenProcess.stdinEnabled = true
    mediaOpenProcess.running = true
  }

  function toggleItem(item) {
    if (!item) return
    if (demoMode) {
      demoItems = demoItems.map(function(candidate) {
        if (candidate.id !== item.id) return candidate
        var copy = Object.assign({}, candidate)
        copy.done = copy.done !== true
        return copy
      })
    }
  }

  function moveCursor(delta) {
    if (visibleMessages.length === 0) return
    keyboardNavigation.moveMessages(delta, visibleMessages.length)
    messageList.currentIndex = cursorIndex
    messageList.positionViewAtIndex(cursorIndex, ListView.Contain)
  }

  function toggleCursorItem() {
    if (visibleMessages.length === 0) return
    root.openMedia(visibleMessages[Math.max(0, Math.min(cursorIndex, visibleMessages.length - 1))].local_path)
  }

  Connections {
    target: root.service
    function onSelectedChatJidChanged() {
      if (root.playbackCoordinator)
        root.playbackCoordinator.releaseSurface("app-timeline")
      Qt.callLater(root.syncComposerToSelectedChat)
    }
    function onSelectedChatAccountChanged() {
      if (root.playbackCoordinator)
        root.playbackCoordinator.releaseSurface("app-timeline")
      Qt.callLater(root.syncComposerToSelectedChat)
    }
    function onChatsChanged() {
      if (root.opened && root.pendingOpenChatJid !== "") root.selectPendingOpenChat()
    }
    function onTextPasted(text, chatRef, owner) {
      if (!ComposerModel.ownsOperation(owner, "app")) return
      var key = String(chatRef && chatRef.key || root.pendingWriteChatKey)
      if (key === root.composerChatKey) {
        composer.insert(composer.cursorPosition, String(text || ""))
        root.focusComposer()
      } else {
        var states = Object.assign({}, root.composerStates)
        var state = states[key] || { text: "", attachments: [], reply: null, edit: null, draftBeforeEdit: "" }
        state.text = String(state.text || "") + String(text || "")
        states[key] = state
        root.composerStates = states
      }
      root.pendingWriteChatKey = ""
    }
    function onAttachmentPasted(path, chatRef, owner) {
      if (!ComposerModel.ownsOperation(owner, "app")) return
      var key = String(chatRef && chatRef.key || root.pendingWriteChatKey)
      if (key === root.composerChatKey) root.addAttachments([path])
      else {
        var states = Object.assign({}, root.composerStates)
        var state = states[key] || { text: "", attachments: [], reply: null, edit: null, draftBeforeEdit: "" }
        var attachments = Array.isArray(state.attachments) ? state.attachments.slice() : []
        if (attachments.indexOf(path) < 0 && attachments.length < 10) attachments.push(path)
        else if (attachments.indexOf(path) < 0 && root.service)
          root.service.discardStage(path)
        state.attachments = attachments
        states[key] = state
        root.composerStates = states
      }
      root.pendingWriteChatKey = ""
    }
    function onWriteCompleted(kind, chatRef, request, owner) {
      if (!ComposerModel.ownsOperation(owner, "app")) return
      var key = String(chatRef && chatRef.key || root.pendingWriteChatKey)
      var sameChat = key === root.composerChatKey
      // Only operations that actually consume composer content may clear its
      // saved draft. Reactions, downloads, menu actions, forwarding, polls,
      // and voice completion must never erase an unrelated draft for the chat.
      if (["send", "files", "sticker", "edit"].indexOf(kind) >= 0) {
        if (sameChat) {
          root.applyLiveComposerState(
            ComposerModel.completedState(root.liveComposerState(), kind, request))
          root.clearComposerState(key)
        } else if (key !== "") {
          var states = Object.assign({}, root.composerStates)
          var completed = ComposerModel.completedState(states[key] || ({}), kind, request)
          if (root.hasComposerValue(completed)) states[key] = completed
          else delete states[key]
          root.composerStates = states
        }
      }
      root.pendingComposerSnapshot = null
      root.pendingWriteKind = ""
      root.pendingWriteChatKey = ""
      if (sameChat && kind === "poll") {
        pollQuestion.text = ""
        pollOptions.text = ""
      }
      if (sameChat && kind === "voice") root.cancelComposerContext(false)
      if (kind === "forward") root.forwardTarget = null
      if (sameChat) root.focusComposer()
    }
    function onWriteFailed(message, chatRef, details, owner) {
      if (!ComposerModel.ownsOperation(owner, "app")) return
      var key = String(chatRef && chatRef.key || root.pendingWriteChatKey)
      var sameChat = key === root.composerChatKey
      var kind = String(details && details.kind || root.pendingWriteKind)
      var request = details && details.request ? details.request : ({})
      var snapshot = key === root.pendingWriteChatKey
        ? root.pendingComposerSnapshot : null
      if (sameChat) {
        if (snapshot) root.applyLiveComposerState(ComposerModel.failedState(
          root.liveComposerState(), kind, request, snapshot, details))
        else if (kind === "files") root.pendingAttachments
          = ComposerModel.remainingAttachments(root.pendingAttachments, details)
        root.attachmentError = String(message || "WhatsApp could not complete that request.")
      } else if (key !== "") {
        var states = Object.assign({}, root.composerStates)
        var state = states[key] || {
          text: "", attachments: [], reply: null, edit: null,
          draftBeforeEdit: "", mentions: [], error: ""
        }
        if (snapshot) state = ComposerModel.failedState(
          state, kind, request, snapshot, details)
        else if (kind === "files") state.attachments
          = ComposerModel.remainingAttachments(state.attachments, details)
        state.error = String(message || "WhatsApp could not complete that request.")
        states[key] = state
        root.composerStates = states
      }
      root.pendingComposerSnapshot = null
      root.pendingWriteKind = ""
      root.pendingWriteChatKey = ""
      if (sameChat) root.focusComposer()
    }
    function onControlCompleted(kind) {
      if (kind === "sync-mode")
        root.showToast(root.offlineForSelectedAccount
          ? "offline · local archive stays available" : "online · background sync resumed")
      if (kind === "notify-mode")
        root.showToast(!root.notifyOn
          ? "notifications off · bar badge only"
          : (root.notifyPreviewOn ? "notifications on · shows message preview"
            : "notifications on · chat names only"))
    }
    function onControlFailed(message) {
      root.showToast(String(message || "setting could not be changed"))
    }
    function onSettingsCompleted() {
      root.showToast("settings saved privately on this device")
    }
    function onSettingsFailed(message) {
      root.showToast(String(message || "settings could not be saved"))
    }
  }

  Timer {
    id: searchDebounce
    interval: 150
    repeat: false
    onTriggered: if (!root.demoMode && root.service) root.service.search(messageSearchField.text)
  }

  FloatingWindow {
    id: window
    objectName: "omawhatsappWindow"
    visible: root.opened
    title: "OmaWhatsApp"
    color: root.background
    implicitWidth: Style.space(1080)
    implicitHeight: Style.space(720)
    minimumSize: Qt.size(Style.space(360), Style.space(460))

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }

    FocusScope {
      id: focusScope
      objectName: "omawhatsappFocusScope"
      anchors.fill: parent
      focus: true

      Item { id: keyboardHome; width: 1; height: 1 }

      Shortcut {
        sequence: "Ctrl+O"
        context: Qt.WindowShortcut
        onActivated: root.openFilePicker("document")
      }

      Shortcut {
        sequence: "Ctrl+Shift+O"
        context: Qt.WindowShortcut
        onActivated: root.openFilePicker("media")
      }

      Shortcut {
        sequence: "Ctrl+Shift+V"
        context: Qt.WindowShortcut
        autoRepeat: false
        onActivated: root.toggleVoiceRecording()
      }

      Shortcut {
        sequence: "Ctrl+B"
        context: Qt.WindowShortcut
        onActivated: root.toggleSidebar()
      }

      Process {
        id: filePickerProcess
        property string kind: "document"
        property var originRef: AccountModel.chatRef("", "")
        command: []
        stdout: StdioCollector { id: pickerOutput }
        stderr: StdioCollector { id: pickerError }
        onExited: function(exitCode) {
          var target = originRef
          originRef = AccountModel.chatRef("", "")
          if (exitCode !== 0) return
          var paths = String(pickerOutput.text || "").split(/\r?\n/)
            .map(function(path) { return path.trim() })
            .filter(function(path) { return path.startsWith("/") })
            .map(function(path) { return root.localFileUrl(path) })
          root.acceptFilePickerResult(target,
            kind === "sticker" ? paths.slice(0, 1) : paths, kind)
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
          if (exitCode === 0) root.showCopyToast()
        }
      }

      Process {
        id: mediaOpenProcess
        property string payload: ""
        command: []
        stdinEnabled: true
        stdout: StdioCollector { id: mediaOpenOutput }
        stderr: StdioCollector { id: mediaOpenError }
        onStarted: {
          write(payload + "\n")
          payload = ""
          stdinEnabled = false
        }
        onExited: function(exitCode) {
          var result = null
          try { result = JSON.parse(String(mediaOpenOutput.text || "{}")) }
          catch (error) {}
          if (exitCode !== 0 || !result || result.ok !== true)
            root.attachmentError = (result && result.error)
              || String(mediaOpenError.text || "External media could not be opened.").trim()
        }
      }

      Timer {
        id: copyToastTimer
        interval: 1800
        repeat: false
        onTriggered: root.copyToastVisible = false
      }

      Rectangle {
        z: 200
        visible: root.copyToastVisible
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(98)
        width: copyToastLabel.implicitWidth + Style.space(30)
        height: Style.space(42)
        radius: Style.cornerRadius
        color: root.background
        border.width: 1
        border.color: root.accent

        Text {
          textFormat: Text.PlainText
          id: copyToastLabel
          anchors.centerIn: parent
          text: "●  " + root.toastText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.copyToastVisible = false
        }
      }

      DropArea {
        anchors.fill: parent
        onDropped: function(drop) {
          if (drop.hasUrls) {
            root.addAttachments(drop.urls)
            drop.acceptProposedAction()
          }
        }
      }

      Keys.onPressed: function(event) {
        if (mediaViewer.opened) return
        if (root.settingsOpen) {
          if (event.key === Qt.Key_Escape) root.settingsOpen = false
          event.accepted = true
          return
        }
        if ((event.modifiers & Qt.ControlModifier)
            && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
          root.selectChatAt(event.key - Qt.Key_1)
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.goBack()
          event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
          messageSearchField.forceActiveFocus()
          messageSearchField.selectAll()
          event.accepted = true
        } else if (keyboardNavigation.wantsChatSearch(event.key, root.textEntryActive)) {
          root.focusChatSearch()
          event.accepted = true
        } else if (event.key === Qt.Key_C && !root.textEntryActive) {
          root.focusComposer()
          event.accepted = true
        } else if (!root.textEntryActive
                   && (event.key === Qt.Key_J || event.key === Qt.Key_Down)) {
          if (root.keyboardContext === "chats") root.moveChatCursor(1)
          else if (root.keyboardContext === "messages") root.moveCursor(1)
          event.accepted = true
        } else if (!root.textEntryActive
                   && (event.key === Qt.Key_K || event.key === Qt.Key_Up)) {
          if (root.keyboardContext === "chats") root.moveChatCursor(-1)
          else if (root.keyboardContext === "messages") root.moveCursor(-1)
          event.accepted = true
        } else if (root.keyboardContext === "chats"
                   && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
          root.openChatCursor()
          event.accepted = true
        } else if (!root.textEntryActive
                   && root.keyboardContext === "messages" && event.key === Qt.Key_Space) {
          root.toggleCursorItem()
          event.accepted = true
        }
      }

      // ------------------------------------------------------------ header

      Item {
        id: appHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(48)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(9)

          Text {
            textFormat: Text.PlainText
            text: "󰖣"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge
          }

          Text {
            textFormat: Text.PlainText
            text: "OmaWhatsApp"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            id: accountLabel
            visible: root.multiAccount
            anchors.verticalCenter: parent.verticalCenter
            text: "󰀄 " + (root.selectedChat
              ? AccountModel.labelOf(root.selectedChat) : root.selectedAccount)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Rectangle {
            id: notifyModeButton
            height: Style.space(28)
            width: notifyModeLabel.implicitWidth + Style.space(20)
            radius: height / 2
            color: notifyModeMouse.containsMouse
              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            border.width: !root.demoMode && root.notifyOn ? 1 : 0
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.65)

            Text {
              textFormat: Text.PlainText
              id: notifyModeLabel
              anchors.centerIn: parent
              text: !root.notifyOn ? "󰂛 quiet"
                : (!root.notifyAvailable ? "󰂚 notify · unavailable"
                  : (root.notifyPreviewOn ? "󰂚 notify" : "󰂚 notify · names"))
              color: !root.notifyOn ? root.dim
                : (root.notifyAvailable ? root.accent : root.urgent)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: notifyModeMouse
              anchors.fill: parent
              enabled: !root.demoMode && root.service && !root.service.controlWriting
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              // Left click switches popups on or off; right click drops the preview.
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton)
                  root.service.setNotifications(null, !root.notifyPreviewOn)
                else
                  root.service.setNotifications(!root.notifyOn, null)
              }
            }
          }

          Rectangle {
            id: syncModeButton
            height: Style.space(28)
            width: syncModeLabel.implicitWidth + Style.space(26)
            radius: height / 2
            color: syncModeMouse.containsMouse
              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            border.width: root.offlineForSelectedAccount ? 1 : 0
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.65)

            Rectangle {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(7)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(6)
              height: width
              radius: width / 2
              color: root.demoMode || (root.selectedStatusReady && root.service
                && (root.service.syncActive || root.offlineForSelectedAccount))
                ? root.accent : root.urgent
              opacity: root.service && root.service.syncActive ? 0.9 : 0.55
            }

            Text {
              textFormat: Text.PlainText
              id: syncModeLabel
              anchors.right: parent.right
              anchors.rightMargin: Style.space(7)
              anchors.verticalCenter: parent.verticalCenter
              text: root.demoMode ? "preview"
                : (!root.selectedStatusReady ? "loading"
                  : (root.offlineForSelectedAccount ? "offline"
                  : (root.service && root.service.syncActive ? "online" : "reconnecting")))
              color: root.offlineForSelectedAccount ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: syncModeMouse
              anchors.fill: parent
              enabled: !root.demoMode && root.service && root.selectedStatusReady
                && !root.service.controlWriting
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.service.setOnline(root.offlineForSelectedAccount)
            }
          }

          Rectangle {
            width: Style.space(30)
            height: width
            radius: Style.cornerRadius
            color: settingsMouse.containsMouse || root.settingsOpen
              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "󰒓"
              color: root.settingsOpen ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            MouseArea {
              id: settingsMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingsOpen = !root.settingsOpen
            }
          }

          Rectangle {
            width: Style.space(30)
            height: width
            radius: Style.cornerRadius
            color: refreshMouse.containsMouse
              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "↻"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            MouseArea {
              id: refreshMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: if (root.service) root.service.refresh()
            }
          }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
        }
      }

      // ---------------------------------------------------------- settings

      Item {
        z: 400
        visible: root.settingsOpen
        anchors.fill: parent

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(0, 0, 0, 0.58)
          MouseArea {
            anchors.fill: parent
            onClicked: root.settingsOpen = false
          }
        }

        Rectangle {
          id: settingsCard
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(28), Style.space(560))
          height: Math.min(parent.height - Style.space(28), settingsContent.implicitHeight + Style.space(32))
          radius: Style.cornerRadius
          color: root.background
          border.width: 1
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.52)

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { mouse.accepted = true }
          }

          Flickable {
            id: settingsScroller
            anchors.fill: parent
            anchors.margins: Style.space(16)
            contentWidth: width
            contentHeight: settingsContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: settingsContent
              width: settingsScroller.width
              spacing: Style.space(10)

            Item {
              width: parent.width
              height: Style.space(42)
              Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)
                Text {
                  textFormat: Text.PlainText
                  text: "OmaWhatsApp settings"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.DemiBold
                }
                Text {
                  textFormat: Text.PlainText
                  text: "Private, local, and explicit by default"
                  color: root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                height: width
                radius: Style.cornerRadius
                color: closeSettingsHover.hovered
                  ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "×"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
                HoverHandler { id: closeSettingsHover }
                TapHandler { onTapped: root.settingsOpen = false }
              }
            }

            Rectangle {
              width: parent.width
              height: privateReadingColumn.implicitHeight + Style.space(24)
              radius: Style.cornerRadius
              color: root.service && root.service.sendReadReceipts
                ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.09)
                : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
              border.width: 1
              border.color: root.service && root.service.sendReadReceipts
                ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.45)
                : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
              Column {
                id: privateReadingColumn
                anchors.left: parent.left
                anchors.right: readReceiptSwitch.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)
                Text {
                  textFormat: Text.PlainText
                  text: root.service && root.service.sendReadReceipts
                    ? "Read receipts enabled" : "Private reading enabled"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.weight: Font.DemiBold
                }
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.Wrap
                  text: root.service && root.service.sendReadReceipts
                    ? "Opening a conversation may tell the other side it was read."
                    : "Read any locally synced message without telling the other side. Local badges still clear."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              ToggleSwitch {
                id: readReceiptSwitch
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                checked: root.service ? root.service.sendReadReceipts : false
                busy: root.service ? root.service.settingsWriting : false
                foreground: root.foreground
                accent: root.accent
                onToggled: if (root.service)
                  root.service.setPreference("send_read_receipts", !checked)
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(62)
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, root.accent)
              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.right: unreadSwitch.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: "Unread count in the bar"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  textFormat: Text.PlainText
                  text: "A local badge only—no desktop message popups"
                  color: root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              ToggleSwitch {
                id: unreadSwitch
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                checked: root.service ? root.service.showUnreadCount : true
                busy: root.service ? root.service.settingsWriting : false
                foreground: root.foreground
                accent: root.accent
                onToggled: if (root.service)
                  root.service.setPreference("show_unread_count", !checked)
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(62)
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, root.accent)
              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.right: onlineSwitch.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: "Background sync"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.offlineForSelectedAccount
                    ? "Paused; your local archive remains readable"
                    : "Keep the encrypted local mirror warm"
                  color: root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              ToggleSwitch {
                id: onlineSwitch
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                checked: root.demoMode || (root.selectedStatusReady
                  && !root.offlineForSelectedAccount)
                enabled: root.demoMode || root.selectedStatusReady
                busy: root.service ? root.service.controlWriting : false
                foreground: root.foreground
                accent: root.accent
                onToggled: if (!root.demoMode && root.service)
                  root.service.setOnline(!checked)
              }
            }

            Rectangle {
              width: parent.width
              height: dropdownSizeColumn.implicitHeight + Style.space(22)
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, root.accent)
              Column {
                id: dropdownSizeColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Style.space(11)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)
                Text {
                  textFormat: Text.PlainText
                  text: "Recent chats in the bar dropdown"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Row {
                  width: parent.width
                  spacing: Style.space(7)
                  Repeater {
                    model: [5, 7, 9]
                    delegate: Rectangle {
                      required property int modelData
                      width: (dropdownSizeColumn.width - Style.space(14)) / 3
                      height: Style.space(32)
                      radius: Style.cornerRadius
                      color: root.service && root.service.dropdownRows === modelData
                        ? Style.selectedFillFor(root.foreground, root.accent)
                        : Style.normalFillFor(root.foreground, root.accent)
                      border.width: 1
                      border.color: root.service && root.service.dropdownRows === modelData
                        ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: String(modelData)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.weight: Font.DemiBold
                      }
                      TapHandler {
                        enabled: root.service && !root.service.settingsWriting
                        onTapped: root.service.setPreference("dropdown_rows", modelData)
                      }
                    }
                  }
                }
              }
            }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                text: "OmaWhatsApp stores these choices in a mode-0600 local preferences file. Private reading is the default and a read receipt is never sent unless you opt in or explicitly choose “Mark read · send receipt”."
                color: root.dimmer
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      // ------------------------------------------------------- chat sidebar

      Rectangle {
        id: sidebar
        anchors.top: appHeader.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        visible: root.narrow ? !root.narrowConversation : width > 0
        width: root.narrow ? parent.width : (root.sidebarCollapsed ? 0
          : Math.min(Style.space(340), Math.max(Style.space(250), window.width * 0.30)))
        opacity: root.narrow || !root.sidebarCollapsed ? 1 : 0
        clip: true
        color: Style.normalFillFor(root.foreground, root.accent)

        Behavior on width {
          NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on opacity { NumberAnimation { duration: 110 } }

        Rectangle {
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          width: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
        }

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(10)

          Item {
            width: parent.width
            height: Style.space(30)
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Chats"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: String(root.sourceChats.length)
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          TextField {
            id: chatSearchField
            width: parent.width
            placeholderText: "Search chats"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            onActiveFocusChanged: if (activeFocus) keyboardNavigation.enterChatSearch()
            onTextChanged: root.chatCursorIndex = 0
            background: Rectangle {
              radius: Style.cornerRadius
              color: chatSearchField.activeFocus || chatSearchField.hovered
                ? Style.hoverFillFor(root.foreground, root.accent)
                : Style.normalFillFor(root.foreground, root.accent)
              border.width: 1
              border.color: chatSearchField.activeFocus
                ? Style.hoverBorderFor(root.foreground, root.accent)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            }
          }

          AccountSwitcher {
            id: appAccountSwitcher
            width: parent.width
            accounts: root.accountEntries
            selectedScope: root.accountScope
            foreground: root.foreground
            background: root.background
            accent: root.accent
            muted: root.dim
            urgent: root.urgent
            fontFamily: root.fontFamily
            linkBusy: !!root.service && root.service.accountOperations.linkBusy
            avatarBusy: !!root.service && root.service.accountOperations.avatarBusy
            statusMessage: root.service
              ? root.service.accountOperations.statusMessage : ""
            allowAccountLink: !root.demoMode && !!root.service
            allowAvatarRefresh: !root.demoMode && !!root.service
            onScopeSelected: function(scope) {
              root.accountScope = scope
              root.chatCursorIndex = 0
            }
            onLinkRequested: function(name) {
              if (root.service) root.service.accountOperations.linkAccount(name)
            }
            onAvatarRefreshRequested: {
              if (root.service) root.service.accountOperations.refreshAvatars()
            }
          }

          AccountReadiness {
            id: appAccountReadiness
            width: parent.width
            accounts: root.demoMode || !root.service ? [] : root.service.accounts
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
          }

          ListView {
            id: chatList
            width: parent.width
            height: sidebar.height - Style.space(116)
              - appAccountSwitcher.height
              - (appAccountReadiness.hasUnavailableAccounts
                ? appAccountReadiness.height + Style.space(10) : 0)
            clip: true
            spacing: Style.space(3)
            model: root.visibleChats
            currentIndex: root.chatCursorIndex
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: chatRow
              required property var modelData
              required property int index
              width: chatList.width
              height: Style.space(66)
              radius: Style.cornerRadius
              readonly property bool selected: String(modelData.account || "") === root.selectedAccount
                && (root.demoMode
                  ? String(modelData.jid) === root.demoSelectedJid
                  : !!root.service && String(modelData.jid) === root.service.selectedChatJid)
              readonly property bool keyboardSelected: root.keyboardContext === "chats"
                && index === root.chatCursorIndex
              color: keyboardSelected || selected
                ? Style.selectedFillFor(root.foreground, root.accent)
                : (chatMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
              border.width: keyboardSelected ? 1 : 0
              border.color: root.accent

              ChatAvatar {
                id: chatAvatar
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(38)
                height: width
                chat: modelData
                selected: chatRow.selected
                foreground: root.foreground
                background: root.background
                accent: root.accent
                fontFamily: root.fontFamily
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: Style.space(9)
                anchors.verticalCenter: parent.verticalCenter
                visible: index < 9 && Number(modelData.unread || 0) === 0
                  && (chatRow.selected || chatMouse.containsMouse)
                text: "Ctrl+" + String(index + 1)
                color: root.dimmer
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Column {
                anchors.left: chatAvatar.right
                anchors.leftMargin: Style.space(9)
                anchors.right: unreadBadge.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: String(modelData.name || "WhatsApp chat")
                  color: root.foreground
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: AccountModel.previewPrefix(modelData, root.multiAccount)
                    + (modelData.last_from_me ? "You · " : "")
                    + String(modelData.preview || "No local messages yet")
                  color: root.dim
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Rectangle {
                id: unreadBadge
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                visible: Number(modelData.unread || 0) > 0
                width: Math.max(Style.space(20), unreadText.implicitWidth + Style.space(8))
                height: Style.space(20)
                radius: height / 2
                color: Number(modelData.notification_unread || 0) > 0
                  ? root.accent : "transparent"
                border.width: Number(modelData.notification_unread || 0) > 0 ? 0 : 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
                Text {
                  textFormat: Text.PlainText
                  id: unreadText
                  anchors.centerIn: parent
                  text: Number(modelData.unread || 0) > 99 ? "99+" : String(modelData.unread || 0)
                  color: Number(modelData.notification_unread || 0) > 0
                    ? root.background : root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: chatMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  root.chatCursorIndex = index
                  root.selectChat(modelData)
                }
              }
            }
          }
        }
      }

      // ------------------------------------------------------ conversation

      Item {
        id: conversation
        visible: !root.narrow || root.narrowConversation
        anchors.top: appHeader.bottom
        anchors.bottom: parent.bottom
        anchors.left: root.narrow ? parent.left : sidebar.right
        anchors.right: parent.right

        Item {
          id: conversationHeader
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(54)

          Row {
            id: conversationTitleRow
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: headerActions.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Rectangle {
              visible: root.narrow
              width: visible ? Style.space(30) : 0
              height: Style.space(30)
              radius: Style.cornerRadius
              color: backHover.hovered
                ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "←"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: backHover }
              TapHandler {
                onTapped: {
                  root.narrowConversation = false
                  root.narrowSearchOpen = false
                }
              }
            }

            Rectangle {
              visible: !root.narrow
              width: visible ? Style.space(30) : 0
              height: Style.space(30)
              radius: Style.cornerRadius
              color: sidebarToggleHover.hovered
                ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.sidebarCollapsed ? "󰤻" : "󰤸"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
              HoverHandler { id: sidebarToggleHover }
              TapHandler { onTapped: root.toggleSidebar() }
              ToolTip.visible: sidebarToggleHover.hovered
              ToolTip.text: (root.sidebarCollapsed ? "Show" : "Hide") + " chats · Ctrl+B"
            }

            Rectangle {
              width: Style.space(34)
              height: width
              radius: width / 2
              color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰠮"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, conversationTitleRow.width
                - Style.space(84))
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.displayGroupName
                color: root.foreground
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                textFormat: Text.PlainText
                text: root.displayKind === "group" ? "group" : "direct message"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Repeater {
              model: root.compact ? [] : ["all", "media", "links"]
              delegate: Rectangle {
                required property string modelData
                width: Style.space(46)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.contentFilter === modelData
                  ? Style.selectedFillFor(root.foreground, root.accent) : "transparent"
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: modelData
                  color: root.contentFilter === modelData ? root.foreground : root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.contentFilter = modelData }
              }
            }

            TextField {
              id: messageSearchField
              visible: !root.narrow || root.narrowSearchOpen
              width: root.narrow ? Style.space(190)
                : (root.compact ? Style.space(120) : Style.space(180))
              height: Style.space(32)
              placeholderText: "Search messages"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              onActiveFocusChanged: if (activeFocus) keyboardNavigation.enterMessageSearch()
              onTextChanged: searchDebounce.restart()
              background: Rectangle {
                radius: Style.cornerRadius
                color: Style.normalFillFor(root.foreground, root.accent)
                border.width: messageSearchField.activeFocus ? 1 : 0
                border.color: root.accent
              }
            }

            Rectangle {
              visible: root.narrow && !root.narrowSearchOpen
              width: visible ? Style.space(32) : 0
              height: Style.space(32)
              radius: Style.cornerRadius
              color: narrowSearchHover.hovered
                ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰍉"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
              HoverHandler { id: narrowSearchHover }
              TapHandler {
                onTapped: {
                  root.narrowSearchOpen = true
                  Qt.callLater(function() { messageSearchField.forceActiveFocus() })
                }
              }
            }

            Rectangle {
              width: Style.space(32)
              height: width
              radius: Style.cornerRadius
              color: chatMenuHover.hovered
                ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰇙"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
              HoverHandler { id: chatMenuHover }
              TapHandler { onTapped: chatMenu.open() }

              Popup {
                id: chatMenu
                x: parent.width - width
                y: parent.height + Style.space(4)
                width: Style.space(230)
                height: chatMenuColumn.implicitHeight + Style.space(10)
                padding: Style.space(5)
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                background: Rectangle {
                  radius: Style.cornerRadius
                  color: root.background
                  border.width: 1
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                }
                contentItem: Column {
                  id: chatMenuColumn
                  spacing: Style.space(2)
                  Repeater {
                    model: [
                      { label: root.selectedChat && root.selectedChat.pinned ? "Unpin chat" : "Pin chat", action: root.selectedChat && root.selectedChat.pinned ? "unpin" : "pin" },
                      { label: root.selectedChat && root.selectedChat.muted ? "Unmute notifications" : "Mute notifications", action: root.selectedChat && root.selectedChat.muted ? "unmute" : "mute" },
                      { label: root.selectedChat && root.selectedChat.archived ? "Unarchive chat" : "Archive chat", action: root.selectedChat && root.selectedChat.archived ? "unarchive" : "archive" },
                      { label: root.selectedChat && Number(root.selectedChat.unread || 0) > 0
                          ? "Mark read · send receipt" : "Mark as unread",
                        action: root.selectedChat && Number(root.selectedChat.unread || 0) > 0
                          ? "read" : "unread" }
                    ]
                    delegate: Rectangle {
                      required property var modelData
                      width: parent.width
                      height: Style.space(34)
                      radius: Style.cornerRadius
                      color: chatActionHover.hovered
                        ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
                      Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      HoverHandler { id: chatActionHover }
                      TapHandler {
                        onTapped: {
                          chatMenu.close()
                          if (!root.demoMode && root.service)
                            root.service.chatAction(
                              root.currentChatRef(), modelData.action, "app")
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.visibleMessages.length === 0 && !(root.service && root.service.loadingMessages)
          anchors.centerIn: messageList
          text: root.displayGroupName === "" ? "Choose a chat" : "No local messages in this chat"
          color: root.dimmer
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        ListView {
          id: messageList
          anchors.top: conversationHeader.bottom
          anchors.bottom: composerBar.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(14)
          clip: true
          spacing: Style.space(8)
          model: root.visibleMessages
          currentIndex: root.cursorIndex
          verticalLayoutDirection: ListView.BottomToTop
          boundsBehavior: Flickable.StopAtBounds

          delegate: Item {
            id: messageRow
            required property var modelData
            required property int index
            width: messageList.width
            height: renderedMessage.height

            MessageBubble {
              id: renderedMessage
              width: parent.width
              message: modelData
              foreground: root.foreground
              background: root.background
              accent: root.accent
              dim: root.dim
              dimmer: root.dimmer
              fontFamily: root.fontFamily
              groupChat: root.displayKind === "group"
              selected: index === root.cursorIndex
              narrow: root.narrow
              surfaceActive: root.timelineMediaActive
              activePlaybackId: root.activeTimelinePlaybackId
              busyMedia: root.writeForCurrentChat
                && root.service.mediaDownloadId === String(modelData.id)
              onSelectedRequested: {
                root.cursorIndex = index
                if (root.service) root.service.selectItem(modelData.id)
                root.focusMessages()
              }
              onOpenMediaRequested: function(path) { root.openMedia(path) }
              onPlaybackRequested: function(messageId) {
                root.requestTimelinePlayback(messageId)
              }
              onDownloadMediaRequested: if (root.service)
                root.service.downloadMedia(root.currentChatRef(), modelData, "app")
              onReplyRequested: root.startReply(modelData)
              onReactionRequested: function(emoji) {
                if (!root.demoMode && root.service)
                  root.service.reactTo(root.currentChatRef(), modelData, emoji, "app")
              }
              onEditRequested: root.startEdit(modelData)
              onDeleteRequested: function(forMe) { root.requestDelete(modelData, forMe) }
              onForwardRequested: root.startForward(modelData)
              onCopyRequested: function(text) { root.copyText(text) }
              onOptionRequested: function(optionIndex) {
                if (!root.demoMode && root.service)
                  root.service.selectOption(
                    root.currentChatRef(), modelData, optionIndex, "app")
              }
            }
          }
        }

        Rectangle {
          id: mentionCompletion
          z: 80
          visible: root.mentionCompletionVisible
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: composerBar.top
          anchors.bottomMargin: Style.space(8)
          width: Math.min(parent.width - Style.space(32), Style.space(520))
          height: Math.min(5, root.mentionCandidates.length) * Style.space(46)
            + Style.space(34)
          radius: Style.cornerRadius
          color: root.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
          clip: true

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.top: parent.top
            anchors.topMargin: Style.space(8)
            text: root.service && root.service.loadingMembers
              ? "LOADING MEMBERS…" : "MENTION"
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          ListView {
            id: mentionList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Style.space(34)
            anchors.bottom: parent.bottom
            clip: true
            model: root.mentionCandidates
            currentIndex: root.mentionSelection
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              required property var modelData
              required property int index
              width: mentionList.width
              height: Style.space(46)
              color: index === root.mentionSelection || mentionHover.hovered
                ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                height: width
                radius: width / 2
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: String(modelData.name || "?").slice(0, 1).toUpperCase()
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(50)
                anchors.right: roleLabel.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: String(modelData.name || "WhatsApp member")
                  color: root.foreground
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: String(modelData.phone || "") !== ""
                  text: String(modelData.phone || "")
                  color: root.dimmer
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                textFormat: Text.PlainText
                id: roleLabel
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                visible: String(modelData.role || "") === "admin"
                  || String(modelData.role || "") === "superadmin"
                text: "ADMIN"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              HoverHandler { id: mentionHover }
              TapHandler { onTapped: root.chooseMention(index) }
            }
          }
        }

        Rectangle {
          id: composerBar
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          property real replyContextHeight: root.replyTarget || root.editTarget ? Style.space(48) : 0
          property real attachmentContextHeight: root.pendingAttachments.length > 0 ? Style.space(68) : 0
          property real contextHeight: replyContextHeight + attachmentContextHeight
          height: Style.space(78) + contextHeight
          color: Style.normalFillFor(root.foreground, root.accent)

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          }

          Rectangle {
            visible: composerBar.replyContextHeight > 0
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: composerBar.replyContextHeight
            color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.48)

            Rectangle {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.top: parent.top
              anchors.topMargin: Style.space(7)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(7)
              width: Style.space(3)
              radius: width / 2
              color: root.accent
            }

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(25)
              anchors.right: cancelContext.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                text: root.editTarget ? "Editing message"
                  : "Replying to " + String(root.replyTarget ? root.replyTarget.sender : "")
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: String(root.editTarget ? root.editTarget.text
                  : (root.replyTarget ? root.replyTarget.text || "[media]" : ""))
                color: root.dim
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              id: cancelContext
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(28)
              height: width
              radius: width / 2
              color: cancelContextHover.hovered
                ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "×"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: cancelContextHover }
              TapHandler { onTapped: root.cancelComposerContext() }
            }
          }

          Rectangle {
            visible: composerBar.attachmentContextHeight > 0
            anchors.top: parent.top
            anchors.topMargin: composerBar.replyContextHeight
            anchors.left: parent.left
            anchors.right: parent.right
            height: composerBar.attachmentContextHeight
            color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.48)

            ListView {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.right: clearAttachments.left
              anchors.rightMargin: Style.space(8)
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.topMargin: Style.space(6)
              anchors.bottomMargin: Style.space(6)
              orientation: ListView.Horizontal
              spacing: Style.space(6)
              clip: true
              model: root.pendingAttachments
              delegate: Rectangle {
                required property string modelData
                required property int index
                width: Math.min(Style.space(178), Math.max(Style.space(116), attachmentLabel.implicitWidth + Style.space(58)))
                height: Style.space(56)
                radius: Style.cornerRadius
                color: Style.normalFillFor(root.foreground, root.accent)
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(5)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(42)
                  height: width
                  radius: Style.cornerRadius
                  color: root.background
                  clip: true
                  Image {
                    visible: root.attachmentIsImage(modelData)
                    anchors.fill: parent
                    anchors.margins: Style.space(2)
                    source: visible ? modelData : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                  }
                  Text {
                    textFormat: Text.PlainText
                    visible: !root.attachmentIsImage(modelData)
                    anchors.centerIn: parent
                    text: "󰈔"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  id: attachmentLabel
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(53)
                  anchors.right: removeAttachment.visible ? removeAttachment.left : parent.right
                  anchors.rightMargin: Style.space(5)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.attachmentName(modelData)
                  color: root.foreground
                  elide: Text.ElideMiddle
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  id: removeAttachment
                  visible: !root.sendingAttachments
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(4)
                  width: Style.space(20)
                  height: width
                  radius: width / 2
                  color: root.background
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "×"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  TapHandler { onTapped: root.removeAttachment(index) }
                }
              }
            }

            Rectangle {
              id: clearAttachments
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              width: root.sendingAttachments ? Style.space(112) : Style.space(30)
              height: width
              radius: width / 2
              color: clearAttachmentsHover.hovered
                ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.sendingAttachments
                  ? "Sending " + String(root.pendingAttachments.length) + "…" : "󰆴"
                color: root.sendingAttachments ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              HoverHandler { id: clearAttachmentsHover }
              TapHandler {
                enabled: !root.sendingAttachments
                onTapped: {
                  if (!root.demoMode && root.service)
                    root.service.discardStages(root.pendingAttachments)
                  root.pendingAttachments = []
                  root.pendingStickerPath = ""
                  root.attachmentError = ""
                }
              }
            }
          }

          Rectangle {
            id: pasteButton
            visible: !root.voiceForCurrentChat
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: composerBar.contextHeight / 2
            width: Style.space(34)
            height: width
            radius: Style.cornerRadius
            color: pasteMouse.containsMouse
              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "󰐕"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }
            MouseArea {
              id: pasteMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: attachmentTray.opened ? attachmentTray.close() : attachmentTray.open()
            }

            Popup {
              id: attachmentTray
              x: 0
              y: -height - Style.space(8)
              width: Style.space(214)
              height: attachmentTrayColumn.implicitHeight + Style.space(10)
              padding: Style.space(5)
              closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
              background: Rectangle {
                radius: Style.cornerRadius
                color: root.background
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
              }
              contentItem: Column {
                id: attachmentTrayColumn
                spacing: Style.space(2)
                Repeater {
                  model: [
                    { icon: "󰈔", label: "Document", action: "document" },
                    { icon: "󰉏", label: "Photos & videos", action: "media" },
                    { icon: "󰄀", label: "Camera", action: "camera" },
                    { icon: "󰎆", label: "Audio", action: "audio" },
                    { icon: "󰛋", label: "Contact", action: "contact" },
                    { icon: "󰐕", label: "Poll", action: "poll" },
                    { icon: "󰃭", label: "Event", action: "event" },
                    { icon: "󰏘", label: "New sticker", action: "sticker" },
                    { icon: "󰅌", label: "Paste clipboard", action: "paste" }
                  ]
                  delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: Style.space(38)
                    radius: Style.cornerRadius
                    color: trayItemHover.hovered
                      ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
                    Text {
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(9)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.icon
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                    }
                    Text {
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(42)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    HoverHandler { id: trayItemHover }
                    TapHandler {
                      onTapped: {
                        attachmentTray.close()
                        if (modelData.action === "media") root.openFilePicker("media")
                        else if (modelData.action === "document") root.openFilePicker("document")
                        else if (modelData.action === "audio") root.openFilePicker("audio")
                        else if (modelData.action === "sticker") root.openFilePicker("sticker")
                        else if (modelData.action === "poll") root.startPoll()
                        else if (modelData.action === "camera")
                          root.attachmentError = "Camera capture needs a desktop camera portal; choose Photos & videos for now."
                        else if (modelData.action === "contact")
                          root.attachmentError = "wacli does not expose contact-card sending yet."
                        else if (modelData.action === "event")
                          root.attachmentError = "wacli does not expose WhatsApp event sending yet."
                        else root.pasteDraft()
                      }
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            id: composerSurface
            visible: !root.voiceForCurrentChat
            anchors.left: pasteButton.right
            anchors.leftMargin: Style.space(8)
            anchors.right: sendButton.left
            anchors.rightMargin: Style.space(8)
            anchors.top: parent.top
            anchors.topMargin: composerBar.contextHeight + Style.space(10)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(10)
            radius: Style.cornerRadius
            color: root.background
            border.width: composer.activeFocus ? 1 : 0
            border.color: root.accent

            TextEdit {
              id: composer
              anchors.fill: parent
              anchors.margins: Style.space(10)
              color: root.foreground
              selectionColor: root.accent
              selectedTextColor: root.background
              wrapMode: TextEdit.Wrap
              textFormat: TextEdit.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              onActiveFocusChanged: if (activeFocus) keyboardNavigation.enterComposer()
              onTextChanged: root.updateMentionCompletion()
              onCursorPositionChanged: root.updateMentionCompletion()
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (root.mentionCompletionVisible
                    && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
                  var delta = event.key === Qt.Key_Down ? 1 : -1
                  root.mentionSelection = (root.mentionSelection + delta
                    + root.mentionCandidates.length) % root.mentionCandidates.length
                  mentionList.positionViewAtIndex(root.mentionSelection, ListView.Contain)
                  event.accepted = true
                } else if (root.mentionCompletionVisible
                           && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                               || event.key === Qt.Key_Tab)) {
                  root.chooseMention(root.mentionSelection)
                  event.accepted = true
                } else if (root.mentionStart >= 0 && event.key === Qt.Key_Escape) {
                  root.closeMentionCompletion()
                  event.accepted = true
                } else if ((event.modifiers & Qt.ControlModifier)
                           && (event.modifiers & Qt.ShiftModifier)
                           && event.key === Qt.Key_V) {
                  root.toggleVoiceRecording()
                  event.accepted = true
                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                  root.pasteDraft()
                  event.accepted = true
                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                           && !(event.modifiers & Qt.ShiftModifier)) {
                  root.sendDraft()
                  event.accepted = true
                } else if (event.key === Qt.Key_Up && composer.text === "") {
                  root.focusMessages()
                  event.accepted = true
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: composer.text === ""
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.pendingStickerPath !== "" ? "Sticker ready — no caption"
                : root.pendingAttachments.length > 0 ? "Add a caption"
                : (root.displayGroupName === "" ? "Choose a chat" : "Message " + root.displayGroupName)
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Rectangle {
            id: sendButton
            visible: !root.voiceForCurrentChat
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: composerBar.contextHeight / 2
            width: Style.space(38)
            height: width
            radius: width / 2
            color: composer.text.trim() !== "" || root.pendingAttachments.length > 0
              || root.currentChatKey() !== "" ? root.accent : "transparent"
            opacity: root.service && root.service.writing ? 0.45 : 1
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: composer.text.trim() !== "" || root.pendingAttachments.length > 0
                ? "➤" : "󰍬"
              color: root.currentChatKey() !== "" ? root.background : root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            MouseArea {
              anchors.fill: parent
              onClicked: {
                if (composer.text.trim() !== "" || root.pendingAttachments.length > 0)
                  root.sendDraft()
                else root.toggleVoiceRecording()
              }
            }
          }

          VoiceComposer {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: composerBar.contextHeight / 2
            service: root.demoMode ? null : root.service
            owner: "app"
            account: root.selectedAccount
            jid: root.currentJid()
            offline: root.offlineForSelectedAccount
            foreground: root.foreground
            background: root.background
            accent: root.accent
            urgent: root.urgent
            muted: root.dim
            fontFamily: root.fontFamily
            demoState: root.demoVoiceState
            demoAccount: root.selectedAccount
            demoJid: root.currentJid()
            demoDurationMs: 42000
            demoPositionMs: 13000
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.attachmentError !== ""
            || (!root.demoMode && root.service && root.service.errorText !== "")
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.bottom: composerBar.top
          anchors.bottomMargin: Style.space(4)
          width: parent.width - Style.space(32)
          text: root.attachmentError !== "" ? root.attachmentError
            : (root.service ? root.service.errorText : "")
          color: root.urgent
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Popup {
        id: deleteConfirm
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(Style.space(360), window.width - Style.space(28))
        height: deleteColumn.implicitHeight + Style.space(28)
        padding: Style.space(14)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: {
          root.deleteTarget = null
          root.deleteOriginRef = AccountModel.chatRef("", "")
        }
        background: Rectangle {
          radius: Style.cornerRadius
          color: root.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
        }
        contentItem: Column {
          id: deleteColumn
          spacing: Style.space(12)
          Text {
            textFormat: Text.PlainText
            text: root.deleteForMe ? "Delete this message for you?"
              : "Delete this message for everyone?"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.deleteForMe
              ? "It will disappear from this device's WhatsApp history."
              : "WhatsApp may refuse older messages; if accepted, everyone loses the message."
            color: root.dim
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Repeater {
              model: [
                { label: "Cancel", confirm: false },
                { label: "Delete", confirm: true }
              ]
              delegate: Rectangle {
                required property var modelData
                width: Style.space(78)
                height: Style.space(34)
                radius: Style.cornerRadius
                color: modelData.confirm ? root.urgent
                  : Style.normalFillFor(root.foreground, root.accent)
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: modelData.label
                  color: modelData.confirm ? root.background : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                TapHandler {
                  onTapped: {
                    if (modelData.confirm) root.confirmDelete()
                    else root.dismissDelete()
                  }
                }
              }
            }
          }
        }
      }

      Popup {
        id: pollComposer
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(Style.space(430), window.width - Style.space(28))
        height: Math.min(Style.space(470), window.height - Style.space(36))
        padding: Style.space(14)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: root.pollOriginRef = AccountModel.chatRef("", "")
        background: Rectangle {
          radius: Style.cornerRadius
          color: root.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
        }
        contentItem: Column {
          spacing: Style.space(10)
          Text {
            textFormat: Text.PlainText
            text: "Create poll"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }
          Text {
            textFormat: Text.PlainText
            text: "Question"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: pollQuestion
            width: parent.width
            placeholderText: "Ask something"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            background: Rectangle {
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, root.accent)
              border.width: pollQuestion.activeFocus ? 1 : 0
              border.color: root.accent
            }
          }
          Text {
            textFormat: Text.PlainText
            text: "Options · one per line (2–12)"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextArea {
            id: pollOptions
            width: parent.width
            height: Math.max(Style.space(130), pollComposer.height - Style.space(250))
            placeholderText: "First option\nSecond option"
            color: root.foreground
            selectionColor: root.accent
            selectedTextColor: root.background
            wrapMode: TextEdit.Wrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            background: Rectangle {
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, root.accent)
              border.width: pollOptions.activeFocus ? 1 : 0
              border.color: root.accent
            }
          }
          Rectangle {
            width: parent.width
            height: Style.space(34)
            radius: Style.cornerRadius
            color: pollMultiHover.hovered
              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(20)
              height: width
              radius: Style.cornerRadius
              color: root.pollMultiple ? root.accent : "transparent"
              border.width: 1
              border.color: root.pollMultiple ? root.accent : root.dim
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: root.pollMultiple
                text: "✓"
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(30)
              anchors.verticalCenter: parent.verticalCenter
              text: "Allow multiple answers"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            HoverHandler { id: pollMultiHover }
            TapHandler { onTapped: root.pollMultiple = !root.pollMultiple }
          }
          Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Repeater {
              model: [
                { label: "Cancel", send: false },
                { label: "Send poll", send: true }
              ]
              delegate: Rectangle {
                required property var modelData
                width: modelData.send ? Style.space(94) : Style.space(76)
                height: Style.space(34)
                radius: Style.cornerRadius
                color: modelData.send ? root.accent
                  : Style.normalFillFor(root.foreground, root.accent)
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: modelData.label
                  color: modelData.send ? root.background : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                TapHandler {
                  onTapped: {
                    if (!modelData.send) {
                      pollComposer.close()
                      return
                    }
                    var question = String(pollQuestion.text || "").trim()
                    var values = String(pollOptions.text || "").split(/\r?\n/)
                      .map(function(value) { return value.trim() })
                      .filter(function(value) { return value !== "" })
                    if (question === "") root.attachmentError = "Give the poll a question."
                    else if (values.length < 2 || values.length > 12)
                      root.attachmentError = "Add between 2 and 12 poll options."
                    else if (!root.demoMode && root.service && !root.service.writing) {
                      if (root.submitPoll(question, values, root.pollMultiple)) {
                        root.attachmentError = ""
                        pollComposer.close()
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      Popup {
        id: forwardPicker
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(Style.space(430), window.width - Style.space(28))
        height: Math.min(Style.space(520), window.height - Style.space(36))
        padding: Style.space(14)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: {
          root.forwardTarget = null
          root.forwardOriginRef = AccountModel.chatRef("", "")
        }
        background: Rectangle {
          radius: Style.cornerRadius
          color: root.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
        }
        contentItem: Column {
          spacing: Style.space(10)
          Item {
            width: parent.width
            height: Style.space(30)
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Forward message"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "×"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              TapHandler { onTapped: root.dismissForward() }
            }
          }
          TextField {
            id: forwardSearch
            width: parent.width
            placeholderText: "Search chats"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            background: Rectangle {
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, root.accent)
              border.width: forwardSearch.activeFocus ? 1 : 0
              border.color: root.accent
            }
          }
          ListView {
            width: parent.width
            height: forwardPicker.height - Style.space(116)
            clip: true
            spacing: Style.space(3)
            model: root.forwardCandidates
              .filter(function(chat) {
                var needle = String(forwardSearch.text || "").trim().toLowerCase()
                return needle === ""
                  || String(chat.name || "").toLowerCase().indexOf(needle) >= 0
              })
            delegate: Rectangle {
              required property var modelData
              width: parent.width
              height: Style.space(48)
              radius: Style.cornerRadius
              color: forwardHover.hovered
                ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: String(modelData.name || "WhatsApp chat")
                color: root.foreground
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: forwardHover }
              TapHandler {
                onTapped: {
                  root.forwardTo(modelData)
                }
              }
            }
          }
        }
      }

      MediaViewer {
        id: mediaViewer
        anchors.fill: parent
        items: root.mediaGallery
        surfaceActive: root.opened
        playback: root.playbackCoordinator
        chatRef: root.currentChatRef()
        foreground: root.foreground
        background: root.background
        accent: root.accent
        dim: root.dim
        fontFamily: root.fontFamily
        onOpenExternalRequested: function(path) { root.openMediaExternal(path) }
      }
    }
  }
}
