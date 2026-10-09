import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SettingsPolicy.js" as SettingsPolicy
import "AccountModel.js" as AccountModel
import "ComposerModel.js" as ComposerModel
import "TimeFormat.js" as TimeFormat
import "FormatModel.js" as FormatModel
import "PresenceModel.js" as PresenceModel
import "Tint.js" as Tint

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
  // Tell the service when the selected conversation is really on screen.
  Binding {
    target: root.service
    property: "appConversationVisible"
    when: !!root.service && !root.demoMode
    value: root.opened && !root.settingsOpen && root.currentChatKey() !== ""
      && (!root.narrow || root.narrowConversation)
      && !(root.chatDetailsOpen && !root.chatDetailsBeside)
      && !(root.mediaBrowserOpen && !root.mediaBrowserBeside)
  }

  UpdateController {
    id: appUpdates
    helper: root.helper
    active: root.opened && !root.demoMode
    online: !!root.service && root.service.statusReady && !root.service.offlineMode
    checkOnLaunch: !!root.service && root.service.checkUpdatesOnLaunch === true
    onUpdateAvailable: function(version) {
      root.showToast("A new version of OmaWhatsApp is available · open settings to update")
    }
  }
  property alias cursorIndex: keyboardNavigation.messageIndex
  property alias chatCursorIndex: keyboardNavigation.chatIndex
  readonly property alias keyboardContext: keyboardNavigation.context
  property var pendingComposerSnapshot: null
  property string pendingWriteKind: ""
  property bool narrowConversation: false
  property bool narrowSearchOpen: false
  property bool sidebarCollapsed: false
  // The chat list's width: automatic until its edge is dragged; the chosen
  // width is saved, and a double click on the edge goes back to automatic.
  property real railDragWidth: -1
  property int railWidthChoice: root.service && !root.demoMode ? Number(root.service.railWidth || 0) : 0
  readonly property real railMinWidth: Style.space(240)
  readonly property real railMaxWidth: Math.max(railMinWidth,
    Math.min(Style.space(560), window.width - Style.space(360)))
  readonly property real railAutoWidth: Math.min(Style.space(340),
    Math.max(Style.space(250), window.width * 0.30))
  readonly property real railWidth: railDragWidth >= 0 ? railDragWidth
    : (railWidthChoice > 0 ? Math.max(railMinWidth, Math.min(railMaxWidth, railWidthChoice))
      : railAutoWidth)
  function setRailWidth(value) {
    var width = Math.round(Math.max(railMinWidth, Math.min(railMaxWidth, Number(value || 0))))
    railWidthChoice = width
    if (root.service && !root.demoMode) root.service.setPreference("rail_width", width)
    return width
  }
  function resetRailWidth() {
    railWidthChoice = 0
    if (root.service && !root.demoMode) root.service.setPreference("rail_width", 0)
  }
  property bool settingsOpen: false
  property int composerMaxLines: service ? service.composerMaxLines : 6
  property string demoTimeFormat: "auto"
  readonly property string timeFormat: demoMode ? demoTimeFormat
    : (service ? service.timeFormat : "auto")
  property var replyTarget: null
  property var editTarget: null
  property var deleteTarget: null
  property var deleteOriginRef: AccountModel.chatRef("", "")
  property bool deleteForMe: true
  property var removeLocalTargetRef: AccountModel.chatRef("", "")
  // Forwarding: messages picked in the conversation (selection mode), then
  // the chats and an optional note in the dialog.
  property bool selectingMessages: false
  property var selectedMessageIds: []
  property var forwardItems: []
  property var forwardChosen: []
  property var forwardOriginRef: AccountModel.chatRef("", "")
  // Someone shared a contact with no chat yet: a draft chat for that person,
  // over the conversation it came from, until the first message is sent.
  property var contactDraft: null
  property bool contactDraftSending: false
  property string contactDraftError: ""
  readonly property var contactDraftCheck: !contactDraft || demoMode || !service
    || typeof service.numberCheckFor !== "function" ? null : service.numberCheckFor(contactDraft.digits)
  // known: this account knows the person; else what WhatsApp answered.
  readonly property string contactDraftState: !contactDraft ? ""
    : contactDraft.jid !== "" ? "known"
    : demoMode ? "registered"
    : contactDraftCheck === null ? "idle"
    : contactDraftCheck.loading ? "checking"
    : contactDraftCheck.error ? "error"
    : contactDraftCheck.registered ? "registered" : "absent"
  readonly property string contactDraftJid: !contactDraft ? ""
    : contactDraft.jid !== "" ? contactDraft.jid
    : demoMode ? contactDraft.digits + "@s.whatsapp.net"
    : contactDraftCheck && contactDraftCheck.registered ? String(contactDraftCheck.jid || "") : ""
  // The account's signature on outgoing texts and captions, and a one-message
  // opt-out from the composer.
  property var demoSignature: ({ enabled: false, name: "", position: "top" })
  property bool signatureSkipped: false
  readonly property var composerSignature: root.demoMode ? root.demoSignature
    : (root.service && typeof root.service.signatureFor === "function"
      ? root.service.signatureFor(root.selectedAccount) : ({ enabled: false, name: "", position: "top" }))
  readonly property bool signatureActive: root.composerSignature.enabled === true && !root.editTarget
    && root.pendingStickerPath === ""
  // A toast can offer one action, such as opening the chat a forward went to.
  property string toastActionLabel: ""
  property var toastActionChat: null
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
  // Rail view: all, unread, to reply, groups or archived (archived chats live apart).
  property string chatView: "all"
  readonly property var chatViews: {
    var scope = AccountModel.normalizeScope(root.accountScope, root.accountEntries)
    var views = [
      { id: "all", label: "All", count: 0 },
      { id: "unread", label: "Unread", count: AccountModel.viewCount(root.sourceChats, scope, "unread") },
      { id: "reply", label: "To reply", count: AccountModel.viewCount(root.sourceChats, scope, "reply") },
      { id: "groups", label: "Groups", count: 0 }
    ]
    var archived = AccountModel.viewCount(root.sourceChats, scope, "archived")
    if (archived > 0 || root.chatView === "archived")
      views.push({ id: "archived", label: "Archived", count: archived })
    return views
  }
  property var demoChats: [
    { jid: "demo-lab", name: "Omarchy Lab", kind: "group", account: "work", account_label: "work", avatar_path: "__demo_avatar__", preview: "Instant and native", timestamp: 1787539920, unread: 0, pinned: true },
    { jid: "demo-team", name: "Design team", kind: "group", account: "work", account_label: "work", avatar_path: "", preview: "The interaction pass is ready", timestamp: 1787539000, unread: 3, pinned: false },
    { jid: "demo-alex", name: "Alex", kind: "dm", account: "personal", account_label: "personal", avatar_path: "__demo_avatar__", preview: "Looks perfect — ship it", timestamp: 1787538200, unread: 1, pinned: false }
  ]
  property var demoItems: [
    { id: "demo-5", text: "Yep — shipped.", sender: "Sam Rivera", sender_jid: "sam@s.whatsapp.net", timestamp: 1787540100, from_me: false, done: false, media_type: "", mime_type: "", local_path: "", tags: [] },
    { id: "demo-1", text: "Instant, native, and private #design", sender: "You", sender_jid: "", timestamp: 1787539920, from_me: true, done: false, media_type: "", mime_type: "", local_path: "", tags: ["design"], reactions: [{ emoji: "🔥", from_me: false }, { emoji: "🔥", from_me: true }], starred: true, status: "read" },
    { id: "demo-2a", text: "Two photos, one smooth send #capture", sender: "You", sender_jid: "", timestamp: 1787539200, from_me: true, done: false, media_type: "album", mime_type: "image/svg+xml", local_path: "__demo__", album_id: "demo-album", album_count: 2, tags: ["capture"], album_items: [
      { id: "demo-2a", text: "Two photos, one smooth send #capture", sender: "You", sender_jid: "", timestamp: 1787539200, from_me: true, media_type: "image", mime_type: "image/svg+xml", local_path: "__demo__", album_id: "demo-album", album_index: 0, album_count: 2 },
      { id: "demo-2b", text: "", sender: "You", sender_jid: "", timestamp: 1787539199, from_me: true, media_type: "image", mime_type: "image/svg+xml", local_path: "__demo_photo__", album_id: "demo-album", album_index: 1, album_count: 2 }
    ] },
    { id: "demo-3", text: "Review the private repo README and release checklist #ship", sender: "You", sender_jid: "", timestamp: 1787538000, from_me: true, done: false, media_type: "", mime_type: "", local_path: "", tags: ["ship"], quoted_id: "demo-1", quoted_sender: "You", quoted_text: "Instant, native, and private #design", status: "delivered" },
    { id: "demo-4", text: "https://github.com/openclaw/wacli #reference", sender: "You", sender_jid: "", timestamp: 1787536800, from_me: true, done: true, media_type: "", mime_type: "", local_path: "", tags: ["reference"], status: "sent" }
  ]
  property var demoMembers: [
    { jid: "sam@s.whatsapp.net", name: "Sam Rivera", phone: "+1 555 123 4567", role: "admin" },
    { jid: "alex@s.whatsapp.net", name: "Alex Kim", phone: "+1 555 765 4321", role: "member" },
    { jid: "nora@s.whatsapp.net", name: "Nora Ali", phone: "+1 555 246 8101", role: "member" }
  ]

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.moizibnyousaf.omawhatsapp"
  // The helper ships in this checkout, at bin/ two levels above this file.
  readonly property string helper: decodeURIComponent(
    String(Qt.resolvedUrl("../../bin/omawhatsapp")).replace(/^file:\/\//, ""))
  readonly property bool showAvatars: root.demoMode || !root.service || root.service.showAvatars !== false
  readonly property string syncPauseReason: !root.demoMode && root.service
    && typeof root.service.syncPauseReason === "string" ? root.service.syncPauseReason : ""
  // Demo captures pick the density with {"demo":true,"density":"compact"}.
  property string demoRailDensity: ""
  // {"demo":true,"onboarding":true} shows the first-run welcome.
  property bool demoOnboarding: false
  readonly property bool onboarding: root.demoMode ? root.demoOnboarding
    : !!root.service && root.service.needsOnboarding === true
  readonly property bool compactRail: root.demoMode ? root.demoRailDensity === "compact"
    : !!root.service && root.service.railDensity === "compact"
  // The list's stamps change with the day, so "now" ticks while the app is open.
  property var clockNow: new Date()
  // Demo stamps are measured from a fixed moment so captures do not age.
  property var demoNow: new Date(1787540400 * 1000)
  readonly property string listClock: TimeFormat.clockPattern(root.timeFormat,
    Qt.locale().timeFormat(Locale.ShortFormat))
  readonly property bool enterSends: root.demoMode || !root.service || root.service.enterSends !== false
  readonly property string composerHint: root.enterSends
    ? "Enter sends · Shift+Enter adds a line" : "Ctrl+Enter sends · Enter adds a line"
  readonly property bool notifyOn: !!root.service && root.service.notificationsEnabled
  readonly property bool notifyPreviewOn: !root.service || root.service.notificationsPreview
  readonly property bool notifyAvailable: !root.service || root.service.notifyAvailable
  readonly property color foreground: Commons.Color.foreground
  readonly property color background: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
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
    ? root.demoItems : (root.service ? (root.service.selectedMessages || root.service.messages) : [])
  readonly property var sourceChats: root.demoMode
    ? root.demoChats : (root.service ? root.service.chats : [])
  readonly property var accountEntries: root.demoMode
    ? [{ account: "work", label: "work" },
       { account: "personal", label: "personal" }]
    : (root.service && Array.isArray(root.service.accounts)
      ? root.service.accounts : [])
  readonly property string displayGroupName: root.demoMode
    ? (root.selectedChat ? root.selectedChat.name : "WhatsApp")
    : (root.service ? root.service.selectedChatName : "WhatsApp")
  readonly property string displayKind: root.demoMode
    ? (root.selectedChat ? root.selectedChat.kind : "chat")
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
  // The account color beside a chat, only while several are linked.
  function accountMark(chat) {
    if (!root.multiAccount || !chat) return -1
    return AccountModel.accountIndex(root.accountEntries, String(chat.account || ""))
  }
  readonly property var selectedChat: {
    var jid = root.demoMode ? root.demoSelectedJid
      : (root.service ? root.service.selectedChatJid : "")
    var account = root.selectedAccount
    return AccountModel.findChat(root.sourceChats, AccountModel.chatRef(account, jid))
  }
  // The rail row carries the cached photo. Until the selected chat is in the
  // loaded rail, keep the neutral conversation glyph the header always showed.
  readonly property var headerChat: root.selectedChat
    || ({ name: "", kind: "group", avatar_path: "" })
  readonly property var forwardCandidates: AccountModel.forwardTargetsForRef(
    root.sourceChats, root.forwardOriginRef)
  readonly property var visibleChats: {
    var needle = chatSearchField ? String(chatSearchField.text || "").trim().toLowerCase() : ""
    var scope = AccountModel.normalizeScope(root.accountScope, root.accountEntries)
    return AccountModel.filterChats(root.sourceChats, scope, needle, 0, root.chatView)
  }
  readonly property var visibleMessages: {
    var needle = messageSearchField ? String(messageSearchField.text || "").trim().toLowerCase() : ""
    var filtered = sourceItems.filter(function(item) {
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

  TimelineAudio {
    id: timelineAudio
    objectName: "timelineAudio"
    messages: root.visibleMessages
    activeId: root.activeTimelinePlaybackId
    rate: root.service ? root.service.audioRate : 1
    active: root.timelineMediaActive
    onAdvanceRequested: function(messageId) { root.requestTimelinePlayback(messageId) }
  }

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

  property string demoConnectionState: "connected"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (error) {}
    var previousDemo = demoMode
    closingFromHost = false
    demoMode = payload.demo === true
    demoConnectionState = demoMode && payload.connectionState === "relink-required" ? "relink-required" : "connected"
    // Opening a closed OmaWhatsApp starts it again.
    if (!demoMode && service && service.closed === true) service.launchApp()
    demoRailDensity = demoMode && payload.density === "compact" ? "compact" : ""
    demoOnboarding = demoMode && payload.onboarding === true
    clockNow = new Date()
    opened = true
    demoVoiceState = demoMode && payload.voice === true ? "review" : "idle"
    pendingOpenChatAccount = String(payload.account || "")
    pendingOpenChatJid = String(payload.jid || "")
    narrowConversation = payload.conversation === true
    narrowSearchOpen = false
    settingsOpen = demoMode && payload.settings === true
    // Demo captures can open a given section: {"demo":true,"settings":true,"section":"media"}.
    if (settingsOpen && typeof payload.section === "string")
      Qt.callLater(function() { settingsView.openSection(payload.section) })
    replyTarget = null
    editTarget = null
    keyboardNavigation.enterComposer()
    mediaViewer.closeViewer()
    var selectedFromPayload = false
    if (pendingOpenChatJid !== "") selectedFromPayload = selectPendingOpenChat()
    chatDetailsOpen = demoMode && payload.details === true
    // {"forward":{…}} from the dropdown carries on the forward it started
    // there: the picker opens for that message instead of asking again.
    if (!demoMode && payload.forward && typeof payload.forward === "object"
        && String(payload.forward.id || "") !== "" && String(payload.jid || "") !== "") {
      var forwardItem = Object.assign({}, payload.forward)
      var forwardRef = AccountModel.chatRef(String(payload.account || ""), String(payload.jid))
      Qt.callLater(function() { root.startForwardFrom(forwardRef, [forwardItem]) })
    }
    // {"contact":{…}} from the dropdown: the shared contact's draft chat
    // opens here, over the chat the card came from.
    if (payload.contact && typeof payload.contact === "object"
        && /^[0-9]{7,15}$/.test(String(payload.contact.digits || ""))) {
      var contactCard = {
        name: String(payload.contact.name || ""), phone: String(payload.contact.phone || ""),
        digits: String(payload.contact.digits), jid: String(payload.contact.jid || "") }
      var contactMessage = { id: String(payload.contact.message_id || ""),
        sender: String(payload.contact.shared_by || ""), from_me: false }
      Qt.callLater(function() { root.openContactChat(contactCard, contactMessage) })
    }
    // {"newChat":true} opens the new chat dialog; demo captures may prefill it.
    if (payload.newChat === true) {
      // A real open may prefill digits (a shared contact's number); demo
      // captures may prefill anything.
      var newChatQuery = typeof payload.newChatQuery === "string"
        && (demoMode || /^[0-9]{6,15}$/.test(payload.newChatQuery)) ? payload.newChatQuery : ""
      Qt.callLater(function() { root.openNewChat(newChatQuery) })
    }
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

  // New chat works in the account the helper is serving; with several
  // accounts the dialog title names it.
  readonly property string newChatAccount: root.demoMode ? "work"
    : String(root.service ? root.service.statusAccount || "" : "")
  readonly property string newChatAccountLabel: {
    if (!root.multiAccount) return ""
    var entry = root.accountEntries.find(function(item) {
      return String(item.account || "") === root.newChatAccount
    })
    return entry ? String(entry.label || entry.account || "") : root.newChatAccount
  }
  // Chat details: a side panel when the window is wide, over the
  // conversation when it is not.
  property bool chatDetailsOpen: false
  readonly property bool chatDetailsBeside: chatDetailsOpen && !narrow && width >= Style.space(1100)
  // Media, links and docs: their own view, beside or over the conversation
  // like the details. The conversation itself is never filtered.
  property bool mediaBrowserOpen: false
  // A panel drawn over the conversation takes every pointer event there. Its
  // own mouse guard stops mouse areas only: tap and hover handlers on the
  // bubbles under it still fired, so the covered conversation is disabled.
  readonly property bool conversationCovered: (chatDetailsPanel.visible && !root.chatDetailsBeside)
    || (mediaBrowser.visible && !root.mediaBrowserBeside)
  property bool composerFocusBeforeCover: false
  onConversationCoveredChanged: {
    if (conversationCovered) {
      root.composerFocusBeforeCover = composer.activeFocus
      conversation.enabled = false
      return
    }
    conversation.enabled = true
    if (root.composerFocusBeforeCover) root.focusComposer()
    root.composerFocusBeforeCover = false
  }
  property string mediaBrowserKind: "media"
  readonly property bool mediaBrowserBeside: mediaBrowserOpen && !narrow && width >= Style.space(1100)
  property var viewerItems: []
  function openMediaBrowser(kind) {
    var name = ["media", "links", "docs"].indexOf(String(kind || "")) >= 0 ? String(kind) : "media"
    chatDetailsOpen = false
    mediaBrowserKind = name
    mediaBrowserOpen = true
    if (!demoMode && service) service.browseMedia(name)
    return true
  }
  function openBrowserMedia(item, gallery) {
    viewerItems = gallery
    var index = gallery.indexOf(item)
    mediaViewer.openAt(index >= 0 ? index : 0)
  }
  property var demoDetails: ({
    ok: true, kind: "chat-details", chat: { kind: "group", name: "Omarchy Lab" },
    since: 1780000000, counts: { total: 1284, media: 42, documents: 7, links: 19, starred: 3 },
    group: { created_ts: 1760000000, owner_name: "Sam Rivera", participant_count: 3, left: false },
    participants: [
      { jid: "sam@s.whatsapp.net", name: "Sam Rivera", phone: "15551234567", role: "superadmin" },
      { jid: "alex@s.whatsapp.net", name: "Alex Kim", phone: "15557654321", role: "admin" },
      { jid: "nora@s.whatsapp.net", name: "Nora Ali", phone: "15552468101", role: "member" }
    ]
  })
  readonly property var chatDetailsData: root.demoMode ? root.demoDetails
    : (root.service && root.service.chatDetails ? root.service.chatDetails : ({}))

  Binding {
    when: !root.demoMode && !!root.service
    target: root.service
    property: "chatDetailsWanted"
    value: root.opened && root.chatDetailsOpen
  }

  function toggleChatDetails() {
    chatDetailsOpen = !chatDetailsOpen
    return chatDetailsOpen
  }
  function runChatDetailsAction(action) {
    var chat = root.selectedChat
    if (!chat) return false
    if (action === "search") {
      if (!root.chatDetailsBeside) chatDetailsOpen = false
      if (root.narrow) root.narrowSearchOpen = true
      Qt.callLater(function() { messageSearchField.forceActiveFocus() })
      return true
    }
    if (action === "unread") return root.toggleChatRead(chat, false)
    if (action === "export") return root.exportChat()
    if (root.demoMode || !root.service) return false
    if (action === "download-missing") return root.service.downloadPending(root.currentChatRef(), "app")
    return root.service.chatAction(root.currentChatRef(), action, "app")
  }
  function openFromChatDetails(jid, name, phone) {
    var target = AccountModel.findChat(sourceChats, AccountModel.chatRef(root.selectedAccount, jid))
    if (target) {
      chatDetailsOpen = root.chatDetailsBeside
      selectChat(target, "composer")
      return true
    }
    // Someone from a group without a chat yet: the new chat dialog takes it.
    chatDetailsOpen = false
    return openNewChat(/^[0-9]{6,}$/.test(String(phone || "")) ? "+" + phone : String(name || ""))
  }

  property var demoPeople: [
    { jid: "demo-alex", name: "Alex", phone: "15557654321", has_chat: true },
    { jid: "15551234567@s.whatsapp.net", name: "Sam Rivera", phone: "15551234567", has_chat: false },
    { jid: "15552468101@s.whatsapp.net", name: "Nora Ali", phone: "15552468101", has_chat: false }
  ]

  // Page Up/Down move a screen through the conversation, Home goes to the
  // oldest loaded message and End back to the newest.
  function pageConversation(key) {
    if (messageList.count === 0) return false
    var minY = messageList.originY
    var maxY = messageList.originY + Math.max(0, messageList.contentHeight - messageList.height)
    var step = messageList.height * 0.85
    if (key === Qt.Key_PageUp) messageList.contentY = Math.max(minY, messageList.contentY - step)
    else if (key === Qt.Key_PageDown) messageList.contentY = Math.min(maxY, messageList.contentY + step)
    else if (key === Qt.Key_Home) messageList.positionViewAtEnd()
    else if (key === Qt.Key_End) scrollToNewest()
    else return false
    return true
  }

  // The day of the topmost message on screen floats at the top while the
  // conversation scrolls away from the newest message, and fades soon after.
  property string floatingDayLabel: ""
  function showFloatingDay() {
    if (messageList.count === 0) return
    var index = messageList.indexAt(messageList.width / 2, messageList.contentY + Style.space(12))
    var item = index >= 0 ? root.visibleMessages[index] : null
    floatingDayLabel = item ? TimeFormat.dayLabel(item.timestamp) : ""
    floatingDayHold.restart()
  }

  // How far the newest message's bottom edge sits below the list's bottom
  // edge (0 at the newest); a newest message scrolled out of the list counts
  // as far away. `contentY` is passed so bindings re-evaluate on scroll.
  // Positioning runs again once the newest bubbles have their real height
  // (images, fonts): a single pass left the newest message cut at the bottom.
  function scrollToNewest() {
    messageList.positionViewAtBeginning()
    Qt.callLater(function() {
      messageList.positionViewAtBeginning()
      Qt.callLater(function() { messageList.positionViewAtBeginning() })
    })
  }

  function newestMessageOffset(list, contentY) {
    if (!list || list.count === 0) return 0
    var item = list.itemAtIndex(0)
    if (!item) return 100000
    return item.mapToItem(list, 0, item.height).y - list.height
  }

  function oldestMessageInView() {
    if (messageList.count === 0) return false
    var item = messageList.itemAtIndex(messageList.count - 1)
    if (!item) return false
    var top = item.mapToItem(messageList, 0, 0).y
    return top + item.height >= 0 && top <= messageList.height
  }
  function maybeLoadOlder() {
    if (demoMode || !service || !opened || typeof service.loadOlderMessages !== "function") return false
    if (messageSearchField.text.trim() !== "") return false
    if (!oldestMessageInView()) return false
    return service.loadOlderMessages()
  }
  onOpenedChanged: if (opened) Qt.callLater(maybeLoadOlder)

  // A sticker from the picker goes at once, as on the phone, answering the
  // message being replied to if there is one.
  function sendPickedSticker(path) {
    if (demoMode || !service || currentChatKey() === "") return false
    var replyId = replyTarget ? String(replyTarget.id || "") : ""
    var started = service.sendSticker(currentChatRef(), path, replyId, "app")
    if (!started) attachmentError = "Finish the current WhatsApp action before sending a sticker."
    else if (replyTarget) replyTarget = null
    return started
  }

  function openQuickSwitcher() {
    if (!opened) return false
    settingsOpen = false
    quickSwitcher.open()
    return true
  }

  function openNewChat(query) {
    if (!opened) return false
    settingsOpen = false
    newChatDialog.open()
    if (typeof query === "string" && query !== "")
      Qt.callLater(function() { newChatDialog.typeQuery(query) })
    return true
  }

  function openNewChatResult(jid) {
    var account = root.demoMode ? "" : root.newChatAccount
    var target = AccountModel.findChat(sourceChats, AccountModel.chatRef(account, jid))
      || sourceChats.find(function(chat) { return String(chat.jid || "") === String(jid) })
    if (target) selectChat(target, "composer")
    return !!target
  }

  function followStartedChat(jid) {
    if (root.demoMode) return
    pendingOpenChatAccount = root.newChatAccount
    pendingOpenChatJid = String(jid || "")
    if (!selectPendingOpenChat() && service) service.refreshChats()
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

  // Quit: the window closes and every account's sync stops until
  // OmaWhatsApp opens again; it still starts with the system if set to.
  function quitApp() {
    if (demoMode) { close(); return true }
    if (!service || !service.quitApp()) return false
    close()
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

  function focusChatView(index) {
    var chip = railViewRepeater.itemAt(index)
    if (!chip) return
    if (root.narrow) {
      root.narrowConversation = false
      root.narrowSearchOpen = false
    } else root.sidebarCollapsed = false
    chip.forceActiveFocus(Qt.TabFocusReason)
  }

  function cycleRailFocus(backwards) {
    var focusedView = railViewRepeater.itemAt(keyboardNavigation.chatViewIndex)
    if (root.keyboardContext === "chat-views" && focusedView && focusedView.activeFocus
        && !root.textEntryActive) {
      var next = keyboardNavigation.chatViewIndex + (backwards ? -1 : 1)
      if (next < 0 || next >= root.chatViews.length) root.focusChats()
      else root.focusChatView(next)
      return true
    }
    if ((root.keyboardContext === "chats" && keyboardHome.activeFocus && !root.textEntryActive)
        || chatSearchField.activeFocus) {
      root.focusChatView(backwards ? root.chatViews.length - 1 : 0)
      return true
    }
    return false
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
    if (root.mediaBrowserOpen) {
      root.mediaBrowserOpen = false
      return
    }
    if (root.chatDetailsOpen) {
      root.chatDetailsOpen = false
      return
    }
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

  // A send while another WhatsApp action runs (often the read mark of a chat
  // just opened from a notification) waits for it instead of being dropped.
  property string queuedSendKey: ""
  readonly property bool sendQueued: queuedSendKey !== "" && queuedSendKey === currentChatKey()
  function runQueuedSend() {
    if (queuedSendKey === "" || !service || service.writing) return false
    if (queuedSendKey !== currentChatKey()) {
      queuedSendKey = ""
      return false
    }
    queuedSendKey = ""
    sendDraft()
    return true
  }

  // Presence of the open chat: typing, online or last seen, when wacli
  // follows presence; the account is shown online while this window has focus.
  readonly property bool windowFocused: root.opened && focusScope.Window.active
  onWindowFocusedChanged: if (!root.demoMode && root.service)
    root.service.setPresenceFocus("app", root.windowFocused)
  // The service may go first when the shell tears everything down.
  Component.onDestruction: if (!root.demoMode && root.service && root.service.setPresenceFocus)
    root.service.setPresenceFocus("app", false)
  readonly property var presenceLine: {
    if (root.demoMode || !root.service || root.currentJid() === "") return { text: "", live: false }
    var names = ({})
    var people = root.service.members || []
    for (var i = 0; i < people.length; i++)
      if (people[i] && people[i].jid) names[String(people[i].jid)] = String(people[i].name || "")
    var now = root.service.presenceNow
    return PresenceModel.line(root.service.presenceSnapshotFor(root.selectedAccount), root.currentJid(), {
      now: now, date: new Date(now * 1000), group: root.displayKind === "group", names: names,
      clock: TimeFormat.clockPattern(root.timeFormat, Qt.locale().timeFormat(Locale.ShortFormat))
    })
  }
  function chatTyping(chat) {
    if (root.demoMode || !root.service || !chat) return false
    return PresenceModel.isTyping(root.service.presenceSnapshotFor(String(chat.account || "")),
      String(chat.jid || ""), root.service.presenceNow)
  }

  // The tick for a sent message's delivery state; "" when none is known.
  function tickGlyph(status) {
    return AccountModel.deliveryGlyph(status)
  }

  function sendDraft() {
    var value = composer.text.trim()
    if (value === "" && pendingAttachments.length === 0) return
    if (demoMode) {
      demoItems = [ComposerModel.demoMessage(root.signatureSkipped ? value
        : ComposerModel.signedText(value, root.demoSignature),
        pendingAttachments.length > 0, replyTarget, Date.now())].concat(demoItems)
      signatureSkipped = false
      composer.text = ""
      pendingAttachments = []
      pendingStickerPath = ""
      selectedMentions = []
      closeMentionCompletion()
      attachmentError = ""
      cancelComposerContext(false)
      return
    }
    if (!service) return
    // Plain texts join the service queue at once; stickers, files and edits
    // still wait here for the running action to finish.
    var queuesInService = pendingStickerPath === "" && pendingAttachments.length === 0
      && editTarget === null
    if (service.writing && !queuesInService) {
      queuedSendKey = currentChatKey()
      return
    }
    queuedSendKey = ""
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
        request.reply_id, "app", !root.signatureSkipped)
      if (started) root.signatureSkipped = false
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
          request.mentions, "app", !root.signatureSkipped)
    if (started && kind === "send") root.signatureSkipped = false
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

  // WhatsApp's formatting on the composer: markers around the selection, or
  // list and quote prefixes on its lines. Edits go through remove/insert so
  // Ctrl+Z still undoes them.
  // Right-click in the composer: editing actions, then WhatsApp formatting.
  function openComposerMenu(x, y) {
    var point = composer.mapToItem(formatMenu.parent, x, y)
    formatMenu.x = Math.max(0, Math.min(formatMenu.parent.width - formatMenu.width, point.x))
    formatMenu.y = Math.max(-formatMenu.height - Style.space(6), point.y - formatMenu.height)
    formatMenu.open()
  }
  function composerMenuAction(kind) {
    if (kind === "cut") composer.cut()
    else if (kind === "copy") composer.copy()
    else if (kind === "paste") root.pasteDraft()
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

  // "Message" on a shared contact: its chat when there is one, otherwise the
  // new chat dialog with the number already typed.
  // "Message" on a shared contact: the chat with that person if there is
  // one, else a draft chat that starts with the first message.
  function openContactChat(card, message) {
    if (!card) return false
    var jid = String(card.jid || "")
    var chats = root.sourceChats
    var known = jid === "" ? null : chats.find(function(chat) {
      return String(chat.jid || "") === jid
        && String(chat.account || "") === String(root.selectedAccount || chat.account || "")
    })
    if (known) {
      selectChat(known)
      return true
    }
    var digits = String(card.digits || "").replace(/[^0-9]/g, "")
    if (digits.length < 7 || digits.length > 15) return false
    contactDraft = {
      name: String(card.name || "").trim() || ("+" + digits),
      phone: String(card.phone || "").trim() || ("+" + digits),
      digits: digits, jid: jid,
      originRef: currentChatRef(), originName: String(root.displayGroupName || "the chat"),
      sharedBy: message && message.from_me !== true ? String(message.sender || "").trim().split(/\s+/)[0] : "",
      messageId: message ? String(message.id || "") : ""
    }
    contactDraftError = ""
    contactDraftSending = false
    contactDraftField.text = ""
    // Asking WhatsApp whether the number is there happens once, here; nothing
    // is sent until Enter.
    if (jid === "" && !demoMode && service && typeof service.checkNumber === "function")
      service.checkNumber("+" + digits)
    Qt.callLater(function() { contactDraftField.forceActiveFocus() })
    return true
  }

  function closeContactDraft() {
    contactDraft = null
    contactDraftSending = false
    contactDraftError = ""
    focusComposer()
  }

  // Back in the chat it came from, on the card itself.
  function showContactCard() {
    var id = contactDraft ? contactDraft.messageId : ""
    closeContactDraft()
    var index = AccountModel.messageIndexOf(root.visibleMessages, id)
    if (index < 0) return false
    cursorIndex = index
    Qt.callLater(function() { messageList.positionViewAtIndex(index, ListView.Center) })
    focusMessages()
    return true
  }

  function retryContactCheck() {
    if (!contactDraft || demoMode || !service) return false
    return service.checkNumber("+" + contactDraft.digits)
  }

  function sendContactDraft() {
    var text = String(contactDraftField.text || "").trim()
    if (!contactDraft || text === "" || contactDraftSending || root.contactDraftJid === "") return false
    contactDraftError = ""
    if (demoMode) {
      showToast("message sent to " + contactDraft.name)
      closeContactDraft()
      return true
    }
    if (!service || !service.startNewChat(root.contactDraftJid, text, "app")) {
      contactDraftError = service && service.errorText ? service.errorText
        : "WhatsApp is busy with another request. Try again in a moment."
      return false
    }
    contactDraftSending = true
    return true
  }

  function pasteDraft() {
    if (demoMode) return
    // The helper also pastes images and files; plain text still pastes when
    // it cannot run.
    if (!service || !service.pasteClipboard(currentChatRef(), "app")) composer.paste()
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

  // File dialogs are zenity's; on a stock Omarchy it is not installed yet.
  function zenityReady() {
    if (root.demoMode || !root.service || root.service.zenityAvailable !== false) return true
    root.showToast("Choosing files needs zenity. Paste or drag files in meanwhile.",
      "Install", function() { root.service.installZenity() })
    return false
  }

  function openFilePicker(kind) {
    var origin = currentChatRef()
    if (filePickerProcess.running || origin.jid === "") return
    if (!zenityReady()) return
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

  // Save as…: a zenity save dialog, then the helper copies the attachment
  // (downloading it first, without pausing sync, when it is not local yet).
  function saveMediaAs(item) {
    if (!item || !item.id || savePickerProcess.running) return false
    var origin = currentChatRef()
    if (origin.jid === "" || root.demoMode || !root.service) return false
    if (!zenityReady()) return false
    var name = String(item.filename || "").split("/").pop()
    if (name === "") name = String(item.local_path || "").split("/").pop()
    if (name === "") name = "attachment"
    savePickerProcess.item = item
    savePickerProcess.originRef = AccountModel.chatRef(origin.account, origin.jid)
    savePickerProcess.command = ["/usr/bin/zenity", "--file-selection", "--save",
      "--confirm-overwrite", "--title=Save attachment",
      "--filename=" + String(Quickshell.env("HOME") || "") + "/Downloads/" + name]
    savePickerProcess.running = true
    return true
  }

  // Export chat: a zenity save dialog, then the helper writes readable text.
  function exportChat() {
    var origin = currentChatRef()
    if (origin.jid === "" || root.demoMode || !root.service || exportPickerProcess.running) return false
    if (!zenityReady()) return false
    var name = String(root.displayGroupName || "chat").replace(/[\/\\:*?"<>|]+/g, " ").trim() || "chat"
    exportPickerProcess.originRef = AccountModel.chatRef(origin.account, origin.jid)
    exportPickerProcess.command = ["/usr/bin/zenity", "--file-selection", "--save",
      "--confirm-overwrite", "--title=Export chat",
      "--filename=" + String(Quickshell.env("HOME") || "") + "/Documents/WhatsApp - " + name + ".txt"]
    exportPickerProcess.running = true
    return true
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

  function showToast(message, actionLabel, actionChat) {
    toastText = String(message || "")
    toastActionLabel = actionChat ? String(actionLabel || "") : ""
    toastActionChat = actionChat || null
    // A toast with something to do stays long enough to do it.
    copyToastTimer.interval = toastActionLabel !== "" ? 6000 : 1800
    copyToastVisible = true
    copyToastTimer.restart()
  }

  function runToastAction() {
    var chat = toastActionChat
    copyToastVisible = false
    toastActionChat = null
    if (!chat) return false
    // An action that is not a chat, such as installing a missing tool.
    if (typeof chat === "function") { chat(); return true }
    var ref = String(chat.jid || "") === "" && String(chat.phone || "") !== ""
      ? AccountModel.chatRef(String(chat.account || ""), String(chat.phone) + "@s.whatsapp.net")
      : AccountModel.refOf(chat)
    var known = AccountModel.findChat(sourceChats, ref)
    if (known) selectChat(known)
    return !!known
  }

  // "N unread messages" divider: the count is captured when the chat is
  // chosen, before automatic reading clears it.
  // The divider stays above the message that was the oldest unread one, so
  // replies sent from here never land above it.
  property var unreadMarker: ({ key: "", count: 0, anchor: "", resolved: true })
  property bool unreadMarkerPositioned: true
  readonly property int unreadDividerIndex: root.unreadMarker.key !== ""
    && root.unreadMarker.key === root.currentChatKey() && root.unreadMarker.count > 0
    ? AccountModel.messageIndexOf(root.visibleMessages, root.unreadMarker.anchor) : -1
  function resolveUnreadAnchor() {
    var marker = root.unreadMarker
    if (marker.resolved || marker.key !== root.currentChatKey()
        || !AccountModel.hasStoredMessages(root.sourceItems)) return
    root.unreadMarker = Object.assign({}, marker, {
      anchor: AccountModel.unreadAnchorId(root.sourceItems, marker.count), resolved: true })
  }
  onVisibleMessagesChanged: {
    root.resolveUnreadAnchor()
    if (root.unreadMarkerPositioned || root.unreadDividerIndex < 0) return
    root.unreadMarkerPositioned = true
    var target = root.unreadDividerIndex
    Qt.callLater(function() { messageList.positionViewAtIndex(target, ListView.Contain) })
  }

  function selectChat(chat, focusTarget) {
    if (!chat) return
    root.signatureSkipped = false
    root.unreadMarker = { key: AccountModel.refOf(chat).key, count: Number(chat.unread || 0),
      anchor: "", resolved: Number(chat.unread || 0) <= 0 }
    root.unreadMarkerPositioned = Number(chat.unread || 0) <= 0
    saveComposerState()
    messageSearchField.text = ""
    cursorIndex = 0
    if (demoMode) {
      demoSelectedAccount = String(chat.account || "")
      demoSelectedJid = String(chat.jid)
    }
    else if (service) service.selectChat(chat)
    // Messages may already be the ones of this chat (the same chat, or demo).
    root.resolveUnreadAnchor()
    restoreComposerState(AccountModel.refOf(chat).key)
    if (narrow) narrowConversation = true
    if (focusTarget === "messages") root.focusMessages()
    else root.focusComposer()
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

  // An unsent draft shows in the list, as on the phone; the open chat shows
  // it in its own composer instead.
  function draftFor(chat) {
    if (!chat) return ""
    var key = AccountModel.refOf(chat).key
    if (key === "" || key === root.currentChatKey()) return ""
    var state = root.composerStates[key]
    if (!state) return ""
    var text = String(state.text || "").replace(/\s+/g, " ").trim()
    if (text !== "") return text
    return Array.isArray(state.attachments) && state.attachments.length > 0 ? "attachment" : ""
  }

  function chatIsUnread(chat) {
    return !!chat && Number(chat.unread || 0) > 0
  }
  function toggleChatRead(chat, forceRead) {
    if (!chat) return false
    var read = forceRead === undefined ? root.chatIsUnread(chat) : forceRead === true
    if (root.demoMode) {
      root.demoChats = root.demoChats.map(function(item) {
        if (String(item.jid) !== String(chat.jid)) return item
        var next = Object.assign({}, item)
        next.unread = read ? 0 : 1
        return next
      })
      return true
    }
    return !!root.service && root.service.setChatRead(AccountModel.refOf(chat), read, "app")
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

  function requestRemoveLocalChat(target) {
    var chat = target || root.selectedChat
    if (!chat || !chat.jid) return
    removeLocalTargetRef = target ? AccountModel.refOf(target) : currentChatRef()
    removeLocalConfirm.open()
  }

  // Right-click on a rail row: the same chat actions as the conversation menu,
  // aimed at that exact row, plus read or unread.
  property var contextChat: null
  readonly property var contextChatActions: {
    var chat = root.contextChat
    if (!chat) return []
    return [
      { label: root.chatIsUnread(chat) ? "Mark as read" : "Mark as unread",
        action: root.chatIsUnread(chat) ? "read" : "unread", destructive: false },
      { label: chat.pinned ? "Unpin chat" : "Pin chat",
        action: chat.pinned ? "unpin" : "pin", destructive: false },
      { label: chat.muted ? "Unmute notifications" : "Mute notifications",
        action: chat.muted ? "unmute" : "mute", destructive: false },
      { label: chat.archived ? "Unarchive chat" : "Archive chat",
        action: chat.archived ? "unarchive" : "archive", destructive: false },
      { label: "Remove local chat…", action: "remove-local", destructive: true }
    ]
  }
  function openChatContextMenu(chat, x, y) {
    root.contextChat = chat
    chatContextMenu.x = x
    chatContextMenu.y = y
    chatContextMenu.open()
  }
  function runChatContextAction(action) {
    var chat = root.contextChat
    chatContextMenu.close()
    if (!chat) return false
    if (action === "read" || action === "unread") return root.toggleChatRead(chat, action === "read")
    if (action === "remove-local") { root.requestRemoveLocalChat(chat); return true }
    if (root.demoMode || !root.service) return false
    return root.service.chatAction(AccountModel.refOf(chat), action, "app")
  }

  function dismissRemoveLocalChat() {
    removeLocalTargetRef = AccountModel.chatRef("", "")
    removeLocalConfirm.close()
  }

  function confirmRemoveLocalChat() {
    var targetRef = removeLocalTargetRef
    dismissRemoveLocalChat()
    if (String(targetRef.jid || "") === "") return false
    if (demoMode) {
      demoChats = demoChats.filter(function(chat) {
        return !AccountModel.sameRef(AccountModel.refOf(chat), targetRef)
      })
      if (!root.selectedChat) {
        if (demoChats.length > 0) {
          root.selectChat(demoChats[0])
        } else {
          root.saveComposerState()
          demoSelectedAccount = ""
          demoSelectedJid = ""
          demoItems = []
          root.restoreComposerState("")
        }
      }
      return true
    }
    if (!service) return false
    return service.chatAction(targetRef, "remove-local", "app")
  }

  // Forward from a message: the conversation enters selection mode with it
  // picked, so more can be added before choosing where they go.
  function startForward(item) {
    var ids = messageIdsOf(item)
    if (ids.length === 0 || item.pending === true) return false
    forwardOriginRef = currentChatRef()
    selectedMessageIds = ids
    selectingMessages = true
    return true
  }

  // An album row stands for each of its photos.
  function messageIdsOf(item) {
    if (!item) return []
    var parts = item.album_items && typeof item.album_items.length === "number" && item.album_items.length > 0
      ? Array.prototype.slice.call(item.album_items) : [item]
    return parts.map(function(part) { return String(part && part.id || "") })
      .filter(function(id) { return id !== "" })
  }

  function isMessageSelected(item) {
    var ids = messageIdsOf(item)
    return ids.length > 0 && ids.every(function(id) { return selectedMessageIds.indexOf(id) >= 0 })
  }

  function toggleMessageSelection(item) {
    var ids = messageIdsOf(item)
    if (ids.length === 0 || item.pending === true || item.revoked === true) return false
    selectedMessageIds = isMessageSelected(item)
      ? selectedMessageIds.filter(function(value) { return ids.indexOf(value) < 0 })
      : selectedMessageIds.concat(ids.filter(function(id) { return selectedMessageIds.indexOf(id) < 0 }))
    return true
  }

  function cancelSelection() {
    selectingMessages = false
    selectedMessageIds = []
  }

  // The picked messages oldest first, the order they are forwarded in.
  function selectedMessages() {
    var picked = []
    var ids = selectedMessageIds
    root.visibleMessages.forEach(function(item) {
      var parts = item && item.album_items && typeof item.album_items.length === "number"
        ? Array.prototype.slice.call(item.album_items) : [item]
      parts.forEach(function(part) {
        if (part && ids.indexOf(String(part.id || "")) >= 0 && picked.indexOf(part) < 0) picked.push(part)
      })
    })
    return picked.sort(function(a, b) { return Number(a.timestamp || 0) - Number(b.timestamp || 0) })
  }

  function copySelection() {
    var text = selectedMessages().map(function(item) { return String(item.text || "").trim() })
      .filter(function(value) { return value !== "" }).join("\n")
    if (text === "") return false
    copyText(text)
    showToast("copied " + selectedMessageIds.length + (selectedMessageIds.length === 1 ? " message" : " messages"))
    cancelSelection()
    return true
  }

  // Star: every linked device sees it; needs a wacli build that stars.
  readonly property bool starAvailable: root.demoMode || (!!root.service && root.service.starSupported === true)
  readonly property bool selectionAllStarred: {
    var picked = root.selectingMessages ? root.selectedMessages() : []
    return picked.length > 0 && picked.every(function(item) { return item.starred === true })
  }
  function setDemoStarred(ids, starred) {
    demoItems = demoItems.map(function(item) {
      return ids.indexOf(String(item.id)) < 0 ? item : Object.assign({}, item, { starred: starred })
    })
  }
  function starSelection(starred) {
    var items = selectedMessages()
    if (items.length === 0) return false
    if (demoMode) {
      setDemoStarred(items.map(function(item) { return String(item.id) }), starred)
      cancelSelection()
      showToast((starred ? "starred " : "unstarred ") + (items.length === 1 ? "1 message" : items.length + " messages"))
      return true
    }
    if (!service || !service.starMany(forwardOriginRef, items, starred, "app")) return false
    cancelSelection()
    return true
  }
  function starOne(item, starred) {
    if (!item) return false
    if (demoMode) { setDemoStarred([String(item.id)], starred); return true }
    return !!service && service.starMessage(currentChatRef(), item, starred, "app")
  }

  // Delete the picked messages: for you, or for everyone when all are yours.
  readonly property bool selectionAllMine: {
    var picked = root.selectingMessages ? root.selectedMessages() : []
    return picked.length > 0 && picked.every(function(item) { return item.from_me === true })
  }
  function requestDeleteSelection() {
    if (selectedMessageIds.length === 0) return false
    batchDeleteConfirm.open()
    return true
  }
  function deleteSelection(forMe) {
    var items = selectedMessages()
    var origin = forwardOriginRef
    batchDeleteConfirm.close()
    if (items.length === 0 || (forMe !== true && !selectionAllMine)) return false
    if (demoMode) {
      var ids = items.map(function(item) { return String(item.id) })
      demoItems = forMe === true
        ? demoItems.filter(function(item) { return ids.indexOf(String(item.id)) < 0 })
        : demoItems.map(function(item) {
            return ids.indexOf(String(item.id)) < 0 ? item : Object.assign({}, item, { revoked: true, text: "" }) })
      cancelSelection()
      showToast(items.length === 1 ? "message deleted" : items.length + " messages deleted")
      return true
    }
    if (!service || !service.deleteMany(origin, items, forMe === true, "app")) return false
    cancelSelection()
    showToast("deleting " + (items.length === 1 ? "1 message" : items.length + " messages") + "…")
    return true
  }

  function openForwardDialog() {
    var items = selectedMessages()
    if (items.length === 0) return false
    return startForwardFrom(forwardOriginRef, items)
  }

  // Straight to the dialog, as the dropdown hands a forward over.
  function startForwardFrom(originRef, items) {
    var list = Array.isArray(items) ? items : [items]
    list = list.filter(function(item) { return item && String(item.id || "") !== "" })
    if (list.length === 0) return false
    forwardItems = list
    forwardOriginRef = originRef
    forwardChosen = []
    forwardSearch.text = ""
    forwardNote.text = ""
    forwardPicker.open()
    Qt.callLater(function() { forwardSearch.forceActiveFocus() })
    return true
  }

  function dismissForward() {
    forwardItems = []
    forwardChosen = []
    forwardPicker.close()
  }

  // A chosen chat, or a typed number (no chat yet) by its digits.
  function forwardKey(chat) {
    if (!chat) return ""
    return String(chat.jid || "") === "" && String(chat.phone || "") !== ""
      ? "phone:" + String(chat.phone) : AccountModel.refOf(chat).key
  }

  function isForwardChosen(chat) {
    var key = forwardKey(chat)
    return key !== "" && forwardChosen.some(function(item) { return forwardKey(item) === key })
  }

  function toggleForwardTarget(chat) {
    if (!chat || (String(chat.jid || "") === "" && !/^[0-9]{7,15}$/.test(String(chat.phone || "")))
        || String(chat.account || "") !== String(forwardOriginRef.account || "")) return false
    var key = forwardKey(chat)
    forwardChosen = isForwardChosen(chat)
      ? forwardChosen.filter(function(item) { return forwardKey(item) !== key })
      : forwardChosen.concat([chat])
    return true
  }

  // The forward search as a phone number, when it reads as one.
  readonly property string forwardDigits: {
    var raw = forwardSearch ? String(forwardSearch.text || "").trim() : ""
    if (!/^[+]?[0-9 ().-]+$/.test(raw)) return ""
    var digits = raw.replace(/[^0-9]/g, "")
    return digits.length >= 7 && digits.length <= 15 && digits.charAt(0) !== "0" ? digits : ""
  }
  readonly property var forwardNumberCheck: root.forwardDigits === "" ? null
    : root.demoMode ? ({ phone: root.forwardDigits, loading: false, registered: true, error: "" })
    : (root.service && typeof root.service.numberCheckFor === "function"
      ? root.service.numberCheckFor(root.forwardDigits) : null)
  readonly property string forwardNumberState: root.forwardDigits === "" ? ""
    : root.forwardNumberCheck === null ? "idle"
    : root.forwardNumberCheck.loading ? "checking"
    : root.forwardNumberCheck.error ? "error"
    : root.forwardNumberCheck.registered ? "registered" : "absent"
  // The typed number: checked once, then added like a chat.
  function useForwardNumber() {
    if (root.forwardDigits === "") return false
    if (root.forwardNumberState === "registered") {
      // The chip reads as typed: +55 16 99999-0000.
      var typed = String(forwardSearch.text || "").trim()
      var added = toggleForwardTarget({ account: String(forwardOriginRef.account || ""), jid: "",
        phone: root.forwardDigits, name: typed.charAt(0) === "+" ? typed : "+" + typed, kind: "dm" })
      if (added) forwardSearch.text = ""
      return added
    }
    if (root.forwardNumberState === "idle" || root.forwardNumberState === "error")
      return !!root.service && root.service.checkNumber("+" + root.forwardDigits)
    return false
  }

  function forwardNames(targets) {
    var names = (targets || []).map(function(chat) { return String(chat.name || "WhatsApp chat") })
    if (names.length <= 2) return names.join(" and ")
    return names.slice(0, 2).join(", ") + " and " + (names.length - 2)
      + (names.length === 3 ? " other chat" : " other chats")
  }

  function sendForward() {
    var origin = forwardOriginRef
    if (forwardItems.length === 0 || forwardChosen.length === 0 || String(origin.jid || "") === "") return false
    var targets = forwardChosen.slice()
    if (demoMode) {
      dismissForward()
      cancelSelection()
      showToast("forwarded to " + forwardNames(targets), "Open " + String(targets[0].name || "chat"), targets[0])
      return true
    }
    if (!service || !service.forwardMany(origin, forwardItems, targets, forwardNote.text, "app")) return false
    dismissForward()
    cancelSelection()
    showToast("forwarding to " + forwardNames(targets) + "…")
    return true
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

  // "Pinned" over the first pinned chat and "Recent" over the first chat
  // after them, in the full list with no search only.
  function railSectionLabel(index) {
    if (root.chatView !== "all" || String(chatSearchField.text || "").trim() !== "") return ""
    var chats = root.visibleChats
    if (!chats || chats.length === 0 || !chats[0] || chats[0].pinned !== true) return ""
    var chat = chats[index]
    if (!chat) return ""
    if (index === 0) return "Pinned"
    var previous = chats[index - 1]
    return chat.pinned !== true && previous && previous.pinned === true ? "Recent" : ""
  }

  // A group member's cached photo, from their own chat in this account.
  readonly property var avatarsByJid: {
    var map = ({})
    var chats = root.sourceChats || []
    for (var i = 0; i < chats.length; i++) {
      var chat = chats[i]
      if (chat && String(chat.avatar_path || "") !== "" && chat.kind !== "group")
        map[String(chat.account || "") + "\n" + String(chat.jid || "")] = String(chat.avatar_path)
    }
    return map
  }
  function senderAvatarPath(message) {
    if (!message || message.from_me === true) return ""
    return root.avatarsByJid[String(root.selectedAccount || "") + "\n"
      + String(message.sender_jid || "")] || ""
  }

  // A key typed into the box (not a restored draft) shows "typing…" to the
  // chat once the text has changed.
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

  function previewKindGlyph(kind) {
    return AccountModel.previewKindGlyph(kind)
  }

  function formatTime(seconds) {
    if (!seconds) return ""
    return Qt.formatDateTime(new Date(Number(seconds) * 1000),
      "ddd " + TimeFormat.clockPattern(root.timeFormat,
        Qt.locale().timeFormat(Locale.ShortFormat)))
  }

  function localMediaUrl(path) {
    var value = String(path || "")
    if (value === "__demo__") return Qt.resolvedUrl("assets/demo-capture.svg")
    if (value === "__demo_photo__") return Qt.resolvedUrl("assets/demo-photo.png")
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
    var granted = false
    if (demoMode || !playbackCoordinator) {
      demoTimelinePlaybackId = String(messageId || "")
      granted = demoTimelinePlaybackId !== ""
    } else {
      granted = playbackCoordinator.acquire("app-timeline", currentChatRef(), messageId)
    }
    // A voice note plays in the timeline's own player; video and GIFs keep
    // theirs in the bubble.
    if (granted && timelineAudio.playable(timelineAudio.itemFor(messageId)))
      timelineAudio.play(messageId)
    return granted
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

  function replyToCursor() {
    if (visibleMessages.length === 0) return false
    var index = Math.max(0, Math.min(cursorIndex, visibleMessages.length - 1))
    var item = visibleMessages[index]
    if (!item || item.pending === true) return false
    root.startReply(item)
    return true
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
    function onPasteFailed(message, chatRef, owner) {
      if (!ComposerModel.ownsOperation(owner, "app")) return
      if (String(chatRef && chatRef.key || "") === root.composerChatKey) composer.paste()
    }
    function onWritingChanged() {
      if (root.service && !root.service.writing && root.queuedSendKey !== "")
        Qt.callLater(root.runQueuedSend)
    }
    function onTextPasted(text, chatRef, owner) {
      if (!ComposerModel.ownsOperation(owner, "app")) return
      var key = String(chatRef && chatRef.key || "")
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
    }
    function onAttachmentPasted(path, chatRef, owner) {
      if (!ComposerModel.ownsOperation(owner, "app")) return
      var key = String(chatRef && chatRef.key || "")
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
    }
    function onWriteCompleted(kind, chatRef, request, owner) {
      if (kind === "media" && root.mediaBrowserOpen && root.service)
        root.service.browseMedia(root.mediaBrowserKind)
      if (!ComposerModel.ownsOperation(owner, "app")) return
      var answer = root.service && root.service.lastWriteResult ? root.service.lastWriteResult : ({})
      if (kind === "export-chat")
        root.showToast("exported " + Number(answer.messages || 0) + " messages")
      if (kind === "download-pending")
        root.showToast(Number(answer.downloaded || 0) + " downloaded"
          + (Number(answer.expired || 0) > 0 ? ", " + answer.expired + " expired on WhatsApp" : ""))
      if (kind === "contact-alias") root.showToast(String(request.alias || "") !== "" ? "alias saved" : "alias removed")
      // The first message to a shared contact: the new chat opens.
      if (kind === "send-new" && root.contactDraftSending && root.contactDraft
          && String(request.target && request.target.jid || "") === root.contactDraftJid) {
        var landed = root.service ? String(root.service.lastStartedChatJid || "") : ""
        root.contactDraft = null
        root.contactDraftSending = false
        root.followStartedChat(landed !== "" ? landed : String(request.target.jid))
        return
      }
      // Forwarding happens in another chat: say where it went. A batch says
      // it once, when it ends.
      if (kind === "forward" && request.batch !== true)
        root.showToast("forwarded to " + String(answer.target || "the chat"))
      if (kind === "contact-tag") root.showToast(request.remove ? "tag removed" : "tag added")
      if (kind === "star" && request.batch !== true)
        root.showToast(request.starred === false ? "unstarred" : "starred · on your other devices too")
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
      if (sameChat && kind !== "forward") root.focusComposer()
    }
    function onChatStateFailed(message, chatRef, action, owner) {
      if (!ComposerModel.ownsOperation(owner, "app")) return
      root.showToast((action === "unread" ? "could not mark unread · " : "could not mark read · ")
        + String(message || "WhatsApp did not answer"))
    }
    function onStarBatchFinished(summary) {
      if (!summary || !ComposerModel.ownsOperation(summary.owner, "app")) return
      var done = Number(summary.total || 0) - Number(summary.failed || 0)
      var verb = summary.starred === false ? "unstarred " : "starred "
      if (Number(summary.failed || 0) === 0)
        root.showToast(verb + (done === 1 ? "1 message" : done + " messages"))
      else
        root.showToast(Number(summary.failed) + " of " + Number(summary.total) + " could not be "
          + (summary.starred === false ? "unstarred" : "starred")
          + (summary.errors && summary.errors.length > 0 ? " · " + String(summary.errors[0]) : ""))
    }
    function onDeleteBatchFinished(summary) {
      if (!summary || !ComposerModel.ownsOperation(summary.owner, "app")) return
      var deleted = Number(summary.total || 0) - Number(summary.failed || 0)
      if (Number(summary.failed || 0) === 0)
        root.showToast(deleted === 1 ? "message deleted" : deleted + " messages deleted")
      else
        root.showToast(Number(summary.failed) + " of " + Number(summary.total)
          + " could not be deleted" + (summary.errors && summary.errors.length > 0
            ? " · " + String(summary.errors[0]) : ""))
    }
    function onForwardBatchFinished(summary) {
      if (!summary || !ComposerModel.ownsOperation(summary.owner, "app")) return
      var targets = summary.targets || []
      if (Number(summary.failed || 0) === 0)
        root.showToast("forwarded to " + root.forwardNames(targets),
          targets.length > 0 ? "Open " + String(targets[0].name || "chat") : "", targets[0])
      else
        root.showToast(Number(summary.failed) + " of " + Number(summary.total)
          + " could not be forwarded" + (summary.errors && summary.errors.length > 0
            ? " · " + String(summary.errors[0]) : ""))
    }
    function onWriteFailed(message, chatRef, details, owner) {
      if (!ComposerModel.ownsOperation(owner, "app")) return
        var key = String(chatRef && chatRef.key || root.pendingWriteChatKey)
      var sameChat = key === root.composerChatKey
      var kind = String(details && details.kind || root.pendingWriteKind)
      var request = details && details.request ? details.request : ({})
      // A batch reports its failures together when it ends.
      if ((kind === "forward" || kind === "delete" || kind === "star") && request.batch === true) return
      if (kind === "send-new" && root.contactDraftSending) {
        root.contactDraftSending = false
        root.contactDraftError = String(message || "The message could not be sent.")
        return
      }
      // A failed text stays as a bubble to retry; the composer keeps what
      // was typed since.
      var snapshot = key === root.pendingWriteChatKey && !(details && details.pending_kept)
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
    interval: 60000
    repeat: true
    running: root.opened && !root.demoMode
    onTriggered: root.clockNow = new Date()
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

      Item {
        id: keyboardHome
        width: 1; height: 1
        Keys.onPressed: function(event) {
          if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
              && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier))
            event.accepted = root.cycleRailFocus(event.key === Qt.Key_Backtab
              || (event.modifiers & Qt.ShiftModifier))
        }
      }

      Shortcut {
        sequence: "Ctrl+O"
        context: Qt.WindowShortcut
        onActivated: root.openFilePicker("document")
      }

      Shortcut {
        sequence: "Ctrl+Q"
        context: Qt.WindowShortcut
        onActivated: root.quitApp()
      }

      Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: root.selectingMessages && !forwardPicker.opened && !batchDeleteConfirm.opened
        onActivated: root.cancelSelection()
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

      Shortcut {
        sequence: "Ctrl+N"
        context: Qt.WindowShortcut
        onActivated: root.openNewChat()
      }

      Shortcut {
        sequence: "Ctrl+K"
        context: Qt.WindowShortcut
        onActivated: root.openQuickSwitcher()
      }

      Process {
        id: filePickerProcess
        objectName: "filePickerProcess"
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
        id: savePickerProcess
        objectName: "savePickerProcess"
        property var item: null
        property var originRef: AccountModel.chatRef("", "")
        command: []
        stdout: StdioCollector { id: savePickerOutput }
        onExited: function(exitCode) {
          var target = originRef
          var chosen = String(savePickerOutput.text || "").trim()
          originRef = AccountModel.chatRef("", "")
          if (exitCode !== 0 || chosen.charAt(0) !== "/" || !root.service) return
          root.service.saveMedia(target, item, chosen, "app")
        }
      }

      Process {
        id: exportPickerProcess
        objectName: "exportPickerProcess"
        property var originRef: AccountModel.chatRef("", "")
        command: []
        stdout: StdioCollector { id: exportPickerOutput }
        onExited: function(exitCode) {
          var target = originRef
          var chosen = String(exportPickerOutput.text || "").trim()
          originRef = AccountModel.chatRef("", "")
          if (exitCode !== 0 || chosen.charAt(0) !== "/" || !root.service) return
          root.service.exportChat(target, chosen, "app")
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
        objectName: "toast"
        width: copyToastLabel.implicitWidth + Style.space(30)
          + (toastAction.visible ? toastAction.width + Style.space(10) : 0)
        height: Style.space(42)
        radius: Style.cornerRadius
        color: root.background
        border.width: 1
        border.color: root.accent

        Text {
          textFormat: Text.PlainText
          id: copyToastLabel
          anchors.left: parent.left
          anchors.leftMargin: Style.space(15)
          anchors.verticalCenter: parent.verticalCenter
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

        // One thing to do next, such as opening the chat a forward went to.
        Rectangle {
          id: toastAction
          objectName: "toastAction"
          visible: root.toastActionLabel !== ""
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          width: toastActionText.implicitWidth + Style.space(22)
          height: Style.space(30)
          radius: Style.cornerRadius
          color: toastActionHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
            : Style.normalFillFor(root.foreground, root.accent)
          Text {
            textFormat: Text.PlainText
            id: toastActionText
            anchors.centerIn: parent
            text: root.toastActionLabel
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          HoverHandler { id: toastActionHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.runToastAction() }
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
        if (event.key === Qt.Key_Escape) {
          root.goBack()
          event.accepted = true
        } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                   && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)
                   && root.cycleRailFocus(event.key === Qt.Key_Backtab
                     || (event.modifiers & Qt.ShiftModifier))) {
          event.accepted = true
        } else if (!root.textEntryActive && root.pageConversation(event.key)) {
          event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
          messageSearchField.forceActiveFocus()
          messageSearchField.selectAll()
          event.accepted = true
        } else if (keyboardNavigation.wantsChatSearch(event.key, root.textEntryActive)) {
          root.focusChatSearch()
          event.accepted = true
        } else if (keyboardNavigation.wantsMessageReply(
                     event.key, event.modifiers, root.textEntryActive)) {
          event.accepted = root.replyToCursor()
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

      // ---------------------------------------------------------- settings

      SettingsView {
        id: settingsView
        z: 400
        visible: root.settingsOpen
        anchors.fill: parent
        app: root
        service: root.service
        updates: appUpdates
        demoMode: root.demoMode
        narrow: root.narrow
        foreground: root.foreground
        background: root.background
        accent: root.accent
        dim: root.dim
        dimmer: root.dimmer
        urgent: root.urgent
        fontFamily: root.fontFamily
        onCloseRequested: root.settingsOpen = false
      }

      // ------------------------------------------------------- chat sidebar

      Rectangle {
        id: sidebar
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        visible: root.narrow ? !root.narrowConversation : width > 0
        width: root.narrow ? parent.width : (root.sidebarCollapsed ? 0 : root.railWidth)
        opacity: root.narrow || !root.sidebarCollapsed ? 1 : 0
        clip: true
        color: Style.normalFillFor(root.foreground, root.accent)

        Behavior on width {
          enabled: root.railDragWidth < 0
          NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on opacity { NumberAnimation { duration: 110 } }

        Popup {
          id: chatContextMenu
          objectName: "chatContextMenu"
          width: Style.space(230)
          height: chatContextColumn.implicitHeight + Style.space(10)
          padding: Style.space(5)
          closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
          onClosed: root.contextChat = null
          background: Rectangle {
            radius: Style.cornerRadius
            color: root.background
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
          }
          contentItem: Column {
            id: chatContextColumn
            spacing: Style.space(2)
            Repeater {
              model: root.contextChatActions
              delegate: Rectangle {
                required property var modelData
                objectName: "chatContextAction-" + modelData.action
                width: parent.width
                height: Style.space(34)
                radius: Style.cornerRadius
                color: chatContextHover.hovered
                  ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
                Text {
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: modelData.destructive ? root.urgent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                HoverHandler { id: chatContextHover }
                TapHandler { onTapped: root.runChatContextAction(modelData.action) }
              }
            }
          }
        }

        Rectangle {
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          width: railResizeArea.containsMouse || railResizeArea.pressed ? 2 : 1
          color: railResizeArea.containsMouse || railResizeArea.pressed ? root.accent
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
        }

        MouseArea {
          id: railResizeArea
          objectName: "railResizeHandle"
          visible: !root.narrow && !root.sidebarCollapsed
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          width: Style.space(6)
          z: 10
          hoverEnabled: true
          cursorShape: Qt.SizeHorCursor
          preventStealing: true
          onPressed: root.railDragWidth = sidebar.width
          onPositionChanged: function(mouse) {
            if (!pressed) return
            var edge = mapToItem(sidebar, mouse.x, 0).x
            root.railDragWidth = Math.max(root.railMinWidth, Math.min(root.railMaxWidth, edge))
          }
          onReleased: {
            if (root.railDragWidth >= 0) root.setRailWidth(root.railDragWidth)
            root.railDragWidth = -1
          }
          onCanceled: root.railDragWidth = -1
          onDoubleClicked: root.resetRailWidth()
          PanelToolTip {
            visible: railResizeArea.containsMouse && !railResizeArea.pressed
            text: "Drag to resize · double-click for the automatic width"
          }
        }

        Column {
          id: railColumn
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(10)

          Item {
            id: railHeader
            width: parent.width
            height: Style.space(30)
            Text {
              textFormat: Text.PlainText
              id: railTitle
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Chats"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.weight: Font.Bold
            }
            LinkStatus {
              objectName: "railHeaderLinkStatus"
              anchors.left: railTitle.right
              anchors.leftMargin: Style.space(12)
              width: Math.max(0, Math.min(Style.space(140),
                railHeaderActions.x - railTitle.width - Style.space(22)))
              anchors.verticalCenter: parent.verticalCenter
              compact: true
              state: railSyncStatus.state
              pauseReason: railSyncStatus.pauseReason
              foreground: root.foreground
              accent: root.accent
              dim: root.dim
              urgent: root.urgent
              fontFamily: root.fontFamily
            }
            Row {
              id: railHeaderActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              PanelActionButton {
                objectName: "railNewChatButton"
                iconText: "󱐒"
                tooltipText: "New chat · Ctrl+N"
                foreground: newChatDialog.opened ? root.accent : root.dim
                hoverColor: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                size: Style.space(28)
                onClicked: root.openNewChat()
              }
              PanelActionButton {
                objectName: "railSettingsButton"
                iconText: "󰢻"
                tooltipText: "Settings"
                foreground: root.settingsOpen ? root.accent : root.dim
                hoverColor: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                size: Style.space(28)
                onClicked: root.settingsOpen = !root.settingsOpen
              }
              PanelActionButton {
                objectName: "railCollapseButton"
                visible: !root.narrow
                iconText: "󰁭"
                tooltipText: "Hide chat list · Ctrl+B"
                foreground: root.dim
                hoverColor: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                size: Style.space(28)
                onClicked: root.toggleSidebar()
              }
            }
          }

          TextField {
            id: chatSearchField
            width: parent.width
            height: root.compactRail ? Style.space(30) : Style.space(34)
            placeholderText: "Search chats"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            leftPadding: Style.space(30)
            rightPadding: Style.space(30)
            onActiveFocusChanged: if (activeFocus) keyboardNavigation.enterChatSearch()
            Keys.onTabPressed: root.cycleRailFocus(false)
            Keys.onBacktabPressed: root.cycleRailFocus(true)
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
            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "󰍉"
              color: chatSearchField.activeFocus ? root.accent : root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            // "/" jumps here from the list; the key says so while the field is idle.
            Rectangle {
              objectName: "chatSearchKeyHint"
              visible: !chatSearchField.activeFocus && chatSearchField.text === ""
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: Style.space(16)
              radius: 4
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "/"
                color: root.dimmer
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // The views scroll sideways when the rail is too narrow for them;
          // the wheel scrolls them too, and the bar shows only while moving.
          // Comfortable: a segmented control that fills the rail. Compact:
          // plain words, the current one underlined.
          Flickable {
            id: railViews
            objectName: "railViews"
            readonly property real segmentHeight: root.compactRail ? Style.space(24) : Style.space(32)
            readonly property real inset: root.compactRail ? 0 : Style.space(3)
            // Each view is as wide as its words; what the rail has left is
            // shared among them (whole pixels, so the sum never overflows).
            readonly property real segmentPadding: root.compactRail ? 0 : Style.space(16)
            readonly property var naturalWidths: root.chatViews.map(function(view) {
              return Math.ceil(railViewMetrics.advanceWidth(view.label)
                + (view.count > 0 ? Style.space(4) + railViewMetrics.advanceWidth(String(view.count)) : 0))
                + segmentPadding
            })
            readonly property real extraWidth: root.compactRail || naturalWidths.length === 0 ? 0
              : Math.max(0, Math.floor((width - inset * 2 - railViewsRow.spacing * (naturalWidths.length - 1)
                - naturalWidths.reduce(function(sum, value) { return sum + value }, 0)) / naturalWidths.length))
            readonly property bool overflowing: contentWidth > width + 1
            width: parent.width
            height: segmentHeight + (railViewsBar.visible ? Style.space(6) : 0)
            contentWidth: railViewsTrack.width
            contentHeight: segmentHeight
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: overflowing
            clip: true
            ScrollBar.horizontal: ScrollBar {
              id: railViewsBar
              objectName: "railViewsBar"
              policy: railViews.overflowing ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }
            WheelHandler {
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                railViews.contentX = Math.max(0, Math.min(
                  railViews.contentWidth - railViews.width, railViews.contentX - delta / 2))
              }
            }
            FontMetrics {
              id: railViewMetrics
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              id: railViewsTrack
              width: railViewsRow.width + railViews.inset * 2
              height: railViews.segmentHeight
              radius: Style.cornerRadius
              color: root.compactRail ? "transparent" : Style.normalFillFor(root.foreground, root.accent)
              Row {
                id: railViewsRow
                x: railViews.inset
                y: railViews.inset
                spacing: root.compactRail ? Style.space(12) : Style.space(2)
                Repeater {
                  id: railViewRepeater
                  // Counts and selected views change live; a numeric model
                  // keeps focused chips alive when their labels update.
                  model: root.chatViews.length
                  onCountChanged: if (root.keyboardContext === "chat-views")
                    Qt.callLater(function() {
                      root.focusChatView(Math.min(keyboardNavigation.chatViewIndex, railViewRepeater.count - 1))
                    })
                  delegate: Rectangle {
                    id: viewChip
                    readonly property var modelData: root.chatViews[index] || ({ id: "", label: "", count: 0 })
                    objectName: "railView-" + modelData.id
                    readonly property bool active: root.chatView === modelData.id
                    required property int index
                    activeFocusOnTab: true
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData.label
                    Accessible.onPressAction: root.focusChatView(index)
                    border.width: activeFocus ? 1 : 0
                    border.color: root.accent
                    onActiveFocusChanged: if (activeFocus) {
                      keyboardNavigation.enterChatViews(root.chatViews.length, index)
                      root.chatView = modelData.id
                      root.chatCursorIndex = 0
                      var left = x + railViews.inset
                      var right = left + width
                      if (left < railViews.contentX) railViews.contentX = left
                      else if (right > railViews.contentX + railViews.width)
                        railViews.contentX = right - railViews.width
                    }
                    Keys.onPressed: function(event) {
                      if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                          && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                        event.accepted = root.cycleRailFocus(event.key === Qt.Key_Backtab
                          || (event.modifiers & Qt.ShiftModifier))
                      } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                           || event.key === Qt.Key_Space) && event.modifiers === Qt.NoModifier) {
                        root.chatView = modelData.id
                        event.accepted = true
                      }
                    }
                    width: Number(railViews.naturalWidths[index] || 0) + railViews.extraWidth
                    height: railViews.segmentHeight - railViews.inset * 2
                    radius: Style.cornerRadius - 2
                    color: root.compactRail || !active
                      ? (!root.compactRail && viewHover.hovered
                        ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
                      : Style.selectedFillFor(root.foreground, root.accent)
                    Row {
                      id: viewLabel
                      anchors.centerIn: parent
                      spacing: Style.space(4)
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.label
                        color: viewChip.active ? root.foreground
                          : viewHover.hovered ? root.foreground : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        textFormat: Text.PlainText
                        visible: modelData.count > 0
                        text: String(modelData.count)
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                    Rectangle {
                      objectName: "railViewUnderline"
                      visible: root.compactRail && viewChip.active
                      anchors.left: viewLabel.left
                      anchors.right: viewLabel.right
                      anchors.top: viewLabel.bottom
                      anchors.topMargin: 1
                      height: 2
                      radius: 1
                      color: root.accent
                    }
                    HoverHandler { id: viewHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                      onTapped: {
                        root.focusChatView(viewChip.active && viewChip.modelData.id !== "all"
                          ? 0 : viewChip.index)
                      }
                    }
                  }
                }
              }
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
            onScopeSelected: function(scope) {
              root.accountScope = scope
              root.chatCursorIndex = 0
            }
            onLinkRequested: function(name) {
              if (root.service) root.service.accountOperations.linkAccount(name)
            }
          }

          LinkStatus {
            id: railSyncStatus
            objectName: "railSyncStatus"
            visible: state !== "connected"
            height: visible ? Style.space(66) : 0
            readonly property var account: root.accountEntries.find(function(entry) {
              return String(entry.account || "") === String(root.accountScope || root.selectedAccount || (root.service ? root.service.defaultAccountName : ""))
            }) || ({})
            width: parent.width
            state: root.demoMode ? root.demoConnectionState
              : String((root.service && root.service.closed && account.connection_state !== "relink-required" && account.connection_state !== "unlinked" ? "closed" : account.connection_state) || (root.selectedStatusReady
                ? (root.service.closed ? "closed" : root.service.offlineMode ? "offline" : root.service.syncActive ? "connecting" : "stopped") : "unknown"))
            pauseReason: !account.account || String(account.account) === String(root.service ? root.service.statusAccount : "")
              ? root.syncPauseReason : ""
            foreground: root.foreground
            accent: root.accent
            dim: root.dim
            urgent: root.urgent
            fontFamily: root.fontFamily
            demo: root.demoMode
            busy: !!root.service && !!root.service.accountOperations && root.service.accountOperations.linkBusy
            actionEnabled: !!root.service && !root.service.controlWriting
            onActionRequested: {
              var name = String(account.account || root.selectedAccount)
              if (expired) {
                if (account.main === true) root.service.accountOperations.linkMainAccount(name)
                else root.service.accountOperations.linkAccount(name)
              } else if (root.service.closed) root.service.launchApp()
              else root.service.setOnline(true, name)
            }
          }

          AccountReadiness {
            id: appAccountReadiness
            width: parent.width
            accounts: root.demoMode || !root.service ? [] : root.service.accounts.filter(function(entry) {
              return String(entry.account || "") !== String(railSyncStatus.account.account || "")
            })
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
          }

          ListView {
            id: chatList
            width: parent.width
            // What the rail leaves below the controls above it, summed from
            // the sidebar rather than read from the column, which has no size
            // yet when the list is built. Not clamped at 0: a list that starts
            // at height 0 defers its rows to the next frame, one that starts
            // negative lays them out as soon as the height arrives.
            height: (sidebar.height - railColumn.anchors.margins * 2
              - railHeader.height - chatSearchField.height - railViews.height
              - appAccountSwitcher.height - railColumn.spacing * 4
              - (appAccountReadiness.visible ? appAccountReadiness.height + railColumn.spacing : 0)
              - (railSyncStatus.visible ? railSyncStatus.height + railColumn.spacing : 0))
            clip: true
            spacing: root.compactRail ? 0 : Style.space(2)
            model: root.visibleChats
            currentIndex: root.chatCursorIndex
            boundsBehavior: Flickable.StopAtBounds

            // Linked, and the first sync still filling the mirror.
            Column {
              objectName: "railFirstSync"
              visible: !root.demoMode && chatList.count === 0 && root.chatView === "all"
                && String(chatSearchField.text || "").trim() === "" && !root.onboarding
                && !!root.service && root.service.anyAuthenticated === true
              width: chatList.width
              y: Style.space(28)
              spacing: Style.space(6)
              Text {
                textFormat: Text.PlainText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Syncing your chats…"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width - Style.space(24)
                x: Style.space(12)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "The first sync can take a few minutes. Chats appear here as they arrive; keep the phone online."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              textFormat: Text.PlainText
              objectName: "railViewEmpty"
              visible: chatList.count === 0 && root.chatView !== "all"
              width: chatList.width
              y: Style.space(24)
              horizontalAlignment: Text.AlignHCenter
              text: root.chatView === "unread" ? "No unread chats"
                : root.chatView === "groups" ? "No groups" : "No archived chats"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // Comfortable rows carry two lines: name and time, then the
            // preview with its tick, kind and badge. Compact rows put name,
            // preview and badge (or time) on one line.
            delegate: Item {
              id: chatRow
              objectName: "chatRow"
              required property var modelData
              required property int index
              width: chatList.width
              readonly property string sectionLabel: root.railSectionLabel(index)
              readonly property real sectionHeight: sectionLabel === "" ? 0
                : (root.compactRail ? Style.space(20) : Style.space(24))
              height: sectionHeight + rowBody.height
              readonly property bool selected: String(modelData.account || "") === root.selectedAccount
                && (root.demoMode
                  ? String(modelData.jid) === root.demoSelectedJid
                  : !!root.service && String(modelData.jid) === root.service.selectedChatJid)
              readonly property bool keyboardSelected: root.keyboardContext === "chats"
                && index === root.chatCursorIndex
              readonly property int unreadCount: Number(modelData.unread || 0)
              // Muted and archived chats count quietly: grey badge, grey time.
              readonly property bool loud: Number(modelData.notification_unread || 0) > 0
              readonly property bool hovered: chatRowHover.hovered
              readonly property string draft: root.draftFor(modelData)
              // Someone typing replaces the preview, as on the phone.
              readonly property bool typing: draft === "" && root.chatTyping(modelData)
              readonly property var preview: AccountModel.previewParts(modelData)
              readonly property real contentX: chatAvatar.x + chatAvatar.width
                + (root.compactRail ? Style.space(8) : Style.space(12))
              readonly property real contentRight: rowBody.width - Style.space(10)

              Text {
                textFormat: Text.PlainText
                objectName: "chatSection"
                visible: chatRow.sectionLabel !== ""
                x: Style.space(12)
                y: chatRow.sectionHeight - height - Style.space(3)
                text: chatRow.sectionLabel.toUpperCase()
                color: root.dimmer
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption - 1
                font.letterSpacing: 1.4
              }

              Rectangle {
                id: rowBody
                objectName: "chatRowBody"
                y: chatRow.sectionHeight
                width: parent.width
                height: root.compactRail ? Style.space(34) : Style.space(58)
                radius: root.compactRail ? Style.cornerRadius : Style.cornerRadius + 2
                color: chatRow.keyboardSelected || chatRow.selected
                  ? Style.selectedFillFor(root.foreground, root.accent)
                  : (chatMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
                border.width: chatRow.keyboardSelected ? 1 : 0
                border.color: root.accent

                HoverHandler { id: chatRowHover }

                // Which account the chat belongs to, when several are linked.
                Rectangle {
                  objectName: "chatAccountStripe"
                  readonly property int mark: root.accountMark(chatRow.modelData)
                  visible: mark >= 0
                  x: Style.space(3)
                  width: 3
                  height: Math.round(parent.height * 0.52)
                  radius: 1.5
                  anchors.verticalCenter: parent.verticalCenter
                  color: Tint.accountColor(mark, root.accent)
                }

                ChatAvatar {
                  showPhoto: root.showAvatars
                  id: chatAvatar
                  x: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.compactRail ? Style.space(22) : Style.space(38)
                  height: width
                  chat: chatRow.modelData
                  selected: chatRow.selected
                  foreground: root.foreground
                  background: root.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                }

                // Comfortable: the two lines sit centred as one block.
                readonly property real lineTop: (height - chatName.implicitHeight
                  - Style.space(3) - chatPreviewLine.height) / 2

                Text {
                  textFormat: Text.PlainText
                  id: chatName
                  objectName: "chatName"
                  x: chatRow.contentX
                  y: root.compactRail ? (rowBody.height - implicitHeight) / 2 : rowBody.lineTop
                  width: root.compactRail
                    ? Math.min(implicitWidth, (chatRow.contentRight - chatRow.contentX) * 0.45)
                    : Math.max(0, chatTime.x - Style.space(8) - x)
                  text: String(chatRow.modelData.name || "WhatsApp chat")
                  color: root.foreground
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: root.compactRail ? Style.font.bodySmall : Style.font.body
                  font.weight: chatRow.unreadCount > 0 ? Font.Bold : Font.Medium
                }

                // Comfortable: beside the name. Compact: in the trailing slot
                // when there is no badge to show.
                Text {
                  textFormat: Text.PlainText
                  id: chatTime
                  objectName: "chatTime"
                  visible: text !== "" && (!root.compactRail
                    || (chatRow.unreadCount === 0 && !chatRow.hovered))
                  x: chatRow.contentRight - implicitWidth
                  y: root.compactRail ? (rowBody.height - implicitHeight) / 2
                    : rowBody.lineTop + (chatName.implicitHeight - implicitHeight) / 2
                  text: TimeFormat.listStamp(chatRow.modelData.timestamp, root.demoMode
                    ? root.demoNow : root.clockNow, root.listClock,
                    Qt.locale().dateFormat(Locale.ShortFormat))
                  color: chatRow.loud ? root.accent : root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Item {
                  id: chatPreviewLine
                  objectName: "chatPreviewLine"
                  x: root.compactRail ? chatName.x + chatName.width + Style.space(8) : chatRow.contentX
                  y: root.compactRail ? (rowBody.height - height) / 2
                    : rowBody.lineTop + chatName.implicitHeight + Style.space(3)
                  width: Math.max(0, chatTrailing.x - Style.space(6) - x)
                  height: chatPreviewText.implicitHeight

                  // Your last message shows its tick instead of "You ·", as
                  // on the phone, when wacli recorded its delivery state.
                  Text {
                    textFormat: Text.PlainText
                    id: chatPreviewTicks
                    objectName: "chatPreviewTicks"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    readonly property string status: chatRow.draft === "" && chatRow.modelData.last_from_me
                      && !chatRow.typing ? String(chatRow.modelData.last_status || "") : ""
                    text: root.tickGlyph(status)
                    color: status === "read" || status === "played" ? root.accent
                      : status === "error" ? Commons.Color.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    textFormat: Text.PlainText
                    id: chatPreviewKind
                    objectName: "chatPreviewKind"
                    anchors.left: chatPreviewTicks.visible ? chatPreviewTicks.right : parent.left
                    anchors.leftMargin: chatPreviewTicks.visible ? Style.space(4) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property string kind: chatRow.draft === "" && !chatRow.typing
                      ? chatRow.preview.kind : ""
                    visible: text !== ""
                    width: visible ? implicitWidth : 0
                    text: root.previewKindGlyph(kind)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    textFormat: Text.PlainText
                    id: chatPreviewText
                    objectName: "chatPreview"
                    anchors.left: chatPreviewKind.visible ? chatPreviewKind.right
                      : chatPreviewTicks.visible ? chatPreviewTicks.right : parent.left
                    anchors.leftMargin: chatPreviewKind.visible || chatPreviewTicks.visible ? Style.space(4) : 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: chatRow.draft !== "" ? "Draft: " + chatRow.draft
                      : chatRow.typing ? "typing…"
                      : AccountModel.previewPrefix(chatRow.modelData, root.multiAccount)
                        + (chatRow.modelData.last_from_me && !chatPreviewTicks.visible ? "You · " : "")
                        + AccountModel.previewSender(chatRow.modelData)
                        + (FormatModel.plain(chatRow.preview.text) || "No local messages yet")
                    color: chatRow.draft !== "" ? Tint.draftColor(root.accent)
                      : chatRow.typing ? root.accent
                      : chatRow.unreadCount > 0 ? root.foreground : root.dim
                    opacity: chatRow.unreadCount > 0 && chatRow.draft === "" && !chatRow.typing ? 0.86 : 1
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: root.compactRail ? Style.font.caption : Style.font.bodySmall
                  }
                }

                // Flags, then one fixed slot: the unread badge, or on hover
                // the read/unread toggle (compact: the time when neither).
                Row {
                  id: chatTrailing
                  z: 2
                  spacing: Style.space(5)
                  x: chatRow.contentRight - width
                  y: root.compactRail ? (rowBody.height - height) / 2
                    : chatPreviewLine.y + (chatPreviewLine.height - height) / 2
                  height: Style.space(22)

                  Row {
                    id: chatFlags
                    objectName: "chatFlags"
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)
                    Text {
                      textFormat: Text.PlainText
                      objectName: "chatMutedIcon"
                      visible: chatRow.modelData.muted === true
                      text: "󰪑"
                      color: root.dimmer
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      textFormat: Text.PlainText
                      objectName: "chatPinnedIcon"
                      visible: chatRow.modelData.pinned === true
                      text: "󰐃"
                      // Accent: the owner found the dim pin too easy to miss.
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // An unread message here @mentions you.
                  Rectangle {
                    objectName: "chatMentionBadge"
                    visible: chatRow.modelData.mentioned === true && chatRow.unreadCount > 0
                    anchors.verticalCenter: parent.verticalCenter
                    height: root.compactRail ? Style.space(16) : Style.space(18)
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

                  Item {
                    id: chatSlot
                    anchors.verticalCenter: parent.verticalCenter
                    // Never narrower than the toggle, so hovering does not
                    // move the preview.
                    width: Math.max(Style.space(22), chatRow.unreadCount > 0 ? unreadBadge.width
                      : root.compactRail ? chatTime.implicitWidth : 0)
                    height: Style.space(22)

                    PanelActionButton {
                      objectName: "chatReadToggle"
                      anchors.centerIn: parent
                      visible: chatRow.hovered
                      iconText: root.chatIsUnread(chatRow.modelData) ? "󰄭" : "󱥂"
                      tooltipText: root.chatIsUnread(chatRow.modelData) ? "Mark as read" : "Mark as unread"
                      foreground: root.dim
                      hoverColor: root.foreground
                      fontFamily: root.fontFamily
                      fontSize: Style.font.bodySmall
                      size: Style.space(22)
                      onClicked: root.toggleChatRead(chatRow.modelData)
                    }

                    Rectangle {
                      id: unreadBadge
                      objectName: "chatUnreadBadge"
                      anchors.centerIn: parent
                      visible: chatRow.unreadCount > 0 && !chatRow.hovered
                      height: root.compactRail ? Style.space(16) : Style.space(18)
                      width: Math.max(height, unreadText.implicitWidth + Style.space(9))
                      radius: height / 2
                      color: chatRow.loud ? root.accent
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                      Text {
                        textFormat: Text.PlainText
                        id: unreadText
                        anchors.centerIn: parent
                        text: chatRow.unreadCount > 99 ? "99+" : String(chatRow.unreadCount)
                        color: chatRow.loud ? root.background : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption - 1
                        font.weight: Font.Bold
                      }
                    }
                  }
                }

                MouseArea {
                  id: chatMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                      var point = rowBody.mapToItem(sidebar, mouse.x, mouse.y)
                      root.openChatContextMenu(chatRow.modelData, point.x, point.y)
                      return
                    }
                    root.chatCursorIndex = chatRow.index
                    root.selectChat(chatRow.modelData)
                  }
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
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: root.narrow ? parent.left : sidebar.right
        anchors.right: root.chatDetailsBeside ? chatDetailsPanel.left
          : (root.mediaBrowserBeside ? mediaBrowser.left : parent.right)

        Item {
          id: conversationHeader
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(54)

          // Picking messages: how many, and what can be done with them.
          Rectangle {
            id: selectionBar
            objectName: "selectionBar"
            visible: root.selectingMessages
            anchors.fill: parent
            z: 20
            color: Qt.tint(root.background, Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12))
            MouseArea { anchors.fill: parent }
            PanelActionButton {
              id: selectionCancel
              objectName: "selectionCancel"
              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅖"
              tooltipText: "Cancel · Esc"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              size: Style.space(32)
              onClicked: root.cancelSelection()
            }
            Text {
              textFormat: Text.PlainText
              objectName: "selectionCount"
              anchors.left: selectionCancel.right
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: root.selectedMessageIds.length === 0 ? "Pick messages"
                : root.selectedMessageIds.length + " selected"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.Bold
            }
            Row {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              Repeater {
                model: [{ id: "delete", label: "Delete" },
                  { id: "star", label: root.selectionAllStarred ? "Unstar" : "Star" },
                  { id: "copy", label: "Copy" }, { id: "forward", label: "Forward" }]
                delegate: Rectangle {
                  id: selectionAction
                  required property var modelData
                  objectName: "selectionAction-" + modelData.id
                  readonly property bool primary: modelData.id === "forward"
                  readonly property bool enabledHere: root.selectedMessageIds.length > 0
                  visible: modelData.id !== "star" || root.starAvailable
                  width: selectionActionLabel.implicitWidth + Style.space(24)
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  opacity: enabledHere ? 1 : 0.45
                  color: primary ? (selectionActionHover.hovered ? Qt.lighter(root.accent, 1.1) : root.accent)
                    : (selectionActionHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
                  Text {
                    textFormat: Text.PlainText
                    id: selectionActionLabel
                    anchors.centerIn: parent
                    text: selectionAction.modelData.label
                    color: selectionAction.primary ? root.background
                      : selectionAction.modelData.id === "delete" ? root.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.weight: selectionAction.primary ? Font.Bold : Font.Normal
                  }
                  HoverHandler { id: selectionActionHover; cursorShape: Qt.PointingHandCursor }
                  TapHandler {
                    enabled: selectionAction.enabledHere
                    onTapped: selectionAction.primary ? root.openForwardDialog()
                      : selectionAction.modelData.id === "delete" ? root.requestDeleteSelection()
                      : selectionAction.modelData.id === "star" ? root.starSelection(!root.selectionAllStarred)
                      : root.copySelection()
                  }
                }
              }
            }
          }

          Row {
            id: conversationTitleRow
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: headerActions.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            PanelActionButton {
              visible: root.narrow
              width: visible ? implicitWidth : 0
              iconText: "󰁍"
              tooltipText: "Back to chats"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              size: Style.space(30)
              onClicked: {
                root.narrowConversation = false
                root.narrowSearchOpen = false
              }
            }

            PanelActionButton {
              objectName: "showChatListButton"
              visible: !root.narrow && root.sidebarCollapsed
              width: visible ? implicitWidth : 0
              iconText: "󰵵"
              tooltipText: "Show chat list · Ctrl+B"
              foreground: root.dim
              hoverColor: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              size: Style.space(30)
              onClicked: root.toggleSidebar()
            }

            ChatAvatar {
              showPhoto: root.showAvatars
              objectName: "conversationAvatar"
              HoverHandler { id: headerAvatarHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.toggleChatDetails() }
              PanelToolTip { visible: headerAvatarHover.hovered; text: "Chat details" }
              width: Style.space(34)
              height: width
              chat: root.headerChat
              selected: true
              foreground: root.foreground
              background: root.background
              accent: root.accent
              fontFamily: root.fontFamily
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, conversationTitleRow.width
                - Style.space(84))
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                objectName: "conversationTitle"
                width: parent.width
                text: root.displayGroupName
                color: root.foreground
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                HoverHandler { id: headerTitleHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.toggleChatDetails() }
                PanelToolTip { visible: headerTitleHover.hovered; text: "Chat details" }
              }
              Text {
                textFormat: Text.PlainText
                objectName: "conversationSubtitle"
                // Typing, online or last seen when wacli follows presence;
                // otherwise the account the chat belongs to, when more than
                // one is linked.
                text: root.presenceLine.text !== "" ? root.presenceLine.text
                  : root.multiAccount && root.selectedChat
                  ? AccountModel.labelOf(root.selectedChat) : ""
                visible: text !== ""
                color: root.presenceLine.live ? root.accent
                  : root.presenceLine.text === "" && root.accountMark(root.selectedChat) >= 0
                  ? Tint.accountColor(root.accountMark(root.selectedChat), root.accent) : root.dim
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

            PanelActionButton {
              objectName: "mediaBrowserButton"
              iconText: "󰽌"
              tooltipText: "Media, links and docs"
              foreground: root.mediaBrowserOpen ? root.accent : root.dim
              hoverColor: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.icon
              size: Style.space(32)
              onClicked: root.mediaBrowserOpen ? (root.mediaBrowserOpen = false)
                : root.openMediaBrowser("media")
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

            PanelActionButton {
              visible: root.narrow && !root.narrowSearchOpen
              width: visible ? implicitWidth : 0
              iconText: "󰍉"
              tooltipText: "Search messages · Ctrl+F"
              foreground: root.dim
              hoverColor: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.icon
              size: Style.space(32)
              onClicked: {
                root.narrowSearchOpen = true
                Qt.callLater(function() { messageSearchField.forceActiveFocus() })
              }
            }

            PanelActionButton {
              objectName: "chatMenuButton"
              iconText: "󰇙"
              tooltipText: "Chat actions"
              foreground: root.dim
              hoverColor: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.icon
              size: Style.space(32)
              onClicked: chatMenu.open()

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
                      { label: root.chatDetailsOpen ? "Hide chat details" : "Chat details", action: "details", destructive: false },
                      { label: root.selectedChat && root.selectedChat.pinned ? "Unpin chat" : "Pin chat", action: root.selectedChat && root.selectedChat.pinned ? "unpin" : "pin", destructive: false },
                      { label: root.selectedChat && root.selectedChat.muted ? "Unmute notifications" : "Mute notifications", action: root.selectedChat && root.selectedChat.muted ? "unmute" : "mute", destructive: false },
                      { label: root.selectedChat && root.selectedChat.archived ? "Unarchive chat" : "Archive chat", action: root.selectedChat && root.selectedChat.archived ? "unarchive" : "archive", destructive: false },
                      { label: "Mark as unread", action: "unread", destructive: false },
                      { label: "Remove local chat", action: "remove-local", destructive: true }
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
                        color: modelData.destructive ? root.urgent : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      HoverHandler { id: chatActionHover }
                      TapHandler {
                        onTapped: {
                          chatMenu.close()
                          if (modelData.action === "details") {
                            root.toggleChatDetails()
                          } else if (modelData.action === "remove-local") {
                            root.requestRemoveLocalChat()
                          } else if (modelData.action === "unread") {
                            root.toggleChatRead(root.selectedChat, false)
                          } else if (!root.demoMode && root.service) {
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
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          }
        }

        Column {
          objectName: "conversationEmptyState"
          visible: root.visibleMessages.length === 0 && !(root.service && root.service.loadingMessages)
          anchors.centerIn: messageList
          spacing: Style.space(10)
          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.displayGroupName === ""
            text: "󰖣"
            color: root.dimmer
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge * 2
          }
          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.displayGroupName === "" ? "Choose a chat" : "No local messages in this chat"
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        ListView {
          id: messageList
          objectName: "messageList"
          anchors.top: conversationHeader.bottom
          anchors.bottom: composerBar.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(14)
          clip: true
          // Gaps come from each row: tight inside one person's run, wider between.
          spacing: 0
          model: root.visibleMessages
          currentIndex: root.cursorIndex
          verticalLayoutDirection: ListView.BottomToTop
          boundsBehavior: Flickable.StopAtBounds
          // A draggable scroll bar that shows while scrolling or hovered.
          ScrollBar.vertical: ScrollBar {
            objectName: "messageScrollBar"
            policy: ScrollBar.AsNeeded
            minimumSize: 0.06
          }
          // When the oldest loaded message is on screen, fetch the page
          // before it. Checked after scrolling and after the list changes.
          onContentYChanged: {
            olderCheck.restart()
            root.showFloatingDay()
          }
          onCountChanged: olderCheck.restart()
          Timer {
            id: olderCheck
            interval: 150
            repeat: false
            onTriggered: root.maybeLoadOlder()
          }

          // Drawn bottom-to-top, the footer sits above the oldest message.
          footer: Item {
            width: messageList.width
            height: olderHint.text !== "" ? Style.space(36) : 0
            Text {
              textFormat: Text.PlainText
              id: olderHint
              objectName: "olderMessagesHint"
              anchors.centerIn: parent
              text: root.demoMode || !root.service || root.visibleMessages.length === 0 ? ""
                : root.service.loadingOlder ? "Loading older messages…"
                : !root.service.hasOlderMessages ? "Start of this computer's copy of the chat" : ""
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          delegate: Item {
            id: messageRow
            required property var modelData
            required property int index
            width: messageList.width
            z: renderedMessage.raised ? 3 : 0
            readonly property bool startsDay: TimeFormat.startsDay(root.visibleMessages, index)
            readonly property bool startsUnread: index === root.unreadDividerIndex
            // Newest first: the message above on screen is the next index.
            readonly property bool joinsAbove: !startsDay && !startsUnread
              && AccountModel.sameRun(root.visibleMessages[index + 1], modelData)
            readonly property bool joinsBelow: index > 0
              && !TimeFormat.startsDay(root.visibleMessages, index - 1)
              && index - 1 !== root.unreadDividerIndex
              && AccountModel.sameRun(modelData, root.visibleMessages[index - 1])
            height: groupGap.height + dayHeader.height + unreadDivider.height + renderedMessage.height

            Item {
              id: groupGap
              width: parent.width
              height: messageRow.joinsAbove ? Style.space(2) : Style.space(8)
            }

            // Newest-first list drawn bottom-to-top: the header sits above the
            // oldest message of its day.
            Item {
              id: dayHeader
              objectName: "dayHeader"
              anchors.top: groupGap.bottom
              visible: messageRow.startsDay
              width: parent.width
              height: visible ? Style.space(40) : 0
              Rectangle {
                anchors.centerIn: parent
                width: dayLabel.implicitWidth + Style.space(20)
                height: Style.space(24)
                radius: height / 2
                color: Style.normalFillFor(root.foreground, root.accent)
                Text {
                  textFormat: Text.PlainText
                  id: dayLabel
                  anchors.centerIn: parent
                  text: TimeFormat.dayLabel(messageRow.modelData.timestamp)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Item {
              id: unreadDivider
              objectName: "unreadDivider"
              anchors.top: dayHeader.bottom
              visible: messageRow.startsUnread
              width: parent.width
              height: visible ? Style.space(34) : 0
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
              }
              Rectangle {
                anchors.centerIn: parent
                width: unreadLabel.implicitWidth + Style.space(20)
                height: Style.space(22)
                radius: height / 2
                color: root.background
                border.width: 1
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                Text {
                  textFormat: Text.PlainText
                  id: unreadLabel
                  anchors.centerIn: parent
                  text: root.unreadMarker.count === 1 ? "1 unread message"
                    : root.unreadMarker.count + " unread messages"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            MessageBubble {
              id: renderedMessage
              anchors.top: unreadDivider.bottom
              timeFormat: root.timeFormat
              // Picking messages: the bubbles make room for the check circles.
              x: root.selectingMessages ? Style.space(40) : 0
              width: parent.width - x
              message: modelData
              foreground: root.foreground
              background: root.background
              accent: root.accent
              dim: root.dim
              dimmer: root.dimmer
              fontFamily: root.fontFamily
              groupChat: root.displayKind === "group"
              senderAvatars: true
              senderAvatarPath: root.showAvatars ? root.senderAvatarPath(modelData) : ""
              joinsAbove: messageRow.joinsAbove
              joinsBelow: messageRow.joinsBelow
              selected: root.keyboardContext === "messages"
                && index === root.cursorIndex
              narrow: root.narrow
              surfaceActive: root.timelineMediaActive
              activePlaybackId: root.activeTimelinePlaybackId
              sharedAudio: timelineAudio
              audioRate: root.service ? root.service.audioRate : 1
              onAudioRateRequested: function(rate) { if (root.service) root.service.audioRate = rate }
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
              onPendingSendRequested: function(action) {
                if (root.service) root.service.resolvePendingSend(modelData.id, action)
              }
              onForwardRequested: root.startForward(modelData)
              starEnabled: root.starAvailable
              onStarRequested: function(starred) { root.starOne(modelData, starred) }
              onCopyRequested: function(text) { root.copyText(text) }
              onSaveRequested: root.saveMediaAs(modelData)
              onPollVoteRequested: function(options) {
                if (!root.demoMode && root.service)
                  root.service.votePoll(root.currentChatRef(), modelData, options, "app")
              }
              onContactChatRequested: function(card) { root.openContactChat(card, modelData) }
              onOptionRequested: function(optionIndex) {
                if (!root.demoMode && root.service)
                  root.service.selectOption(
                    root.currentChatRef(), modelData, optionIndex, "app")
              }
            }

            // While picking, the whole row toggles its message.
            Item {
              objectName: "messageSelectArea"
              visible: root.selectingMessages
              z: 5
              anchors.top: renderedMessage.top
              anchors.bottom: renderedMessage.bottom
              width: parent.width
              readonly property bool pickable: modelData.pending !== true && modelData.revoked !== true
              readonly property bool picked: root.isMessageSelected(modelData)
              Rectangle {
                anchors.fill: parent
                color: parent.picked ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10) : "transparent"
              }
              Rectangle {
                objectName: "messageSelectCircle"
                visible: parent.pickable
                x: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(20)
                height: width
                radius: width / 2
                color: parent.picked ? root.accent : "transparent"
                border.width: parent.picked ? 0 : 2
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: parent.parent.picked
                  text: "󰄬"
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                }
              }
              MouseArea {
                anchors.fill: parent
                enabled: parent.pickable
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleMessageSelection(messageRow.modelData)
              }
            }
          }
        }

        // Back to the newest message, with how many arrived while reading above.
        property string awayNewestId: ""
        // Bottom-to-top list: the newest item ends at y = 0, so the view is at
        // the latest message when its bottom edge reaches 0.
        // Measured on the newest message itself: contentY and originY move
        // with the list's height estimates (a machine without the theme
        // fonts showed the jump button at the bottom and not at the top).
        readonly property bool awayFromLatest: root.newestMessageOffset(messageList, messageList.contentY)
          > Style.space(48)
        onAwayFromLatestChanged: awayNewestId = awayFromLatest && root.visibleMessages.length > 0
          ? String(root.visibleMessages[0].id || "") : ""
        readonly property int newWhileAway: {
          if (awayNewestId === "") return 0
          for (var i = 0; i < root.visibleMessages.length; i++)
            if (String(root.visibleMessages[i].id || "") === awayNewestId) return i
          return 0
        }
        Timer { id: floatingDayHold; interval: 1400; repeat: false }
        Rectangle {
          id: floatingDay
          objectName: "floatingDay"
          z: 68
          readonly property bool shown: root.floatingDayLabel !== "" && jumpToLatest.parent.awayFromLatest
            && (messageList.moving || floatingDayHold.running)
          opacity: shown ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 180 } }
          anchors.top: messageList.top
          anchors.topMargin: Style.space(6)
          anchors.horizontalCenter: messageList.horizontalCenter
          width: floatingDayText.implicitWidth + Style.space(22)
          height: Style.space(26)
          radius: height / 2
          color: Qt.tint(root.background, Qt.rgba(root.foreground.r, root.foreground.g,
            root.foreground.b, 0.12))
          Text {
            textFormat: Text.PlainText
            id: floatingDayText
            anchors.centerIn: parent
            text: root.floatingDayLabel
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        // The shell button is transparent; over the conversation the text
        // would show through it, so it gets a solid backing.
        Rectangle {
          objectName: "jumpToLatestBacking"
          z: 69
          visible: jumpToLatest.visible
          anchors.fill: jumpToLatest
          radius: Style.cornerRadius
          color: root.background
        }
        PanelActionButton {
          id: jumpToLatest
          objectName: "jumpToLatest"
          z: 70
          visible: parent.awayFromLatest
          anchors.right: messageList.right
          anchors.bottom: messageList.bottom
          anchors.rightMargin: Style.space(8)
          anchors.bottomMargin: Style.space(8)
          size: Style.space(36)
          iconText: "󰁅"
          tooltipText: parent.newWhileAway > 0
            ? "Jump to latest · " + parent.newWhileAway + " new" : "Jump to latest"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.icon
          bordered: true
          onClicked: root.scrollToNewest()
          Rectangle {
            visible: jumpToLatest.parent.newWhileAway > 0
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: -Style.space(4)
            width: Math.max(Style.space(18), newCount.implicitWidth + Style.space(8))
            height: Style.space(18)
            radius: height / 2
            color: root.accent
            Text {
              textFormat: Text.PlainText
              id: newCount
              anchors.centerIn: parent
              text: jumpToLatest.parent.newWhileAway > 99 ? "99+" : String(jumpToLatest.parent.newWhileAway)
              color: root.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
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

        FontMetrics {
          id: composerMetrics
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Rectangle {
          id: composerBar
          objectName: "composerBar"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          property real replyContextHeight: root.replyTarget || root.editTarget ? Style.space(48) : 0
          property real attachmentContextHeight: root.pendingAttachments.length > 0 ? Style.space(68) : 0
          property real signatureContextHeight: root.signatureActive ? Style.space(26) : 0
          property real contextHeight: replyContextHeight + attachmentContextHeight + signatureContextHeight
          readonly property int singleLineHeight: Math.max(1, Math.ceil(composerMetrics.lineSpacing))
          readonly property int maxLines: root.composerMaxLines
          readonly property int visibleLines: Math.max(1, Math.min(composer.lineCount, maxLines))
          // One control height for the attach button, a one-line field and the
          // send button; every control sits on the same bottom edge, so a
          // single line reads as centred and a taller draft grows upward.
          readonly property real controlSize: Style.space(40)
          readonly property real edge: Style.space(12)
          readonly property real fieldPadding: Math.max(Style.space(6),
            Math.floor((controlSize - singleLineHeight) / 2))
          readonly property real fieldHeight: Math.max(controlSize,
            Math.ceil(visibleLines * singleLineHeight) + fieldPadding * 2)
          height: Math.min(fieldHeight + edge * 2 + contextHeight, parent.height - Style.space(120))
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
              PanelToolTip { visible: cancelContextHover.hovered; text: root.editTarget ? "Cancel edit · Esc" : "Cancel reply · Esc" }
              TapHandler { onTapped: root.cancelComposerContext() }
            }
          }

          // The signature this message will carry, with a one-click skip.
          Item {
            id: composerSignatureStrip
            objectName: "composerSignature"
            visible: composerBar.signatureContextHeight > 0
            anchors.top: parent.top
            anchors.topMargin: composerBar.replyContextHeight + composerBar.attachmentContextHeight
              + Style.space(6)
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            height: composerBar.signatureContextHeight - Style.space(6)
            Text {
              textFormat: Text.PlainText
              id: composerSignatureLabel
              objectName: "composerSignatureLabel"
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.signatureSkipped ? "󰷼  This message goes without your signature"
                : "󰷼  Signed as " + root.composerSignature.name
                  + (root.composerSignature.position === "bottom" ? " · at the end" : " · at the top")
              color: root.signatureSkipped ? root.dimmer : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              textFormat: Text.PlainText
              objectName: "composerSignatureToggle"
              anchors.left: composerSignatureLabel.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.signatureSkipped ? "Sign it" : "Skip once"
              color: signatureToggleHover.hovered ? root.foreground : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              HoverHandler { id: signatureToggleHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.signatureSkipped = !root.signatureSkipped }
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
                  HoverHandler { id: removeAttachmentHover }
                  PanelToolTip { visible: removeAttachmentHover.hovered; text: "Remove attachment" }
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

          PanelActionButton {
            id: pasteButton
            objectName: "composerAttachButton"
            visible: !root.voiceForCurrentChat
            anchors.left: parent.left
            anchors.leftMargin: composerBar.edge
            anchors.bottom: parent.bottom
            anchors.bottomMargin: composerBar.edge
            size: composerBar.controlSize
            iconText: "󰏢"
            tooltipText: attachmentTray.opened ? "" : "Attach · Ctrl+O files · Ctrl+Shift+O photos and videos"
            foreground: attachmentTray.opened ? root.accent : root.dim
            hoverColor: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.icon
            onClicked: attachmentTray.opened ? attachmentTray.close() : attachmentTray.open()

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
                    { icon: "󰎆", label: "Audio", action: "audio" },
                    { icon: "󰐕", label: "Poll", action: "poll" },
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
                        else root.pasteDraft()
                      }
                    }
                  }
                }
              }
            }
          }

          PanelActionButton {
            id: emojiButton
            objectName: "composerEmojiButton"
            visible: !root.voiceForCurrentChat
            anchors.left: pasteButton.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: composerBar.edge
            size: composerBar.controlSize
            iconText: "󰇵"
            tooltipText: emojiPicker.opened ? "" : "Emoji"
            foreground: emojiPicker.opened ? root.accent : root.dim
            hoverColor: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.icon
            onClicked: emojiPicker.opened ? emojiPicker.close() : emojiPicker.open()

            EmojiPicker {
              id: emojiPicker
              x: 0
              y: -height - Style.space(8)
              target: composer
              foreground: root.foreground
              surface: root.background
              accent: root.accent
              muted: root.dim
              fontFamily: root.fontFamily
              stickersEnabled: !root.demoMode && !!root.service
              stickers: root.service && root.service.stickers ? root.service.stickers : []
              stickersLoading: !!root.service && root.service.stickersLoading === true
              onStickersOpened: if (root.service) root.service.refreshStickers(true)
              onStickerPicked: function(path) { root.sendPickedSticker(path) }
            }
          }

          Rectangle {
            id: composerSurface
            objectName: "composerSurface"
            visible: !root.voiceForCurrentChat
            anchors.left: emojiButton.right
            anchors.leftMargin: Style.space(6)
            anchors.right: sendButton.left
            anchors.rightMargin: Style.space(8)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: composerBar.edge
            height: composerBar.fieldHeight
            radius: Style.cornerRadius
            color: root.background
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

            MouseArea {
              anchors.fill: parent
              onClicked: composer.forceActiveFocus()
            }

            // Formatting: a bar over any selection, and the right-click menu.
            FormatBar {
              id: formatBar
              editor: composer
              anchorItem: composerSurface
              enabledHere: !root.voiceForCurrentChat
              foreground: root.foreground
              surface: root.background
              accent: root.accent
              muted: root.dim
              fontFamily: root.fontFamily
              onChosen: function(kind) { root.applyFormat(kind) }
            }

            FormatMenu {
              id: formatMenu
              editActions: true
              hasSelection: composer.selectedText !== ""
              foreground: root.foreground
              surface: root.background
              accent: root.accent
              muted: root.dim
              fontFamily: root.fontFamily
              onChosen: function(kind) { root.composerMenuAction(kind) }
            }

            Flickable {
              id: composerFlickable
              objectName: "composerFlickable"
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(6)
              anchors.topMargin: composerBar.fieldPadding
              anchors.bottomMargin: composerBar.fieldPadding
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
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onActiveFocusChanged: if (activeFocus) keyboardNavigation.enterComposer()
                onTextChanged: {
                  root.updateMentionCompletion()
                  if (text === "") composerFlickable.contentY = 0
                  // An emptied box (sent or deleted) stops "typing…" at once.
                  if (text === "") root.composerEmptied()
                }
                onCursorPositionChanged: root.updateMentionCompletion()
                onCursorRectangleChanged: composerFlickable.ensureVisible(cursorRectangle)
                TapHandler {
                  acceptedButtons: Qt.RightButton
                  onTapped: function(eventPoint) {
                    root.openComposerMenu(eventPoint.position.x, eventPoint.position.y)
                  }
                }
                Keys.priority: Keys.BeforeItem
                // Ctrl+B bolds a selection here; without one it still hides the chat list.
                Keys.onShortcutOverride: function(event) {
                  if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_B
                      && !(event.modifiers & Qt.ShiftModifier) && composer.selectedText !== "")
                    event.accepted = true
                }
                Keys.onPressed: function(event) {
                  root.noteComposerKey(event)
                  // Page Up/Down scroll the conversation even while typing.
                  if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                    event.accepted = root.pageConversation(event.key)
                    return
                  }
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
                  } else if ((event.modifiers & Qt.ControlModifier)
                             && !(event.modifiers & Qt.ShiftModifier)
                             && event.key === Qt.Key_B && composer.selectedText !== "") {
                    root.applyFormat("bold")
                    event.accepted = true
                  } else if ((event.modifiers & Qt.ControlModifier)
                             && !(event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_I) {
                    root.applyFormat("italic")
                    event.accepted = true
                  } else if ((event.modifiers & Qt.ControlModifier)
                             && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_X) {
                    root.applyFormat("strike")
                    event.accepted = true
                  } else if ((event.modifiers & Qt.ControlModifier)
                             && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_M) {
                    root.applyFormat("mono")
                    event.accepted = true
                  } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                             && (root.enterSends
                               ? !(event.modifiers & Qt.ShiftModifier)
                               : !!(event.modifiers & Qt.ControlModifier))) {
                    root.sendDraft()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up && composer.text === "") {
                    root.focusMessages()
                    event.accepted = true
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              objectName: "composerPlaceholder"
              visible: composer.text === ""
              // Same inset as the editor, so typing does not shift the line.
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.top: parent.top
              anchors.topMargin: composerBar.fieldPadding
              elide: Text.ElideRight
              width: parent.width - Style.space(24)
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
            objectName: "composerSendButton"
            visible: !root.voiceForCurrentChat
            anchors.right: parent.right
            anchors.rightMargin: composerBar.edge
            anchors.bottom: parent.bottom
            anchors.bottomMargin: composerBar.edge
            width: composerBar.controlSize
            height: width
            radius: width / 2
            color: composer.text.trim() !== "" || root.pendingAttachments.length > 0
              || root.currentChatKey() !== "" ? root.accent : "transparent"
            // Only a file or sticker waits for the running action; text queues.
            opacity: root.service && root.service.writing && !root.sendQueued
              && (root.pendingAttachments.length > 0 || root.pendingStickerPath !== "") ? 0.45 : 1
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.sendQueued ? "󰔟"
                : (composer.text.trim() !== "" || root.pendingAttachments.length > 0 ? "󰒊" : "󰍬")
              color: root.currentChatKey() !== "" ? root.background : root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }
            MouseArea {
              id: sendButtonMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (composer.text.trim() !== "" || root.pendingAttachments.length > 0)
                  root.sendDraft()
                else root.toggleVoiceRecording()
              }
            }
            PanelToolTip {
              visible: sendButtonMouse.containsMouse
              text: root.sendQueued ? "Sends as soon as the current WhatsApp action finishes"
                : composer.text.trim() !== "" || root.pendingAttachments.length > 0
                ? (root.enterSends ? "Send · Enter" : "Send · Ctrl+Enter")
                : "Record a voice note · Ctrl+Shift+V"
            }
          }

          VoiceComposer {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: composerBar.edge
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

      // Deleting several picked messages at once.
      Popup {
        id: batchDeleteConfirm
        objectName: "batchDeleteConfirm"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(Style.space(400), window.width - Style.space(28))
        height: batchDeleteColumn.implicitHeight + Style.space(28)
        padding: Style.space(14)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
          radius: Style.cornerRadius
          color: root.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
        }
        contentItem: Column {
          id: batchDeleteColumn
          spacing: Style.space(12)
          Text {
            textFormat: Text.PlainText
            objectName: "batchDeleteTitle"
            text: root.selectedMessageIds.length === 1 ? "Delete 1 message?"
              : "Delete " + root.selectedMessageIds.length + " messages?"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.selectionAllMine
              ? "For you, they disappear from this device's history. For everyone, WhatsApp may refuse older ones; the rest are gone for everyone."
              : "Some are not yours, so they can only be deleted for you."
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
                { id: "cancel", label: "Cancel" },
                { id: "me", label: "Delete for me" },
                { id: "all", label: "Delete for everyone" }
              ]
              delegate: Rectangle {
                id: batchDeleteButton
                required property var modelData
                objectName: "batchDelete-" + modelData.id
                visible: modelData.id !== "all" || root.selectionAllMine
                width: batchDeleteLabel.implicitWidth + Style.space(24)
                height: Style.space(34)
                radius: Style.cornerRadius
                color: modelData.id === "cancel" ? Style.normalFillFor(root.foreground, root.accent) : root.urgent
                Text {
                  textFormat: Text.PlainText
                  id: batchDeleteLabel
                  anchors.centerIn: parent
                  text: batchDeleteButton.modelData.label
                  color: batchDeleteButton.modelData.id === "cancel" ? root.foreground : root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                  onTapped: {
                    if (batchDeleteButton.modelData.id === "cancel") batchDeleteConfirm.close()
                    else root.deleteSelection(batchDeleteButton.modelData.id === "me")
                  }
                }
              }
            }
          }
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
        id: removeLocalConfirm
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(Style.space(380), window.width - Style.space(28))
        height: removeLocalColumn.implicitHeight + Style.space(28)
        padding: Style.space(14)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: root.removeLocalTargetRef = AccountModel.chatRef("", "")
        background: Rectangle {
          radius: Style.cornerRadius
          color: root.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
        }
        contentItem: Column {
          id: removeLocalColumn
          spacing: Style.space(12)
          Text {
            textFormat: Text.PlainText
            text: "Remove local chat?"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "This only deletes the local chat history from this device, not from Meta's WhatsApp servers. The chat will disappear from OmaWhatsApp and will only reappear if a new message is received."
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
                { label: "Remove", confirm: true }
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
                    if (modelData.confirm) root.confirmRemoveLocalChat()
                    else root.dismissRemoveLocalChat()
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

      // Forward: what goes, to which chats (several at once), and an
      // optional note that follows the messages in each chat.
      Popup {
        id: forwardPicker
        objectName: "forwardPicker"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(Style.space(520), window.width - Style.space(28))
        height: Math.min(Style.space(660), window.height - Style.space(36))
        padding: 0
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: {
          root.forwardItems = []
          root.forwardChosen = []
        }
        readonly property var matches: root.forwardCandidates.filter(function(chat) {
          var needle = String(forwardSearch.text || "").trim().toLowerCase()
          return needle === "" || String(chat.name || "").toLowerCase().indexOf(needle) >= 0
            || (root.forwardDigits !== "" && String(chat.jid || "").indexOf(root.forwardDigits) === 0)
        })
        // A typed number that is not one of the chats above gets its own row.
        readonly property bool numberRow: root.forwardDigits !== ""
          && !matches.some(function(chat) { return String(chat.jid || "").indexOf(root.forwardDigits + "@") === 0 })
        background: Rectangle {
          radius: Style.cornerRadius + 4
          color: root.background
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
        }
        Shortcut {
          sequences: ["Ctrl+Return", "Ctrl+Enter"]
          context: Qt.WindowShortcut
          enabled: forwardPicker.opened
          onActivated: root.sendForward()
        }
        contentItem: Item {
          Column {
            id: forwardHeaderColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(18)
            spacing: Style.space(12)

            Item {
              width: parent.width
              height: Style.space(30)
              Text {
                textFormat: Text.PlainText
                objectName: "forwardTitle"
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.forwardItems.length === 1 ? "Forward message"
                  : "Forward " + root.forwardItems.length + " messages"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.weight: Font.Bold
              }
              PanelActionButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅖"
                tooltipText: "Close · Esc"
                foreground: root.dim
                hoverColor: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                size: Style.space(30)
                onClicked: root.dismissForward()
              }
            }

            // What goes: kind and words of each message, up to three.
            Rectangle {
              objectName: "forwardPreview"
              width: parent.width
              height: forwardPreviewColumn.implicitHeight + Style.space(16)
              radius: Style.cornerRadius + 2
              color: Style.normalFillFor(root.foreground, root.accent)
              Column {
                id: forwardPreviewColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(10)
                spacing: Style.space(4)
                Repeater {
                  model: root.forwardItems.slice(0, 3)
                  delegate: Text {
                    required property var modelData
                    textFormat: Text.PlainText
                    width: forwardPreviewColumn.width
                    readonly property var parts: AccountModel.previewParts({
                      preview: String(modelData.text || modelData.filename || ""),
                      last_media_type: String(modelData.media_type || "") })
                    text: (AccountModel.previewKindGlyph(parts.kind) !== ""
                      ? AccountModel.previewKindGlyph(parts.kind) + "  " : "")
                      + (FormatModel.plain(parts.text) || "Message")
                    elide: Text.ElideRight
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  visible: root.forwardItems.length > 3
                  text: "+" + (root.forwardItems.length - 3) + " more"
                  color: root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            // Where it goes: each chosen chat as a chip, then the search.
            Rectangle {
              width: parent.width
              height: Math.max(Style.space(40), forwardChipFlow.implicitHeight + Style.space(12))
              radius: Style.cornerRadius + 2
              color: Style.normalFillFor(root.foreground, root.accent)
              border.width: 1
              border.color: forwardSearch.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              Flow {
                id: forwardChipFlow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(6)
                Repeater {
                  model: root.forwardChosen
                  delegate: Rectangle {
                    id: forwardChip
                    required property var modelData
                    objectName: "forwardChip"
                    width: forwardChipLabel.implicitWidth + Style.space(28)
                    height: Style.space(24)
                    radius: height / 2
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                    Text {
                      textFormat: Text.PlainText
                      id: forwardChipLabel
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      text: String(forwardChip.modelData.name || "WhatsApp chat")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: "×"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    TapHandler { onTapped: root.toggleForwardTarget(forwardChip.modelData) }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                  }
                }
                TextField {
                  id: forwardSearch
                  objectName: "forwardSearch"
                  width: Math.max(Style.space(140), forwardChipFlow.width
                    - (root.forwardChosen.length > 0 ? Style.space(4) : 0))
                  height: Style.space(28)
                  placeholderText: root.forwardChosen.length > 0 ? "Add another chat or number"
                    : "Search chats or type a number"
                  foreground: root.foreground
                  accent: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  leftPadding: Style.space(4)
                  background: null
                  Keys.onPressed: function(event) {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && !(event.modifiers & Qt.ControlModifier)) {
                      // Enter checks or adds a typed number, else picks the first match.
                      if (forwardPicker.numberRow) {
                        root.useForwardNumber()
                      } else if (forwardPicker.matches.length > 0) {
                        root.toggleForwardTarget(forwardPicker.matches[0])
                        forwardSearch.text = ""
                      }
                      event.accepted = true
                    } else if (event.key === Qt.Key_Backspace && forwardSearch.text === ""
                               && root.forwardChosen.length > 0) {
                      root.toggleForwardTarget(root.forwardChosen[root.forwardChosen.length - 1])
                      event.accepted = true
                    }
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "RECENT"
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption - 1
              font.letterSpacing: 1.4
            }
          }

          Rectangle {
            id: forwardNumberRow
            objectName: "forwardNumberRow"
            visible: forwardPicker.numberRow
            anchors.top: forwardHeaderColumn.bottom
            anchors.topMargin: Style.space(4)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            height: visible ? Style.space(48) : 0
            radius: Style.cornerRadius
            readonly property bool actionable: root.forwardNumberState === "registered"
              || root.forwardNumberState === "idle" || root.forwardNumberState === "error"
            color: forwardNumberHover.hovered && actionable
              ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
            Rectangle {
              id: forwardNumberIcon
              x: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
              height: width
              radius: width / 2
              color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰏲"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
            Text {
              textFormat: Text.PlainText
              objectName: "forwardNumberLabel"
              anchors.left: forwardNumberIcon.right
              anchors.leftMargin: Style.space(12)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              readonly property string number: "+" + root.forwardDigits
              text: ({
                idle: "Check " + number + " on WhatsApp",
                checking: "Checking " + number + " with WhatsApp…",
                registered: "Add " + number + " · on WhatsApp",
                absent: number + " is not on WhatsApp",
                error: String(root.forwardNumberCheck && root.forwardNumberCheck.error || "Could not check") + " · try again"
              })[root.forwardNumberState] || ""
              elide: Text.ElideRight
              color: root.forwardNumberState === "absent" ? root.dim
                : root.forwardNumberState === "registered" ? root.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            HoverHandler { id: forwardNumberHover; cursorShape: forwardNumberRow.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: forwardNumberRow.actionable; onTapped: root.useForwardNumber() }
          }

          ListView {
            id: forwardList
            objectName: "forwardList"
            anchors.top: forwardNumberRow.visible ? forwardNumberRow.bottom : forwardHeaderColumn.bottom
            anchors.topMargin: Style.space(4)
            anchors.bottom: forwardFooter.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            clip: true
            spacing: Style.space(2)
            model: forwardPicker.matches
            delegate: Rectangle {
              id: forwardRow
              required property var modelData
              objectName: "forwardRow"
              readonly property bool chosen: root.isForwardChosen(modelData)
              width: forwardList.width
              height: Style.space(48)
              radius: Style.cornerRadius
              color: chosen ? Style.selectedFillFor(root.foreground, root.accent)
                : forwardRowHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
              ChatAvatar {
                id: forwardAvatar
                x: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(34)
                height: width
                showPhoto: root.showAvatars
                chat: forwardRow.modelData
                foreground: root.foreground
                background: root.background
                accent: root.accent
                fontFamily: root.fontFamily
              }
              Text {
                textFormat: Text.PlainText
                anchors.left: forwardAvatar.right
                anchors.leftMargin: Style.space(12)
                anchors.right: forwardCheck.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: String(forwardRow.modelData.name || "WhatsApp chat")
                color: root.foreground
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Rectangle {
                id: forwardCheck
                objectName: "forwardCheck"
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(20)
                height: width
                radius: 5
                color: forwardRow.chosen ? root.accent : "transparent"
                border.width: forwardRow.chosen ? 0 : 2
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: forwardRow.chosen
                  text: "󰄬"
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                }
              }
              HoverHandler { id: forwardRowHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.toggleForwardTarget(forwardRow.modelData) }
            }
            Text {
              textFormat: Text.PlainText
              visible: forwardList.count === 0 && !forwardPicker.numberRow
              anchors.centerIn: parent
              text: "No chat matches"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: forwardFooter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(18)
            spacing: Style.space(10)
            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            }
            TextField {
              id: forwardNote
              objectName: "forwardNote"
              width: parent.width
              height: Style.space(38)
              placeholderText: "Add a message (optional)"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              background: Rectangle {
                radius: Style.cornerRadius + 1
                color: Style.normalFillFor(root.foreground, root.accent)
                border.width: 1
                border.color: forwardNote.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              }
            }
            Item {
              width: parent.width
              height: Style.space(40)
              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Ctrl+Enter sends"
                color: root.dimmer
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Rectangle {
                id: forwardSend
                objectName: "forwardSend"
                readonly property bool ready: root.forwardChosen.length > 0 && root.forwardItems.length > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: forwardSendLabel.implicitWidth + Style.space(36)
                height: Style.space(40)
                radius: Style.cornerRadius + 2
                opacity: ready ? 1 : 0.45
                color: forwardSendHover.hovered && ready ? Qt.lighter(root.accent, 1.1) : root.accent
                Text {
                  textFormat: Text.PlainText
                  id: forwardSendLabel
                  anchors.centerIn: parent
                  text: root.forwardChosen.length > 1 ? "Send to " + root.forwardChosen.length + " chats"
                    : root.forwardChosen.length === 1 ? "Send to " + String(root.forwardChosen[0].name || "chat")
                    : "Choose a chat"
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.Bold
                }
                HoverHandler { id: forwardSendHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: forwardSend.ready; onTapped: root.sendForward() }
              }
            }
          }
        }
      }

      // A shared contact with no chat yet (L220): the person's draft chat,
      // over the chat the card came from, with a way back to it.
      Rectangle {
        id: contactDraftPanel
        objectName: "contactDraftPanel"
        visible: !!root.contactDraft
        anchors.fill: conversation
        z: 40
        color: root.background
        MouseArea { anchors.fill: parent }
        Keys.onEscapePressed: root.closeContactDraft()

        Item {
          id: contactDraftHeader
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(64)

          Rectangle {
            id: contactDraftBack
            objectName: "contactDraftBack"
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(contactDraftBackLabel.implicitWidth + Style.space(30), Style.space(200))
            height: Style.space(30)
            radius: Style.cornerRadius
            color: contactDraftBackHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
              : Style.normalFillFor(root.foreground, root.accent)
            Text {
              textFormat: Text.PlainText
              id: contactDraftBackLabel
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "󰅁 " + (root.contactDraft ? root.contactDraft.originName : "")
              elide: Text.ElideRight
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            HoverHandler { id: contactDraftBackHover; cursorShape: Qt.PointingHandCursor }
            PanelToolTip { visible: contactDraftBackHover.hovered; text: "Back · Esc" }
            TapHandler { onTapped: root.closeContactDraft() }
          }
          ChatAvatar {
            id: contactDraftAvatar
            anchors.left: contactDraftBack.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(38)
            height: width
            showPhoto: false
            chat: root.contactDraft ? ({ name: root.contactDraft.name, kind: "dm",
              jid: root.contactDraft.digits }) : ({})
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
          }
          Column {
            anchors.left: contactDraftAvatar.right
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              objectName: "contactDraftName"
              width: parent.width
              text: root.contactDraft ? root.contactDraft.name : ""
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.Bold
            }
            Text {
              textFormat: Text.PlainText
              objectName: "contactDraftStatus"
              width: parent.width
              text: !root.contactDraft ? "" : root.contactDraft.phone + " · " + ({
                known: "in your contacts", registered: "on WhatsApp", checking: "checking with WhatsApp…",
                absent: "not on WhatsApp", idle: "not checked yet",
                error: "could not check" })[root.contactDraftState]
              elide: Text.ElideRight
              color: root.contactDraftState === "absent" || root.contactDraftState === "error" ? root.urgent
                : root.contactDraftState === "known" || root.contactDraftState === "registered" ? root.accent
                : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          }
        }

        Column {
          anchors.centerIn: parent
          width: Math.min(Style.space(440), parent.width - Style.space(48))
          spacing: Style.space(16)
          Rectangle {
            width: parent.width
            height: contactDraftCardColumn.implicitHeight + Style.space(32)
            radius: Style.cornerRadius + 4
            color: Style.normalFillFor(root.foreground, root.accent)
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            Column {
              id: contactDraftCardColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(16)
              spacing: Style.space(12)
              Text {
                textFormat: Text.PlainText
                objectName: "contactDraftExplainer"
                width: parent.width
                wrapMode: Text.Wrap
                readonly property string first: root.contactDraft
                  ? root.contactDraft.name.split(/\s+/)[0] : ""
                text: !root.contactDraft ? ""
                  : root.contactDraftState === "absent"
                    ? root.contactDraft.name + " is not on WhatsApp, so there is no chat to start."
                    : (root.contactDraft.sharedBy !== "" ? root.contactDraft.sharedBy + " shared this contact. "
                      : "") + "There is no chat with " + first + " yet: it starts with your first message."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                lineHeight: 1.3
              }
              Row {
                spacing: Style.space(8)
                Repeater {
                  model: [{ id: "copy", label: "Copy number" }, { id: "card", label: "Show the card" },
                    { id: "retry", label: "Check again" }]
                  delegate: Rectangle {
                    id: contactDraftAction
                    required property var modelData
                    objectName: "contactDraftAction-" + modelData.id
                    visible: modelData.id !== "retry" || root.contactDraftState === "error"
                    width: contactDraftActionLabel.implicitWidth + Style.space(24)
                    height: Style.space(32)
                    radius: Style.cornerRadius
                    color: contactDraftActionHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
                      : Style.selectedFillFor(root.foreground, root.accent)
                    Text {
                      textFormat: Text.PlainText
                      id: contactDraftActionLabel
                      anchors.centerIn: parent
                      text: contactDraftAction.modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    HoverHandler { id: contactDraftActionHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                      onTapped: {
                        if (contactDraftAction.modelData.id === "copy") {
                          root.copyText(root.contactDraft.phone)
                          root.showToast("number copied")
                        } else if (contactDraftAction.modelData.id === "card") root.showContactCard()
                        else root.retryContactCheck()
                      }
                    }
                  }
                }
              }
            }
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Checking a number asks WhatsApp once; nothing is sent until you press Enter."
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(16)
          height: Style.space(44) + (contactDraftErrorText.visible ? contactDraftErrorText.height + Style.space(6) : 0)
          Text {
            textFormat: Text.PlainText
            id: contactDraftErrorText
            objectName: "contactDraftError"
            visible: root.contactDraftError !== ""
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            text: root.contactDraftError
            elide: Text.ElideRight
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: contactDraftField
            objectName: "contactDraftField"
            anchors.left: parent.left
            anchors.right: contactDraftSend.left
            anchors.rightMargin: Style.space(8)
            anchors.bottom: parent.bottom
            height: Style.space(44)
            enabled: root.contactDraftState !== "absent" && !root.contactDraftSending
            placeholderText: root.contactDraftState === "absent" ? "Not on WhatsApp"
              : root.contactDraft ? "Message " + root.contactDraft.name : "Message"
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            leftPadding: Style.space(14)
            background: Rectangle {
              radius: Style.cornerRadius + 4
              color: Style.normalFillFor(root.foreground, root.accent)
              border.width: 1
              border.color: contactDraftField.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
            }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.sendContactDraft()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.closeContactDraft()
                event.accepted = true
              }
            }
          }
          Rectangle {
            id: contactDraftSend
            objectName: "contactDraftSend"
            readonly property bool ready: root.contactDraftJid !== "" && !root.contactDraftSending
              && String(contactDraftField.text || "").trim() !== ""
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Style.space(44)
            height: width
            radius: width / 2
            color: root.accent
            opacity: ready ? 1 : 0.45
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.contactDraftSending ? "…" : "󰒊"
              color: root.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: contactDraftSend.ready; onTapped: root.sendContactDraft() }
          }
        }
      }

      // First run: nothing linked yet (or no wacli), over the whole window.
      OnboardingView {
        id: onboardingView
        objectName: "onboardingView"
        visible: root.onboarding && !root.settingsOpen
        anchors.fill: parent
        z: 80
        service: root.demoMode ? null : root.service
        demoMode: root.demoMode
        foreground: root.foreground
        background: root.background
        accent: root.accent
        dim: root.dim
        fontFamily: root.fontFamily
      }

      ChatDetailsPanel {
        id: chatDetailsPanel
        visible: root.chatDetailsOpen && !!root.selectedChat && !root.settingsOpen
        z: root.chatDetailsBeside ? 0 : 5
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: root.chatDetailsBeside ? Style.space(340)
          : (root.narrow ? parent.width : Math.max(Style.space(340), conversation.width))
        details: root.chatDetailsData
        chat: root.selectedChat
        loading: !root.demoMode && !!root.service && root.service.chatDetailsLoading
        showAvatars: root.showAvatars
        foreground: root.foreground
        surface: root.background
        accent: root.accent
        muted: root.dim
        fontFamily: root.fontFamily
        onCloseRequested: root.chatDetailsOpen = false
        onActionRequested: function(action) { root.runChatDetailsAction(action) }
        onFilterRequested: function(filter) { root.openMediaBrowser(filter) }
        onOpenChatRequested: function(jid, name, phone) { root.openFromChatDetails(jid, name, phone) }
        service: root.demoMode ? null : root.service
        urgent: root.urgent
        onCopyRequested: function(text) { root.copyText(text); root.showCopyToast() }
      }

      MediaBrowser {
        id: mediaBrowser
        visible: root.mediaBrowserOpen && !!root.selectedChat && !root.settingsOpen
        z: root.mediaBrowserBeside ? 0 : 5
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: root.mediaBrowserBeside ? Style.space(380)
          : (root.narrow ? parent.width : Math.max(Style.space(380), conversation.width))
        kind: root.mediaBrowserKind
        items: root.demoMode ? root.demoItems.filter(function(item) {
            return root.mediaBrowserKind === "media" ? ["image", "video", "gif"].indexOf(String(item.media_type || "")) >= 0
              : root.mediaBrowserKind === "links" ? String(item.text || "").indexOf("http") >= 0
              : item.media_type === "document" })
          : (root.service && root.service.browserItems ? root.service.browserItems : [])
        loading: !root.demoMode && !!root.service && root.service.browserLoading
        foreground: root.foreground
        surface: root.background
        accent: root.accent
        muted: root.dim
        fontFamily: root.fontFamily
        onCloseRequested: root.mediaBrowserOpen = false
        onKindRequested: function(kind) { root.openMediaBrowser(kind) }
        onOpenMediaRequested: function(item, gallery) { root.openBrowserMedia(item, gallery) }
        onOpenDocumentRequested: function(item) { root.openMediaExternal(String(item.local_path || "")) }
        onDownloadRequested: function(item) {
          if (!root.demoMode && root.service) root.service.downloadMedia(root.currentChatRef(), item, "app")
        }
      }

      QuickSwitcher {
        id: quickSwitcher
        chats: root.sourceChats
        showAvatars: root.showAvatars
        foreground: root.foreground
        surface: root.background
        accent: root.accent
        muted: root.dim
        fontFamily: root.fontFamily
        onChosen: function(chat) { root.selectChat(chat, "composer") }
      }

      NewChatDialog {
        id: newChatDialog
        service: root.demoMode ? null : root.service
        demoMode: root.demoMode
        demoPeople: root.demoPeople
        chats: root.sourceChats.filter(function(chat) {
          return root.demoMode || String(chat.account || "") === root.newChatAccount
        })
        showAvatars: root.showAvatars
        accountLabel: root.newChatAccountLabel
        foreground: root.foreground
        surface: root.background
        accent: root.accent
        muted: root.dim
        urgent: root.urgent
        fontFamily: root.fontFamily
        onOpenChatRequested: function(jid) { root.openNewChatResult(jid) }
        onChatStarted: function(jid) { root.followStartedChat(jid) }
        onGroupRequested: function(kind) { groupDialog.openFor(kind) }
      }

      GroupDialog {
        id: groupDialog
        service: root.demoMode ? null : root.service
        demoMode: root.demoMode
        demoPeople: root.demoPeople || []
        showAvatars: root.showAvatars
        foreground: root.foreground
        surface: root.background
        accent: root.accent
        muted: root.dim
        fontFamily: root.fontFamily
        onGroupReady: function(jid) { if (jid !== "") root.followStartedChat(jid) }
      }

      MediaViewer {
        id: mediaViewer
        objectName: "mediaViewer"
        timeFormat: root.timeFormat
        anchors.fill: parent
        // The media browser opens the viewer on its own gallery.
        items: root.viewerItems.length > 0 ? root.viewerItems : root.mediaGallery
        onOpenedChanged: if (!opened) root.viewerItems = []
        surfaceActive: root.opened
        playback: root.playbackCoordinator
        chatRef: root.currentChatRef()
        foreground: root.foreground
        background: root.background
        accent: root.accent
        dim: root.dim
        fontFamily: root.fontFamily
        onOpenExternalRequested: function(path) { root.openMediaExternal(path) }
        onSaveRequested: function(item) { root.saveMediaAs(item) }
      }
    }
  }
}
