import QtQuick
import Quickshell
import Quickshell.Io
import "SettingsPolicy.js" as SettingsPolicy
import "AccountModel.js" as AccountModel
import "PresenceModel.js" as PresenceModel
import "ComposerModel.js" as ComposerModel

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
  property bool notificationsSound: true
  property bool notifyPending: false
  property bool notifyAvailable: true
  property bool loadingChats: false
  property bool loadingMessages: false
  property bool loadingMembers: false
  property bool writing: false
  property bool controlWriting: false
  property bool settingsWriting: false
  property bool sendReadReceipts: false
  property bool readOnReply: true
  property bool enterSends: true
  property bool showAvatars: true
  // Off by default: a photo batch pauses sync, and what arrives meanwhile is lost.
  property bool autoRefreshAvatars: false
  property string railDensity: "comfortable"
  property int railWidth: 0
  property bool autoDownloadMedia: true
  property var about: ({})
  property bool aboutLoading: false
  // New chat: people this account's mirror knows, and WhatsApp's answer for a
  // typed number. A first message only goes to one of those two.
  property var newChatPeople: []
  property string newChatPeopleQuery: ""
  property bool newChatPeopleLoading: false
  property bool newChatPeoplePending: false
  // Presence: online, last seen and typing, from wacli builds that follow it.
  // Their sync keeps presence.json in each store; WhatsApp only sends it to a
  // device shown online, so the account is online while a surface looking at
  // it has focus (and the setting allows it), on a lease the sync ends itself.
  property bool showOnline: true
  // A clicked message popup opens the reply view by the bar (else the app).
  property bool notifyReply: true
  property bool presenceSupported: true
  property var presenceByStore: ({})
  property var presenceFocusOwners: []
  // Seconds, ticking while presence is shown, so typing fades on time.
  property int presenceNow: Math.floor(Date.now() / 1000)
  property string presenceAccount: ""
  readonly property bool presenceActive: showOnline && presenceSupported && ready && !closed
    && !offlineMode && presenceFocusOwners.length > 0
  function storeForAccount(account) {
    var name = String(account || "")
    for (var i = 0; i < accounts.length; i++)
      if (String(accounts[i].account || "") === name && String(accounts[i].store || "") !== "")
        return String(accounts[i].store)
    return storeDirectory
  }
  function presenceSnapshotFor(account) {
    return presenceByStore[storeForAccount(account)] || null
  }
  function applyPresence(store, text) {
    var next = Object.assign({}, presenceByStore)
    var snapshot = PresenceModel.parse(text)
    if (snapshot) next[String(store)] = snapshot
    else delete next[String(store)]
    presenceByStore = next
    presenceNow = Math.floor(Date.now() / 1000)
  }
  function reloadPresence(store) {
    for (var i = 0; i < presenceFiles.count; i++) {
      var file = presenceFiles.objectAt(i)
      if (file && file.store === String(store)) file.reload()
    }
  }
  function setPresenceFocus(owner, focused) {
    var name = String(owner || "")
    var owners = presenceFocusOwners.filter(function(item) { return item !== name })
    if (focused) owners.push(name)
    if (owners.length !== presenceFocusOwners.length || focused !== (presenceFocusOwners.indexOf(name) >= 0))
      presenceFocusOwners = owners
  }
  property var presenceQueue: []
  function queuePresence(action, account, jid) {
    if (!presenceSupported) return false
    var request = { action: String(action), account: String(account || ""), jid: String(jid || "") }
    if (request.action === "available") request.lease = 90
    presenceQueue = presenceQueue.filter(function(item) {
      return !(item.action === request.action && item.account === request.account && item.jid === request.jid)
    }).concat([request])
    runNextPresence()
    return true
  }
  function runNextPresence() {
    if (presenceProcess.running || presenceQueue.length === 0) return
    var next = presenceQueue[0]
    presenceQueue = presenceQueue.slice(1)
    presenceProcess.payload = JSON.stringify(next)
    presenceProcess.stdinEnabled = true
    presenceProcess.running = true
  }
  function followSelectedPresence() {
    if (!presenceActive || selectedChatKind !== "dm" || selectedChatJid === "") return
    queuePresence("subscribe", selectedChatAccount, selectedChatJid)
  }
  function syncPresenceAccount() {
    var wanted = presenceActive ? String(selectedChatAccount || statusAccount || "") : ""
    if (presenceAccount !== "" && presenceAccount !== wanted)
      queuePresence("unavailable", presenceAccount, "")
    if (wanted !== "" && wanted !== presenceAccount) {
      queuePresence("available", wanted, "")
      followSelectedPresence()
    }
    presenceAccount = wanted
  }
  onPresenceActiveChanged: syncPresenceAccount()
  onSelectedChatJidChanged: followSelectedPresence()
  Timer {
    id: presenceRenew
    interval: 60 * 1000
    repeat: true
    running: root.presenceActive
    onTriggered: if (root.presenceAccount !== "") root.queuePresence("available", root.presenceAccount, "")
  }
  Timer {
    // WhatsApp forgets subscriptions; the sync keeps them 10 minutes.
    id: presenceFollowRenew
    interval: 5 * 60 * 1000
    repeat: true
    running: root.presenceActive
    onTriggered: root.followSelectedPresence()
  }
  Timer {
    id: presenceClock
    interval: 2000
    repeat: true
    running: Object.keys(root.presenceByStore).length > 0
    onTriggered: root.presenceNow = Math.floor(Date.now() / 1000)
  }
  Instantiator {
    id: presenceFiles
    model: root.storeDirectories
    delegate: FileView {
      required property string modelData
      readonly property string store: modelData
      path: modelData + "/presence.json"
      printErrors: false
      onLoaded: root.applyPresence(modelData, text())
      onLoadFailed: root.applyPresence(modelData, "")
    }
  }
  Process {
    id: presenceProcess
    objectName: "presenceProcess"
    property string payload: ""
    command: [root.helper, "presence"]
    stdinEnabled: true
    stdout: StdioCollector { id: presenceOutput }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var answer = root.parseJson(presenceOutput.text)
      // An official wacli has no presence commands: stop asking this session.
      if (answer && answer.supported === false) {
        root.presenceQueue = []
        root.presenceAccount = ""
        root.presenceSupported = false
        return
      }
      root.runNextPresence()
    }
  }

  // Messages sent from here that the mirror has not stored yet. They show at
  // once as pending bubbles: the send itself takes a second or more.
  property var pendingSends: []
  // Voice note speed, shared by every audio bubble as on the phone.
  property real audioRate: 1
  // Last helper answers, so an identical refresh does not rebuild the lists.
  property string lastChatsRaw: ""
  property string lastMessagesRaw: ""
  property string lastMessagesKey: ""
  property int pendingSendSerial: 0
  // Older pages loaded by scrolling up. Kept apart so the refresh of the
  // newest page, on every mirror change, never throws them away.
  property var olderMessages: []
  property bool loadingOlder: false
  property bool hasOlderMessages: true
  readonly property var selectedMessages: {
    var key = selectedChatRef().key
    var stored = {}
    for (var i = 0; i < messages.length; i++) stored[String(messages[i].id || "")] = true
    // A search shows only its own results.
    var older = query !== "" ? [] : olderMessages.filter(function(item) {
      return !stored[String(item.id || "")]
    })
    var waiting = pendingSends.filter(function(item) {
      return item.key === key && !(item.message_id !== "" && stored[item.message_id])
    }).map(function(item) {
      return { id: item.local_id, text: item.text, sender: "You", sender_jid: "",
        timestamp: item.timestamp, from_me: true, done: false,
        media_type: String(item.media_type || ""),
        mime_type: item.media_type === "sticker" ? "image/webp" : "",
        local_path: String(item.local_path || ""), tags: [], quoted_id: item.reply_id,
        pending: true, send_state: item.state }
    })
    var page = older.length > 0 ? messages.concat(older) : messages
    // A star shows at once; WhatsApp can take seconds to accept it.
    var stars = starOverrides
    if (Object.keys(stars).length > 0) page = page.map(function(item) {
      var wanted = stars[key + "\n" + String(item && item.id || "")]
      return wanted === undefined || !!item.starred === wanted ? item : Object.assign({}, item, { starred: wanted })
    })
    return waiting.length > 0 ? waiting.reverse().concat(page) : page
  }
  // Stars asked for and not yet in the mirror, by chat key and message id;
  // each goes once the mirror shows the same.
  property var starOverrides: ({})
  onMessagesChanged: pruneStarOverrides()
  function pruneStarOverrides() {
    if (Object.keys(starOverrides).length === 0) return
    var key = selectedChatRef().key
    var next = Object.assign({}, starOverrides)
    var changed = false
    for (var i = 0; i < messages.length; i++) {
      var slot = key + "\n" + String(messages[i].id || "")
      if (next[slot] !== undefined && !!messages[i].starred === next[slot]) {
        delete next[slot]
        changed = true
      }
    }
    if (changed) starOverrides = next
  }
  function setStarOverride(chatRef, id, starred) {
    var ref = AccountModel.chatRef(chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
    var next = Object.assign({}, starOverrides)
    if (starred === null) delete next[ref.key + "\n" + String(id)]
    else next[ref.key + "\n" + String(id)] = starred === true
    starOverrides = next
  }
  function loadOlderMessages() {
    if (loadingOlder || !hasOlderMessages || query !== "" || selectedChatJid === "") return false
    var source = olderMessages.length > 0 ? olderMessages : messages
    if (source.length === 0) return false
    var oldest = source[source.length - 1]
    loadingOlder = true
    olderProcess.chatRef = selectedChatRef()
    olderProcess.payload = JSON.stringify({
      account: olderProcess.chatRef.account, jid: olderProcess.chatRef.jid,
      before: { ts: Number(oldest.timestamp || 0), id: String(oldest.id || "") }
    })
    olderProcess.stdinEnabled = true
    olderProcess.running = true
    return true
  }
  // Media browser: the chat's media, links or documents over its whole local
  // history. The conversation itself is never filtered.
  property var browserItems: []
  property string browserKind: ""
  property bool browserLoading: false
  function browseMedia(kind) {
    var name = String(kind || "")
    if (["media", "links", "docs"].indexOf(name) < 0 || selectedChatJid === "") return false
    if (mediaBrowserProcess.running) { browserPendingKind = name; return false }
    browserKind = name
    browserLoading = true
    mediaBrowserProcess.chatRef = selectedChatRef()
    mediaBrowserProcess.kind = name
    mediaBrowserProcess.payload = JSON.stringify({
      account: mediaBrowserProcess.chatRef.account, jid: mediaBrowserProcess.chatRef.jid, kind: name })
    mediaBrowserProcess.stdinEnabled = true
    mediaBrowserProcess.running = true
    return true
  }
  property string browserPendingKind: ""
  // Group control: live settings read on request (they pause sync a moment),
  // and the last answer of a group action (an invite link, pending requests).
  property var groupSettings: ({})
  property bool groupSettingsLoading: false
  property string groupSettingsError: ""
  property var lastGroupResult: ({})
  function loadGroupSettings() {
    var ref = selectedChatRef()
    if (String(ref.jid || "") === "" || selectedChatKind !== "group" || groupInfoProcess.running) return false
    if (offlineMode) { groupSettingsError = "Offline mode is on. Go online to manage the group."; return false }
    groupSettingsLoading = true
    groupSettingsError = ""
    groupInfoProcess.chatRef = ref
    groupInfoProcess.payload = JSON.stringify({ account: ref.account, jid: ref.jid, authorization: "remote-read" })
    groupInfoProcess.stdinEnabled = true
    groupInfoProcess.running = true
    return true
  }
  function groupAction(action, value, owner) {
    var name = String(action || "")
    var request = { action: name, value: value === undefined ? null : value }
    if (name === "invite-get" || name === "requests") request.authorization = "remote-read"
    return runWriteForChat("group-action", request, selectedChatRef(), owner || "app")
  }
  // Chat details panel: what the mirror knows about the selected chat.
  property var chatDetails: ({})
  property bool chatDetailsLoading: false
  property bool chatDetailsWanted: false
  property bool chatDetailsPending: false
  // Where the last first message landed: wacli files an @lid recipient's
  // chat under their phone JID when it knows the mapping.
  property string lastStartedChatJid: ""
  property var numberCheck: ({ account: "", phone: "", loading: false, registered: false,
    responded: false, jid: "", has_chat: false, name: "", error: "" })
  property var pendingReplyReadRef: ({ account: "", jid: "", key: "" })
  // A chat the user explicitly marked unread stays unread while it is open;
  // choosing it again reads it.
  property string manualUnreadKey: ""
  property string lastAutoReadKey: ""
  property double lastAutoReadAt: 0
  property bool showUnreadCount: true
  property bool checkUpdatesOnLaunch: false
  property int dropdownRows: 7
  property int composerMaxLines: 6
  property string timeFormat: "auto"
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
  // Typing and recording shown to the chat, as the phone does: "typing" when
  // the box starts filling and again every 10 s while it goes on, "paused"
  // after 5 s without a key or when the box empties. It follows "Show me
  // online" and never runs without the sync (no second session, no pause).
  property var typingRef: AccountModel.chatRef("", "")
  property string typingState: ""
  property double typingSentAt: 0
  property var pendingChatPresence: []
  readonly property bool typingAllowed: showOnline && !closed && !offlineMode && syncActive && ready
  function composerActivity(chatRef, text) {
    var ref = AccountModel.chatRef(chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
    if (!typingAllowed || ref.jid === "") return false
    if (typingState !== "" && !AccountModel.sameRef(ref, typingRef)) sendChatPresence(typingRef, "paused")
    if (String(text || "").trim() === "") {
      if (typingState === "typing" && AccountModel.sameRef(ref, typingRef)) sendChatPresence(ref, "paused")
      typingIdle.stop()
      return true
    }
    var now = Date.now()
    if (typingState !== "typing" || !AccountModel.sameRef(ref, typingRef) || now - typingSentAt > 10000)
      sendChatPresence(ref, "typing")
    typingIdle.restart()
    return true
  }
  function sendChatPresence(ref, state) {
    typingRef = state === "paused" ? AccountModel.chatRef("", "") : ref
    typingState = state === "paused" ? "" : state
    typingSentAt = Date.now()
    var request = { account: String(ref.account || ""), jid: String(ref.jid || ""), state: state }
    // One waiting state per chat, the latest: a chat left mid-word still
    // hears "paused" when the next one hears "typing".
    if (chatPresenceProcess.running) {
      pendingChatPresence = pendingChatPresence.filter(function(item) {
        return item.jid !== request.jid || item.account !== request.account }).concat([request])
      return true
    }
    chatPresenceProcess.payload = JSON.stringify(request)
    chatPresenceProcess.stdinEnabled = true
    chatPresenceProcess.running = true
    return true
  }
  Timer {
    id: typingIdle
    interval: 5000
    repeat: false
    onTriggered: if (root.typingState === "typing") root.sendChatPresence(root.typingRef, "paused")
  }
  Process {
    id: chatPresenceProcess
    objectName: "chatPresenceProcess"
    property string payload: ""
    command: [root.helper, "chat-presence"]
    stdinEnabled: true
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: {
      if (root.pendingChatPresence.length === 0) return
      var next = root.pendingChatPresence[0]
      root.pendingChatPresence = root.pendingChatPresence.slice(1)
      payload = JSON.stringify(next)
      stdinEnabled = true
      running = true
    }
  }
  readonly property string voiceState: voiceRecorder.state
  // Recording a voice note shows "recording audio…" to that chat.
  onVoiceStateChanged: {
    var ref = AccountModel.chatRef(root.voiceDraftAccount, root.voiceDraftJid)
    if (!root.typingAllowed || ref.jid === "") return
    if (root.voiceState === "recording") root.sendChatPresence(ref, "recording")
    else if (root.typingState === "recording") root.sendChatPresence(ref, "paused")
  }
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
  // Set by the full app and the bar dropdown while the selected conversation
  // itself is on screen. An open window showing only the chat list does not
  // count: reading, badge clearing and popup suppression need the chat seen.
  property bool appConversationVisible: false
  property bool dropdownConversationVisible: false
  readonly property bool conversationOnScreen: appConversationVisible || dropdownConversationVisible
  readonly property bool multiAccount: AccountModel.isMultiAccount(accounts)
  readonly property var storeDirectories:
    AccountModel.storeDirectories(accounts, storeDirectory)
  function sameChat(chat, account, jid) {
    return AccountModel.sameChat(chat, account, jid)
  }
  function selectedChatRef() {
    return AccountModel.chatRef(selectedChatAccount, selectedChatJid)
  }
  // The helper in ~/.local/bin and this plugin are installed together; an
  // update that replaced only the plugin (omarchy plugin update) leaves them
  // apart, and the helper may lack what the plugin asks for.
  readonly property string appVersion: manifest && manifest.version ? String(manifest.version) : ""
  property string helperVersion: ""
  property bool helperAnswered: false
  property bool helperRefusedCommand: false
  readonly property bool helperOutdated: appVersion !== ""
    && (helperRefusedCommand || (helperAnswered && helperVersion !== appVersion))
  // omarchy plugin update replaces the files but the shell keeps the QML it
  // loaded, so the helper runs ahead until the shell restarts.
  readonly property string helperOutdatedText: "Update not finished: the app is " + appVersion
    + " and its helper " + (helperVersion !== "" ? helperVersion : "another version")
    + ". Restart the Omarchy shell to finish."
  function restartShell() {
    Quickshell.execDetached(["/usr/bin/omarchy", "restart", "shell"])
    return true
  }
  function noteHelperRefusal(text) {
    if (/invalid choice|unrecognized arguments/.test(String(text || ""))) helperRefusedCommand = true
  }
  // The helper's own stderr, unless it only says the helper is too old.
  function helperErrorText(stderrText, fallback) {
    noteHelperRefusal(stderrText)
    if (helperOutdated) return helperOutdatedText
    return String(stderrText || fallback).trim()
  }
  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.atoslins.whatsapp"
  property string pendingAppPayload: ""
  signal openDropdownRequested(var payload)
  signal toggleDropdownRequested(var payload)
  PlaybackCoordinator { id: playbackCoordinator }
  AccountOperations {
    id: accountOperations
    helper: root.helper
    accounts: root.accounts
    onRefreshRequested: { root.refreshStatus(); root.refreshChats() }
    onAvatarRefreshFinished: function(checked, pending) {
      root.autoAvatarNotBefore = Date.now()
        + (pending > 0 ? root.autoAvatarBusyGap : root.autoAvatarQuietGap)
    }
  }

  // Automatic chat-photo refresh. wacli needs the store lock for photo
  // lookups, so each batch pauses sync for a few seconds: run only while no
  // window is open, and back off for a day once nothing more is due.
  readonly property double autoAvatarBusyGap: 2 * 60 * 1000
  readonly property double autoAvatarQuietGap: 24 * 60 * 60 * 1000
  property double autoAvatarNotBefore: Date.now() + 10 * 60 * 1000
  function maybeAutoRefreshAvatars() {
    if (!root.autoRefreshAvatars || root.windowOpen || root.offlineMode) return false
    if (!root.ready || !root.statusReady || accountOperations.busy) return false
    if (Date.now() < root.autoAvatarNotBefore) return false
    root.autoAvatarNotBefore = Date.now() + root.autoAvatarBusyGap
    return accountOperations.refreshAvatars()
  }
  Timer {
    id: autoAvatarTimer
    interval: 60 * 1000
    repeat: true
    running: root.autoRefreshAvatars
    onTriggered: root.maybeAutoRefreshAvatars()
  }
  // The helper ships in this checkout, at bin/ two levels above this file:
  // the helper and the QML always come from the same commit.
  readonly property string helper: decodeURIComponent(
    String(Qt.resolvedUrl("../../bin/omawhatsapp")).replace(/^file:\/\//, ""))
  readonly property string storeDirectory: AccountModel.defaultStoreDirectory(
    Quickshell.env("WACLI_STORE_DIR"), Quickshell.env("XDG_STATE_HOME"),
    Quickshell.env("HOME"))
  readonly property int unreadCount: chats.reduce(function(total, chat) {
    return total + Number(chat.unread || 0)
  }, 0)
  // Why sync is down when this app stopped it: wacli can do these only while
  // it holds the store itself. Empty when the pause is not ours.
  readonly property string syncPauseReason: {
    if (syncActive) return ""
    if (accountOperations && accountOperations.avatarBusy) return "checking chat photos"
    if (numberCheck && numberCheck.loading) return "checking a number"
    if (groupSettingsLoading) return "reading group settings"
    if (!writing) return ""
    // Files, voice notes, text, stickers, polls and reactions go through the
    // sync process itself (wacli 0.18.3) and never pause it.
    switch (activeWriteKind) {
    case "chat-action": return "updating the chat"
    case "group-action": return "updating the group"
    case "delete": return "deleting a message"
    case "forward": return "forwarding a message"
    case "send-new": return "starting a chat"
    case "star": return "starring a message"
    default: return ""
    }
  }
  // The badge counts chats, as WhatsApp's own icon does: 3 means three
  // conversations are waiting, not three messages.
  readonly property int notificationUnreadCount: chats.reduce(function(total, chat) {
    return total + (Number(chat.notification_unread || 0) > 0 ? 1 : 0)
  }, 0)
  readonly property int notificationMessageCount: chats.reduce(function(total, chat) {
    return total + Number(chat.notification_unread || 0)
  }, 0)
  readonly property string barTooltip: helperOutdated ? "WhatsApp for Omarchy · restart the shell to finish updating"
    : closed ? "WhatsApp for Omarchy is closed · click to open"
    : !railReady ? "WhatsApp for Omarchy · reconnecting"
    : offlineMode ? "WhatsApp for Omarchy · offline archive"
    : notificationUnreadCount === 0 ? "WhatsApp for Omarchy · no unread chats"
    : "WhatsApp for Omarchy · " + notificationUnreadCount
      + (notificationUnreadCount === 1 ? " unread chat" : " unread chats")
      + " · " + notificationMessageCount
      + (notificationMessageCount === 1 ? " message" : " messages")
      + " · middle-click to dismiss"
  readonly property string barTooltipWithMute: barTooltip
    + (notificationsMuted ? "\nNotifications muted · right-click to turn them on"
      : "\nRight-click to mute notifications")

  signal textPasted(string text, var chatRef, string owner)
  signal attachmentPasted(string path, var chatRef, string owner)
  signal pasteFailed(string message, var chatRef, string owner)
  signal writeCompleted(string kind, var chatRef, var request, string owner)
  signal writeFailed(string message, var chatRef, var details, string owner)
  // A forward to several chats ended: who got it, and what failed.
  signal forwardBatchFinished(var summary)
  // Several messages deleted together: how many went, and what failed.
  signal deleteBatchFinished(var summary)
  signal starBatchFinished(var summary)
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
    if (!railReady || !notificationsEnabled) return
    if (notifyProcess.running) { notifyPending = true; return }
    notifyPending = false
    notifyProcess.payload = JSON.stringify({
      account: selectedChatAccount,
      skip_jid: conversationOnScreen ? selectedChatJid : ""
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
    if (notificationsEnabled) notifyDebounce.restart()
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
    manualUnreadKey = ""
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
      lastMessagesRaw = ""
      members = []
      olderMessages = []
      hasOlderMessages = true
      browserItems = []
      groupSettings = ({})
      groupSettingsError = ""
      lastGroupResult = ({})
      chatDetails = ({})
      errorText = ""
      refreshMessages()
      refreshMembers()
      if (chatDetailsWanted) Qt.callLater(refreshChatDetails)
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
    // Paused sync means the store lock is taken; retry once it is back.
    if (!syncActive && !offlineMode) { receiptRetry.interval = 2000; receiptRetry.restart(); return }
    receiptRetry.interval = 100
    if (!SettingsPolicy.shouldSendAutomaticReceipt(
          sendReadReceipts, offlineMode, false)) {
      pendingReceiptRef = AccountModel.chatRef("", "")
      return
    }
    Qt.callLater(function() {
      if (!AccountModel.sameRef(target, root.selectedChatRef())) return
      if (!root.conversationOnScreen) return
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
      // Once the process that just ended is fully gone.
      if (sendQueue.length > 0) Qt.callLater(runNextQueuedSend)
      else if (writeBatch) Qt.callLater(runNextBatchJob)
    }
  }
  function search(value) {
    var next = String(value || "").trim()
    if (next === query) return
    query = next
    refreshMessages()
  }
  function selectItem(id) { selectedId = String(id || "") }
  function writeOwner(owner) {
    return ["app", "dropdown", "service"].indexOf(String(owner || "")) >= 0
      ? String(owner) : "service"
  }
  // Why a write for this chat cannot start now, or "" when it can.
  function writeRefusal(kind, payload, targetRef) {
    if (!statusReady || statusAccount !== targetRef.account)
      return "That account is still loading. Try again in a moment."
    if (!ready) return "That account is not linked or its local archive is not ready."
    // Saving a copy works offline when the file is already local; the helper
    // refuses the download part while offline.
    var isLocalAction = (kind === "chat-action" && payload && payload.action === "remove-local")
      || ["save-media", "export-chat", "contact-alias", "contact-tag"].indexOf(kind) >= 0
    if (offlineMode && !isLocalAction)
      return "Offline mode is on. Go online before sending or changing WhatsApp state."
    return ""
  }
  function runWriteForChat(kind, payload, chatRef, owner) {
    var targetRef = AccountModel.chatRef(
      chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
    var target = targetRef.jid
    var scope = targetRef.account
    var origin = writeOwner(owner)
    if (writing || writeProcess.running || target === "") return false
    var refusal = writeRefusal(kind, payload, targetRef)
    if (refusal !== "") {
      errorText = refusal
      writeFailed(refusal, targetRef, ({}), origin)
      if (!statusReady || statusAccount !== scope) refreshStatus()
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
  // Texts typed while another WhatsApp action runs wait here in order, each
  // already on screen as a pending bubble, so Enter never waits for the
  // network and the next message can be typed at once.
  property var sendQueue: []
  // The signature of an account, as its status reports it.
  function signatureFor(account) {
    return ComposerModel.signatureOf(root.accounts, account)
  }
  // `signed` false sends this one message without the account's signature.
  function sendText(chatRef, text, replyId, mentions, owner, signed) {
    var ref = AccountModel.chatRef(chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
    var value = String(text || "").trim()
    if (value === "") return false
    if (ref.jid === "") return false
    if (signed !== false) value = ComposerModel.signedText(value, signatureFor(ref.account))
    var origin = writeOwner(owner)
    pendingSendSerial += 1
    var localId = "pending:" + pendingSendSerial
    var payload = {
      text: value,
      reply_id: String(replyId || ""),
      mentions: Array.isArray(mentions) ? mentions.slice() : [],
      local_id: localId
    }
    var queued = writing || writeProcess.running || sendQueue.length > 0
    if (queued) {
      var refusal = writeRefusal("send", payload, ref)
      if (refusal !== "") {
        errorText = refusal
        writeFailed(refusal, ref, ({}), origin)
        return false
      }
      sendQueue = sendQueue.concat([{ payload: payload, chatRef: ref, owner: origin }])
    } else if (!runWriteForChat("send", payload, ref, origin)) {
      return false
    }
    pendingSends = pendingSends.concat([{
      local_id: localId, key: ref.key, text: value, reply_id: payload.reply_id,
      timestamp: Math.floor(Date.now() / 1000), created: Date.now(),
      state: queued ? "queued" : "sending", message_id: "",
      request: payload, chatRef: ref, owner: origin
    }])
    return true
  }
  function runNextQueuedSend() {
    while (!writing && !writeProcess.running && sendQueue.length > 0) {
      var next = sendQueue[0]
      sendQueue = sendQueue.slice(1)
      var refusal = writeRefusal("send", next.payload, next.chatRef)
      if (refusal === "" && runWriteForChat("send", next.payload, next.chatRef, next.owner)) {
        updatePendingSend(next.payload.local_id, { state: "sending" })
        return true
      }
      // Offline or the account went away meanwhile: it stays on screen, not sent.
      updatePendingSend(next.payload.local_id, { state: "failed",
        error: refusal !== "" ? refusal : "WhatsApp could not send this message." })
    }
    return false
  }
  // Retry or discard a message that failed to send; it keeps its bubble until then.
  function resolvePendingSend(localId, action) {
    var id = String(localId || "")
    var item = null
    for (var i = 0; i < pendingSends.length; i++)
      if (pendingSends[i].local_id === id) item = pendingSends[i]
    if (!item || item.state !== "failed") return false
    if (action === "discard") {
      dropPendingSend(id)
      return true
    }
    if (action !== "retry" || !item.request) return false
    var refusal = writeRefusal("send", item.request, item.chatRef)
    if (refusal !== "") {
      errorText = refusal
      updatePendingSend(id, { error: refusal })
      return false
    }
    sendQueue = sendQueue.concat([{ payload: item.request, chatRef: item.chatRef, owner: item.owner }])
    updatePendingSend(id, { state: "queued", error: "", created: Date.now() })
    runNextQueuedSend()
    return true
  }
  function updatePendingSend(localId, changes) {
    var id = String(localId || "")
    if (id === "") return
    pendingSends = pendingSends.map(function(item) {
      return item.local_id === id ? Object.assign({}, item, changes) : item
    })
  }
  function dropPendingSend(localId) {
    var id = String(localId || "")
    pendingSends = pendingSends.filter(function(item) { return item.local_id !== id })
  }
  // A pending bubble gives way once the mirror holds its message, and never
  // outlives a sane delay if the stored row never matches.
  function prunePendingSends() {
    if (pendingSends.length === 0) return
    var key = selectedChatRef().key
    var stored = {}
    for (var i = 0; i < messages.length; i++) stored[String(messages[i].id || "")] = true
    var now = Date.now()
    var next = pendingSends.filter(function(item) {
      if (item.message_id !== "" && item.key === key && stored[item.message_id]) return false
      // Files land as several rows (an album, a caption); the first refresh
      // after the upload finished carries them.
      if (item.kind === "files" && item.state === "sent") return false
      if (item.state === "sent" && now - item.created > 90000) return false
      // Unsent text stays until it is retried or discarded.
      if (item.state === "failed" || item.state === "queued" || item.state === "sending") return true
      return now - item.created < 300000
    })
    if (next.length !== pendingSends.length) pendingSends = next
  }
  // Pasting only reads the clipboard and stages an image, so it runs on its
  // own process: a send or a read mark in flight never swallows Ctrl+V.
  function pasteClipboard(chatRef, owner) {
    var targetRef = AccountModel.chatRef(
      chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
    if (pasteProcess.running || targetRef.jid === "") return false
    pasteProcess.chatRef = targetRef
    pasteProcess.owner = ["app", "dropdown"].indexOf(String(owner || "")) >= 0
      ? String(owner) : "service"
    pasteProcess.payload = JSON.stringify({ account: targetRef.account, jid: targetRef.jid })
    pasteProcess.stdinEnabled = true
    pasteProcess.running = true
    return true
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
  function sendFilesReply(chatRef, paths, caption, replyId, owner, signed) {
    var files = Array.isArray(paths) ? paths : []
    pendingSendSerial += 1
    var localId = "pending:" + pendingSendSerial
    var text = String(caption || "").trim()
    // A caption carries the signature; a file sent without one gets none.
    if (signed !== false && text !== "")
      text = ComposerModel.signedText(text, signatureFor(chatRef ? String(chatRef.account || "") : ""))
    var started = runWriteForChat("files", {
      paths: files,
      caption: text,
      reply_id: String(replyId || ""),
      local_id: localId
    }, chatRef, owner)
    if (started && files.length > 0) {
      var ref = AccountModel.chatRef(chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
      var name = decodeURIComponent(String(files[0]).split("/").pop() || "file")
      var label = "📎 " + (files.length === 1 ? name : files.length + " files")
      pendingSends = pendingSends.concat([{
        local_id: localId, key: ref.key, kind: "files",
        text: text !== "" ? label + "\n" + text : label, reply_id: String(replyId || ""),
        timestamp: Math.floor(Date.now() / 1000), created: Date.now(),
        state: "sending", message_id: ""
      }])
    }
    return started
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
    var file = String(path || "")
    pendingSendSerial += 1
    var localId = "pending:" + pendingSendSerial
    var started = runWriteForChat("sticker", {
      path: file,
      reply_id: String(replyId || ""),
      local_id: localId
    }, chatRef, owner)
    if (started && file !== "") {
      var ref = AccountModel.chatRef(chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
      pendingSends = pendingSends.concat([{
        local_id: localId, key: ref.key, kind: "sticker", text: "", reply_id: String(replyId || ""),
        media_type: "sticker", local_path: file.indexOf("file://") === 0 ? decodeURIComponent(file.slice(7)) : file,
        timestamp: Math.floor(Date.now() / 1000), created: Date.now(),
        state: "sending", message_id: ""
      }])
    }
    return started
  }
  // Sticker picker: recent stickers of this account, fetched on first open.
  property var stickers: []
  property bool stickersLoading: false
  function refreshStickers(fetchMissing) {
    if (stickersProcess.running) return false
    var fetch = fetchMissing === true && !offlineMode
    stickersLoading = fetch
    stickersProcess.command = [helper, fetch ? "fetch-stickers" : "stickers"]
    stickersProcess.payload = JSON.stringify({ account: statusAccount })
    stickersProcess.stdinEnabled = true
    stickersProcess.running = true
    return true
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
  function saveMedia(chatRef, item, destination, owner) {
    if (!item || !item.id || String(destination || "") === "") return false
    // The save dialog already asked before replacing a file.
    return runWriteForChat("save-media", {
      id: String(item.id), destination: String(destination), replace: true
    }, chatRef, owner)
  }
  onChatDetailsWantedChanged: if (chatDetailsWanted) refreshChatDetails()
  function refreshChatDetails() {
    var ref = selectedChatRef()
    if (String(ref.jid || "") === "") return false
    if (chatDetailsProcess.running) { chatDetailsPending = true; return false }
    chatDetailsLoading = true
    chatDetailsProcess.chatRef = ref
    chatDetailsProcess.payload = JSON.stringify({ account: ref.account, jid: ref.jid })
    chatDetailsProcess.stdinEnabled = true
    chatDetailsProcess.running = true
    return true
  }
  function searchPeople(query) {
    newChatPeopleQuery = String(query || "").trim()
    if (contactsProcess.running) { newChatPeoplePending = true; return true }
    if (!statusReady || !ready) return false
    newChatPeopleLoading = true
    contactsProcess.account = statusAccount
    contactsProcess.query = newChatPeopleQuery
    contactsProcess.payload = JSON.stringify({ account: statusAccount, query: newChatPeopleQuery })
    contactsProcess.stdinEnabled = true
    contactsProcess.running = true
    return true
  }
  // Creating a group or joining one by link: a request of its own, since it
  // has no chat to target yet. The dialog follows groupRequest.
  property var groupRequest: ({ kind: "", loading: false, jid: "", error: "" })
  function runGroupRequest(kind, fields) {
    if (groupRequestProcess.running) return false
    if (offlineMode) {
      groupRequest = { kind: kind, loading: false, jid: "",
        error: "Offline mode is on. Go online to change WhatsApp." }
      return false
    }
    if (!statusReady || !ready) {
      groupRequest = { kind: kind, loading: false, jid: "",
        error: "That account is still loading. Try again in a moment." }
      return false
    }
    groupRequest = { kind: kind, loading: true, jid: "", error: "" }
    groupRequestProcess.kind = kind
    groupRequestProcess.command = [helper, kind]
    groupRequestProcess.payload = JSON.stringify(Object.assign({ account: statusAccount }, fields))
    groupRequestProcess.stdinEnabled = true
    groupRequestProcess.running = true
    return true
  }
  function createGroup(name, participants) {
    var people = []
    for (var i = 0; i < Number(participants ? participants.length : 0); i++)
      people.push(String(participants[i]))
    return runGroupRequest("create-group", { name: String(name || ""), participants: people })
  }
  function joinGroup(invite) {
    return runGroupRequest("join-group", { invite: String(invite || "") })
  }
  function numberCheckFor(phone) {
    var digits = String(phone || "").replace(/[^0-9]/g, "")
    return String(numberCheck.phone || "") === digits
      && String(numberCheck.account || "") === statusAccount ? numberCheck : null
  }
  function checkNumber(phone) {
    var digits = String(phone || "").replace(/[^0-9]/g, "")
    var base = { account: statusAccount, phone: digits, loading: false, registered: false,
      responded: false, jid: "", has_chat: false, name: "", error: "" }
    if (checkNumberProcess.running) return false
    if (digits.length < 7 || digits.length > 15) {
      numberCheck = Object.assign(base, { error: "Type a phone number with its country code." })
      return false
    }
    if (offlineMode) {
      numberCheck = Object.assign(base, {
        error: "Offline mode is on. Go online to check a number with WhatsApp." })
      return false
    }
    if (!statusReady || !ready) {
      numberCheck = Object.assign(base, { error: "That account is still loading. Try again in a moment." })
      return false
    }
    numberCheck = Object.assign(base, { loading: true })
    checkNumberProcess.account = statusAccount
    checkNumberProcess.phone = digits
    checkNumberProcess.payload = JSON.stringify({
      account: statusAccount, phone: String(phone), authorization: "remote-read" })
    checkNumberProcess.stdinEnabled = true
    checkNumberProcess.running = true
    return true
  }
  function startNewChat(jid, text, owner) {
    var value = String(text || "").trim()
    var target = String(jid || "")
    if (value === "" || !/^[0-9]{5,20}@(s[.]whatsapp[.]net|lid)$/.test(target)) return false
    return runWriteForChat("send-new", { target: { jid: target }, text: value },
      AccountModel.chatRef(statusAccount, target), owner)
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
  // Starring needs a wacli build that stars; the first refusal hides it.
  property bool starSupported: true
  function starMessage(chatRef, item, starred, owner) {
    if (!item || !item.id || !starSupported) return false
    var started = runWriteForChat("star", { id: String(item.id), starred: starred !== false }, chatRef, owner)
    if (started) setStarOverride(chatRef, item.id, starred !== false)
    return started
  }
  function starMany(chatRef, items, starred, owner) {
    var origin = AccountModel.chatRef(chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
    var messages = (Array.isArray(items) ? items : []).filter(function(item) {
      return item && String(item.id || "") !== "" && item.pending !== true && item.revoked !== true })
    if (!starSupported || origin.jid === "" || messages.length === 0 || writeBatch) return false
    var refusal = writeRefusal("star", ({}), origin)
    if (refusal !== "") {
      errorText = refusal
      writeFailed(refusal, origin, ({ kind: "star" }), writeOwner(owner))
      return false
    }
    writeBatch = { kind: "star", origin: origin, owner: writeOwner(owner), starred: starred !== false,
      total: messages.length, done: 0, failed: 0, errors: [] }
    batchJobs = messages.map(function(item) { return { kind: "star", item: item, starred: starred !== false } })
    messages.forEach(function(item) { setStarOverride(origin, item.id, starred !== false) })
    runNextBatchJob()
    return true
  }
  function forwardMessage(chatRef, item, targetJid, owner) {
    if (!item || !item.id || String(targetJid || "") === "") return false
    return runWriteForChat("forward", {
      id: String(item.id), to_jid: String(targetJid)
    }, chatRef, owner)
  }
  // Several messages to several chats of the same account, with an optional
  // note after them in each chat. One WhatsApp action at a time, in order:
  // each chat gets the messages oldest first, then the note.
  property var batchJobs: []
  property var writeBatch: null
  function forwardMany(originRef, items, targets, note, owner) {
    var origin = AccountModel.chatRef(originRef ? originRef.account : "", originRef ? originRef.jid : "")
    var messages = (Array.isArray(items) ? items : []).filter(function(item) {
      return item && String(item.id || "") !== "" && item.pending !== true })
    // A target is a chat of this account, or a number WhatsApp just confirmed.
    var chats = (Array.isArray(targets) ? targets : []).filter(function(chat) {
      return chat && (String(chat.jid || "") !== "" || /^[0-9]{7,15}$/.test(String(chat.phone || "")))
        && String(chat.account || "") === String(origin.account || "") })
    if (origin.jid === "" || messages.length === 0 || chats.length === 0 || writeBatch) return false
    var refusal = writeRefusal("forward", ({}), origin)
    if (refusal !== "") {
      errorText = refusal
      writeFailed(refusal, origin, ({ kind: "forward" }), writeOwner(owner))
      return false
    }
    var text = String(note || "").trim()
    var jobs = []
    chats.forEach(function(chat) {
      messages.forEach(function(item) {
        jobs.push({ kind: "forward", item: item, target: chat })
      })
      if (text !== "") jobs.push({ kind: "note", text: text, target: chat })
    })
    writeBatch = { kind: "forward", origin: origin, owner: writeOwner(owner), targets: chats.map(function(chat) {
      var phone = String(chat.phone || "")
      return { account: String(chat.account || ""),
        jid: String(chat.jid || "") !== "" ? String(chat.jid) : phone + "@s.whatsapp.net",
        phone: String(chat.jid || "") !== "" ? "" : phone, name: String(chat.name || "") } }),
      total: jobs.length, done: 0, failed: 0, errors: [], note: text }
    batchJobs = jobs
    runNextBatchJob()
    return true
  }
  function runNextBatchJob() {
    if (!writeBatch) return false
    while (!writing && !writeProcess.running && sendQueue.length === 0 && batchJobs.length > 0) {
      var job = batchJobs[0]
      batchJobs = batchJobs.slice(1)
      var newNumber = job.target && String(job.target.jid || "") === "" && String(job.target.phone || "") !== ""
      var started = job.kind === "note" && newNumber
        // A number with no chat yet: the note is its first message.
        ? runWriteForChat("send-new", { target: { phone: "+" + String(job.target.phone) },
            text: ComposerModel.signedText(job.text, signatureFor(writeBatch.origin.account)), batch: true },
            AccountModel.chatRef(writeBatch.origin.account, String(job.target.phone) + "@s.whatsapp.net"),
            writeBatch.owner)
        : job.kind === "note"
        ? sendText(AccountModel.refOf(job.target), job.text, "", [], writeBatch.owner)
        : job.kind === "delete"
        ? runWriteForChat("delete", { id: String(job.item.id), for_me: job.forMe === true,
            batch: true }, writeBatch.origin, writeBatch.owner)
        : job.kind === "star"
        ? runWriteForChat("star", { id: String(job.item.id), starred: job.starred === true,
            batch: true }, writeBatch.origin, writeBatch.owner)
        : runWriteForChat("forward", { id: String(job.item.id), to_jid: String(job.target.jid || ""),
            to_phone: newNumber ? String(job.target.phone) : "", batch: true },
            writeBatch.origin, writeBatch.owner)
      if (job.kind === "note" && !newNumber) {
        // The note is one more queued text; it reports like any send.
        finishBatchJob(started, started ? "" : (errorText || "The note could not be sent."))
        continue
      }
      if (started) return true
      finishBatchJob(false, errorText || (job.kind === "delete"
        ? "WhatsApp could not delete that message." : "WhatsApp could not forward that message."))
    }
    if (batchJobs.length === 0 && !writing && !writeProcess.running) endBatch()
    return false
  }
  function finishBatchJob(ok, message) {
    if (!writeBatch) return
    var next = Object.assign({}, writeBatch)
    next.done += 1
    if (!ok) {
      next.failed += 1
      if (String(message || "") !== "" && next.errors.indexOf(String(message)) < 0)
        next.errors = next.errors.concat([String(message)])
    }
    writeBatch = next
  }
  function endBatch() {
    if (!writeBatch || batchJobs.length > 0) return
    var summary = writeBatch
    writeBatch = null
    if (summary.kind === "delete") deleteBatchFinished(summary)
    else if (summary.kind === "star") starBatchFinished(summary)
    else forwardBatchFinished(summary)
  }
  // Several messages of one chat deleted together, for you or (all yours)
  // for everyone, one WhatsApp action at a time.
  function deleteMany(chatRef, items, forMe, owner) {
    var origin = AccountModel.chatRef(chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
    var messages = (Array.isArray(items) ? items : []).filter(function(item) {
      return item && String(item.id || "") !== "" && item.pending !== true && item.revoked !== true })
    if (origin.jid === "" || messages.length === 0 || writeBatch) return false
    if (forMe !== true && messages.some(function(item) { return item.from_me !== true })) return false
    var refusal = writeRefusal("delete", ({}), origin)
    if (refusal !== "") {
      errorText = refusal
      writeFailed(refusal, origin, ({ kind: "delete" }), writeOwner(owner))
      return false
    }
    writeBatch = { kind: "delete", origin: origin, owner: writeOwner(owner), forMe: forMe === true,
      total: messages.length, done: 0, failed: 0, errors: [] }
    batchJobs = messages.map(function(item) { return { kind: "delete", item: item, forMe: forMe === true } })
    runNextBatchJob()
    return true
  }
  property var lastWriteResult: ({})
  function exportChat(chatRef, destination, owner) {
    return runWriteForChat("export-chat", { destination: String(destination || ""), replace: true }, chatRef, owner)
  }
  function downloadPending(chatRef, owner) {
    return runWriteForChat("download-pending", { limit: 50 }, chatRef, owner)
  }
  function setContactAlias(chatRef, person, alias, owner) {
    return runWriteForChat("contact-alias", { person: String(person || ""),
      alias: String(alias || "") }, chatRef, owner)
  }
  function setContactTag(chatRef, person, tag, remove, owner) {
    return runWriteForChat("contact-tag", { person: String(person || ""),
      tag: String(tag || ""), remove: remove === true }, chatRef, owner)
  }
  // A person's about and business profile, asked of WhatsApp on request.
  property var contactProfile: ({ jid: "", loading: false, about: "", business: ({}), error: "" })
  function loadContactProfile(chatRef, person) {
    var jid = String(person || "")
    if (jid === "" || contactProfileProcess.running) return false
    if (offlineMode) {
      contactProfile = { jid: jid, loading: false, about: "", business: ({}),
        error: "Offline mode is on. Go online to ask WhatsApp." }
      return false
    }
    contactProfile = { jid: jid, loading: true, about: "", business: ({}), error: "" }
    contactProfileProcess.person = jid
    contactProfileProcess.payload = JSON.stringify({
      account: chatRef ? String(chatRef.account || "") : "", person: jid,
      authorization: "remote-read" })
    contactProfileProcess.stdinEnabled = true
    contactProfileProcess.running = true
    return true
  }
  function votePoll(chatRef, item, options, owner) {
    if (!item || !item.id || !options || Number(options.length || 0) === 0) return false
    var chosen = []
    for (var i = 0; i < Number(options.length); i++) chosen.push(String(options[i]))
    return runWriteForChat("poll-vote", { id: String(item.id), options: chosen }, chatRef, owner)
  }
  function selectOption(chatRef, item, index, owner) {
    if (!item || !item.id) return false
    return runWriteForChat("select", {
      id: String(item.id), index: Number(index)
    }, chatRef, owner)
  }
  function chatAction(chatRef, action, owner) {
    if (action === "read" || action === "unread") return markChatState(chatRef, action, owner)
    var started = runWriteForChat("chat-action", {
      action: String(action || "")
    }, chatRef, owner)
    // wacli cannot delegate pin, mute or archive, so the write pauses sync
    // for a few seconds; the rail shows the result at once instead of after
    // the next refresh. A failure refreshes the rail back to the mirror.
    if (started) applyChatActionLocally(chatRef, action)
    return started
  }
  // Read and unread marks have a process of their own. Writing read state can
  // make wacli wait for WhatsApp to repair the account's app state, for
  // minutes; a reply typed meanwhile must still go out at once. One mark at a
  // time, the latest one per chat.
  property var readMarkQueue: []
  property var activeReadMark: null
  signal chatStateFailed(string message, var chatRef, string action, string owner)
  function markChatState(chatRef, action, owner) {
    var ref = AccountModel.chatRef(chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
    if (ref.jid === "" || (action !== "read" && action !== "unread")) return false
    var origin = writeOwner(owner)
    var refusal = writeRefusal("chat-action", { action: action }, ref)
    if (refusal !== "") {
      chatStateFailed(refusal, ref, action, origin)
      if (!statusReady || statusAccount !== ref.account) refreshStatus()
      return false
    }
    readMarkQueue = readMarkQueue.filter(function(item) { return item.ref.key !== ref.key })
      .concat([{ ref: ref, action: action, owner: origin }])
    applyChatActionLocally(ref, action)
    runNextReadMark()
    return true
  }
  function runNextReadMark() {
    if (readMarkProcess.running || readMarkQueue.length === 0) return false
    // Without the sync's queue to share, two wacli runs would contend for the
    // store: the mark waits for the running write instead.
    if (!syncActive && (writing || writeProcess.running)) {
      readMarkRetry.restart()
      return false
    }
    var next = readMarkQueue[0]
    readMarkQueue = readMarkQueue.slice(1)
    activeReadMark = next
    readMarkProcess.payload = JSON.stringify({ jid: next.ref.jid, account: next.ref.account,
      action: next.action })
    readMarkProcess.stdinEnabled = true
    readMarkProcess.running = true
    return true
  }
  function applyChatActionLocally(chatRef, action) {
    var changes = ({
      pin: { pinned: true }, unpin: { pinned: false },
      mute: { muted: true }, unmute: { muted: false },
      archive: { archived: true }, unarchive: { archived: false }
    })[String(action || "")]
    if (!changes) return false
    var ref = AccountModel.chatRef(chatRef ? chatRef.account : "", chatRef ? chatRef.jid : "")
    lastChatsRaw = ""
    var next = chats.map(function(item) {
      return AccountModel.sameRef(AccountModel.refOf(item), ref) ? Object.assign({}, item, changes) : item
    })
    // The helper's order: pinned first, then newest, then by name.
    next.sort(function(a, b) {
      if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1
      var byTime = Number(b.timestamp || 0) - Number(a.timestamp || 0)
      if (byTime !== 0) return byTime
      return String(a.name || "").localeCompare(String(b.name || ""))
    })
    chats = next
    return true
  }
  // A conversation on screen is a conversation being read: messages that
  // arrive while it is open are marked read too, unless the user chose
  // "Mark as unread" for it. Throttled so a failing write cannot loop.
  function readOpenChatIfUnread(chat) {
    if (!root.conversationOnScreen || !chat || Number(chat.unread || 0) <= 0) return false
    // While sync is paused (a photo batch, a locked write) mark-read would
    // wait on the store lock and hold the write queue; a later refresh after
    // sync returns reads the chat instead.
    if (!root.syncActive) return false
    var ref = AccountModel.refOf(chat)
    if (!AccountModel.sameRef(ref, root.selectedChatRef())) return false
    if (ref.key === root.manualUnreadKey) return false
    var now = Date.now()
    if (ref.key === root.lastAutoReadKey && now - root.lastAutoReadAt < 10000) return false
    root.lastAutoReadKey = ref.key
    root.lastAutoReadAt = now
    root.pendingReceiptRef = ref
    root.maybeSendAutomaticReceipt()
    return true
  }

  // Mark one exact chat read or unread on WhatsApp. The count changes at once
  // and the next refresh confirms it from the mirror.
  function setChatRead(chatRef, read, owner) {
    var target = AccountModel.chatRef(String(chatRef && chatRef.account || ""),
      String(chatRef && chatRef.jid || ""))
    if (String(target.jid || "") === "") return false
    if (!root.chatAction(target, read ? "read" : "unread", owner)) return false
    if (!read && AccountModel.sameRef(target, root.selectedChatRef()))
      root.manualUnreadKey = target.key
    root.lastChatsRaw = ""
    root.chats = root.chats.map(function(item) {
      if (!root.sameChat(item, target.account, target.jid)) return item
      var next = Object.assign({}, item)
      next.unread = read ? 0 : Math.max(1, Number(item.unread || 0))
      if (read) next.notification_unread = 0
      return next
    })
    return true
  }
  function clearNotificationCount(jid, account) {
    var target = String(jid || "")
    root.lastChatsRaw = ""
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
  function setNotifications(enabled, preview, sound) {
    if (controlProcess.running || writing) return false
    var request = ({})
    if (enabled !== undefined && enabled !== null) request.enabled = enabled === true
    if (preview !== undefined && preview !== null) request.preview = preview === true
    if (sound !== undefined && sound !== null) request.sound = sound === true
    controlWriting = true
    controlProcess.kind = "notify-mode"
    controlProcess.account = ""
    controlProcess.payload = JSON.stringify(request)
    controlProcess.command = [helper, "notify-mode"]
    controlProcess.stdinEnabled = true
    controlProcess.running = true
    return true
  }
  // Right-clicking the bar icon mutes or unmutes every notification. It flips
  // the Settings switch itself, so the two never disagree, and switching back
  // on starts from the current messages instead of replaying the muted ones.
  property string lastOsdMessage: ""
  // -1: nothing waiting; 0: mute, 1: unmute, retried while a write finishes.
  property int pendingNotificationsOn: -1
  readonly property bool notificationToggleInFlight: pendingNotificationsOn >= 0
    || (controlProcess.running && controlProcess.kind === "notify-mode")
  readonly property bool notificationsMuted: pendingNotificationsOn >= 0
    ? pendingNotificationsOn === 0 : !notificationsEnabled
  function toggleNotificationsMuted() {
    return setNotificationsOn(notificationsMuted)
  }
  function setNotificationsOn(on) {
    var next = on === true
    showNotificationOsd(next)
    if (!setNotifications(next, null)) {
      pendingNotificationsOn = next ? 1 : 0
      notificationToggleRetry.restart()
      return false
    }
    pendingNotificationsOn = -1
    notificationToggleRetry.stop()
    notificationsEnabled = next
    return true
  }
  function showNotificationOsd(on) {
    lastOsdMessage = on ? "WhatsApp notifications on" : "WhatsApp notifications muted"
    Quickshell.execDetached(["omarchy", "osd", "-i", on ? "󰂚" : "󰂛", "-m", lastOsdMessage])
  }
  Timer {
    id: notificationToggleRetry
    interval: 300
    repeat: true
    onTriggered: {
      if (root.pendingNotificationsOn < 0) { stop(); return }
      var next = root.pendingNotificationsOn === 1
      if (!root.setNotifications(next, null)) return
      root.pendingNotificationsOn = -1
      root.notificationsEnabled = next
      stop()
    }
  }

  function setAutoDownloadMedia(enabled) {
    if (controlProcess.running || writing) return false
    controlWriting = true
    controlProcess.kind = "media-mode"
    controlProcess.account = ""
    controlProcess.payload = JSON.stringify({ auto_download_media: enabled === true })
    controlProcess.command = [helper, "media-mode"]
    controlProcess.stdinEnabled = true
    controlProcess.running = true
    return true
  }
  function refreshAbout() {
    if (aboutProcess.running) return false
    aboutLoading = true
    aboutProcess.running = true
    return true
  }

  // Quit: every account's sync stops until WhatsApp for Omarchy opens again (this
  // login session); nothing arrives, no popup, not shown online.
  property bool closed: false
  property bool startAtLogin: true
  // First run: nothing linked yet (or no wacli at all) shows the welcome.
  property bool wacliInstalled: true
  property bool anyAuthenticated: true
  property string defaultAccountName: "primary"
  // What the first run sets up outside the plugin folder (sync units, the
  // command link, the agent skill), as the helper reports it.
  property var setupState: ({})
  readonly property bool setupKnown: setupState.units !== undefined
  readonly property bool setupComplete: setupState.complete === true
  // Agent access is opt-in: off unless the user said yes.
  readonly property bool setupAgents: setupState.agents === true
  readonly property bool zenityAvailable: setupState.zenity !== false
  readonly property bool originalPluginEnabled: !!setupState.original_plugin
    && setupState.original_plugin.enabled === true
  // Paths the setup needs that belong to something else; it never touches
  // them, and waits until they are moved away.
  readonly property var setupConflicts: Array.isArray(setupState.conflicts) ? setupState.conflicts : []
  // Consent already given (or an install by the old script) is applied without
  // asking again; replacing the original OmaWhatsApp always asks.
  readonly property bool setupAutomatic: (setupState.consented === true
    || setupState.previous_install === true) && !originalPluginEnabled
    && setupConflicts.length === 0
  readonly property bool needsSetup: setupKnown && !setupComplete && !setupAutomatic
  // wacli is installed but older than the helper's minimum.
  property bool wacliTooOld: false
  property string wacliVersion: ""
  readonly property bool needsOnboarding: !wacliInstalled || wacliTooOld || needsSetup
    || (statusReady && !anyAuthenticated)
  property bool setupWriting: false
  property bool autoSetupTried: false
  property var lastTeardown: null
  signal setupCompleted(string kind)
  function acceptSetupState(value) {
    if (!value || typeof value !== "object") return
    setupState = value
    if (!setupComplete && setupAutomatic && !autoSetupTried && !setupWriting
        && value.wacli && value.wacli.found === true) {
      autoSetupTried = true
      runSetup(null, false)
    }
  }
  function runSetup(agents, replaceOriginal) {
    if (setupProcess.running) return false
    setupWriting = true
    setupProcess.kind = "setup"
    setupProcess.stdinEnabled = true
    setupProcess.payload = JSON.stringify({
      agents: agents === true ? true : (agents === false ? false : null),
      replace_original: replaceOriginal === true
    })
    setupProcess.running = true
    return true
  }
  // Undo the setup; the linked device, the archive and the settings stay.
  function removeFromComputer() {
    if (setupProcess.running) return false
    setupWriting = true
    setupProcess.kind = "teardown"
    setupProcess.stdinEnabled = true
    setupProcess.payload = JSON.stringify({ confirm: "remove" })
    setupProcess.running = true
    return true
  }
  // Commands the user runs and confirms in a terminal (packages, updates).
  function runInTerminal(title, command) {
    Quickshell.execDetached(["/usr/bin/xdg-terminal-exec", "--title=" + title, "--hold", "--"]
      .concat(command))
    return true
  }
  function installWacli() {
    return runInTerminal("Install wacli", ["/usr/bin/omarchy", "pkg", "aur", "add", "wacli-bin"])
  }
  function installZenity() {
    return runInTerminal("Install zenity", ["/usr/bin/omarchy", "pkg", "add", "zenity"])
  }
  function removePlugin() {
    return runInTerminal("Remove WhatsApp for Omarchy",
      ["/usr/bin/omarchy", "plugin", "remove", root.pluginId])
  }
  function quitApp() {
    if (controlProcess.running || writing) return false
    return runControl("quit", ({}))
  }
  // The phone loses this linked device; the local archive stays. The helper
  // refuses unless the confirmation names the account.
  function unlinkAccount(name, confirm) {
    if (controlProcess.running || writing) return false
    return runControl("unlink-account", { name: String(name || ""), confirm: String(confirm || "") })
  }
  // Opening a closed WhatsApp for Omarchy starts its sync again.
  function launchApp() {
    if (controlProcess.running) return false
    return runControl("launch", ({}))
  }
  function runControl(kind, payload) {
    controlWriting = true
    controlProcess.kind = kind
    controlProcess.account = root.selectedChatAccount
    controlProcess.payload = JSON.stringify(payload || ({}))
    controlProcess.command = [helper, kind]
    controlProcess.stdinEnabled = true
    controlProcess.running = true
    return true
  }
  // Each account has its own sync; without one named, the open chat's.
  function setOnline(online, account) {
    if (controlProcess.running || writing) return false
    controlWriting = true
    controlProcess.kind = "sync-mode"
    controlProcess.account = account === undefined || account === null
      ? root.selectedChatAccount : String(account)
    controlProcess.payload = JSON.stringify({
      account: controlProcess.account, online: online === true
    })
    controlProcess.command = [helper, "sync-mode"]
    controlProcess.stdinEnabled = true
    controlProcess.running = true
    return true
  }
  function applyInterfacePreferences(payload) {
    if (payload.auto_download_media !== undefined)
      root.autoDownloadMedia = payload.auto_download_media !== false
    root.readOnReply = payload.read_on_reply !== false
    root.showOnline = payload.show_online !== false
    root.notifyReply = payload.notify_reply !== false
    root.enterSends = payload.enter_sends !== false
    root.showAvatars = payload.show_avatars !== false
    root.autoRefreshAvatars = payload.auto_refresh_avatars !== false
    root.railDensity = payload.rail_density === "compact" ? "compact" : "comfortable"
    root.railWidth = Math.max(0, Math.min(640, Number(payload.rail_width || 0)))
  }

  // Replying shows you read the chat, so it clears the unread count the way
  // the phone does. wacli's mark-read only syncs the read state to your own
  // devices; it never sends the other side a read receipt.
  readonly property var replyKinds: ["send", "files", "voice", "sticker", "poll"]
  function markReadAfterReply(chatRef) {
    if (!root.readOnReply || root.offlineMode) return false
    var target = AccountModel.chatRef(String(chatRef && chatRef.account || ""),
      String(chatRef && chatRef.jid || ""))
    if (String(target.jid || "") === "") return false
    var chat = null
    for (var i = 0; i < root.chats.length; i++) {
      if (root.sameChat(root.chats[i], target.account, target.jid)) { chat = root.chats[i]; break }
    }
    if (!chat || Number(chat.unread || 0) <= 0) return false
    root.lastChatsRaw = ""
    root.chats = root.chats.map(function(item) {
      if (!root.sameChat(item, target.account, target.jid)) return item
      var next = Object.assign({}, item)
      next.unread = 0
      next.notification_unread = 0
      return next
    })
    root.pendingReplyReadRef = target
    replyReadRetry.attempts = 0
    replyReadRetry.restart()
    return true
  }

  Timer {
    id: replyReadRetry
    // The mark has its own process, so a send in flight does not hold it; a
    // mark that keeps being refused (offline, account unavailable) is dropped
    // after a few seconds.
    property int attempts: 0
    interval: 150
    repeat: false
    onTriggered: {
      var target = root.pendingReplyReadRef
      if (String(target.jid || "") === "") return
      attempts += 1
      if (root.chatAction(target, "read")) {
        root.pendingReplyReadRef = AccountModel.chatRef("", "")
        return
      }
      if (attempts < 40) restart()
      else root.pendingReplyReadRef = AccountModel.chatRef("", "")
    }
  }

  function setPreference(key, value, account) {
    if (settingsProcess.running) return false
    var settings = ({})
    settings[String(key || "")] = value
    settingsWriting = true
    settingsProcess.account = account === undefined || account === null
      ? root.selectedChatAccount : String(account)
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

    function openDropdown(payload: string): string {
      var data = {}
      try { data = JSON.parse(payload || "{}") } catch (e) {}
      root.openDropdownRequested(data)
      return "ok"
    }

    function toggleDropdown(payload: string): string {
      var data = {}
      try { data = JSON.parse(payload || "{}") } catch (e) {}
      root.toggleDropdownRequested(data)
      return "ok"
    }
  }

  // One watcher per account store; they share the debounce below. SQLite can
  // open WAL sidecars writable even for read-only queries, so CLOSE_WRITE does
  // not mean chat data changed. Keep writes, checkpoints, replacement and removal
  // events; a read completing must not schedule another read of itself.
  Instantiator {
    id: storeWatchers
    model: root.storeDirectories
    delegate: Process {
      id: storeWatcher
      required property string modelData
      running: true
      command: [
        "setpriv", "--pdeathsig", "TERM",
        "inotifywait", "-m", "-q",
        "-e", "create,delete,move,modify",
        "--format", "%f", modelData
      ]
      stdout: SplitParser {
        splitMarker: "\n"
        onRead: function(fileName) {
          var name = String(fileName || "").trim()
          if (name === "wacli.db" || name === "wacli.db-wal")
            root.refreshFromStore()
          // Presence changes alone never reload chats or messages.
          else if (name === "presence.json")
            root.reloadPresence(storeWatcher.modelData)
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

  // A message landing in the mirror pops its notification now, not at the
  // next 12-second tick; the short wait folds a burst into one popup per chat.
  Timer {
    id: notifyDebounce
    interval: 900
    repeat: false
    onTriggered: root.runNotify()
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
        if (root.chatDetailsWanted) root.refreshChatDetails()
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
      root.prunePendingSends()
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
    objectName: "statusProcess"
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
      root.noteHelperRefusal(statusError.text)
      if (payload && payload.setup) root.acceptSetupState(payload.setup)
      if (!payload || payload.ok !== true) {
        // wacli missing or too old: onboarding says how to install it.
        root.wacliInstalled = !(payload && payload.installed === false)
        root.wacliTooOld = !!payload && payload.wacli_too_old === true
        root.wacliVersion = payload && payload.wacli_version ? String(payload.wacli_version) : ""
        if (applies) {
          root.statusReady = false
          root.ready = false
          root.railReady = false
          root.errorText = root.helperOutdated ? root.helperOutdatedText
            : (payload && payload.error)
            || root.helperErrorText(statusError.text, "WhatsApp for Omarchy could not connect.")
        }
      } else if (applies) {
        root.helperAnswered = true
        root.helperVersion = String(payload.helper_version || "")
        var readiness = AccountModel.statusReadiness(payload)
        root.statusAccount = responseAccount
        root.statusReady = true
        root.authenticated = readiness.authenticated
        root.railReady = readiness.railReady
        root.syncActive = payload.sync_active === true
        root.wacliInstalled = true
        root.wacliTooOld = false
        root.wacliVersion = String(payload.wacli_version || "")
        root.anyAuthenticated = payload.any_authenticated === true
        root.defaultAccountName = String((Array.isArray(payload.accounts)
          ? (payload.accounts.filter(function(item) { return item && item["default"] === true })[0] || {})
          : {}).account || "primary")
        root.closed = payload.closed === true
        root.startAtLogin = payload.start_at_login !== false
        root.offlineMode = payload.offline_mode === true
        var notifications = payload.notifications
        // A status read that started before a mute toggle must not undo it.
        if (!root.notificationToggleInFlight)
          root.notificationsEnabled = !!notifications && notifications.enabled === true
        root.notificationsPreview = !notifications || notifications.preview !== false
        root.notificationsSound = !notifications || notifications.sound !== false
        root.notifyAvailable = payload.notify_available !== false
        root.accounts = Array.isArray(payload.accounts) ? payload.accounts : []
        root.sendReadReceipts = payload.send_read_receipts === true
        root.showUnreadCount = payload.show_unread_count !== false
        root.checkUpdatesOnLaunch = payload.check_updates_on_launch === true
        root.dropdownRows = [5, 7, 9].indexOf(Number(payload.dropdown_rows)) >= 0
          ? Number(payload.dropdown_rows) : 7
        root.composerMaxLines = [4, 6, 8, 10].indexOf(Number(payload.composer_max_lines)) >= 0
          ? Number(payload.composer_max_lines) : 6
        root.timeFormat = ["auto", "12h", "24h"].indexOf(payload.time_format) >= 0
          ? payload.time_format : "auto"
        root.applyInterfacePreferences(payload)
        root.ready = readiness.accountReady
        if (root.ready) root.errorText = root.helperOutdated ? root.helperOutdatedText : ""
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

  Process {
    id: setupProcess
    objectName: "setupProcess"
    property string kind: "setup"
    property string payload: ""
    command: [root.helper, kind]
    stdinEnabled: true
    stdout: StdioCollector { id: setupOutput }
    stderr: StdioCollector { id: setupError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.setupWriting = false
      var result = root.parseJson(setupOutput.text)
      if (exitCode !== 0 || !result || result.ok !== true) {
        root.errorText = (result && result.error)
          || root.helperErrorText(setupError.text, "WhatsApp for Omarchy could not finish setting up.")
        root.refreshStatus()
        return
      }
      if (kind === "teardown") root.lastTeardown = result
      if (result.setup) root.setupState = result.setup
      root.errorText = ""
      root.setupCompleted(kind)
      root.refreshStatus()
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
    objectName: "chatsProcess"
    property string payload: ""
    command: [root.helper, "chats", "--limit", "500"]
    stdinEnabled: true
    stdout: StdioCollector { id: chatsOutput }
    stderr: StdioCollector { id: chatsError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.loadingChats = false
      if (root.storeRefreshPending) storeRefreshDebounce.restart()
      // Most mirror changes leave the rail as it was; an identical answer
      // keeps the current model, so the list is not rebuilt for nothing.
      var raw = String(chatsOutput.text || "")
      if (raw !== "" && raw === root.lastChatsRaw && exitCode === 0) return
      var payload = root.parseJson(raw)
      if (!payload || payload.ok !== true) {
        root.errorText = (payload && payload.error) || root.helperErrorText(chatsError.text, "Chats could not be read.")
        return
      }
      root.lastChatsRaw = raw
      root.chats = Array.isArray(payload.chats) ? payload.chats : []
      if (root.chats.length === 0) {
        root.selectedChatJid = ""
        root.selectedChatAccount = ""
        root.selectedChatName = ""
        root.selectedChatKind = "unknown"
        root.query = ""
        root.messages = []
        root.lastMessagesRaw = ""
        root.members = []
        return
      }
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
        root.lastMessagesRaw = ""
        root.members = []
        if (root.conversationOnScreen)
          root.dismissNotifications(root.selectedChatJid, root.selectedChatAccount)
      }
      root.selectedChatName = String(selected.name || "WhatsApp chat")
      root.selectedChatKind = String(selected.kind || "unknown")
      root.readOpenChatIfUnread(selected)
      if (root.messages.length === 0) root.refreshMessages()
      if (root.selectedChatKind === "group" && root.members.length === 0) root.refreshMembers()
    }
  }

  Process {
    id: controlProcess
    objectName: "controlProcess"
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
          || root.helperErrorText(controlError.text, "WhatsApp for Omarchy could not change that setting.")
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
      if (finishedKind === "sync-mode") {
        var syncedAccount = String(payload.account || account || "")
        root.accounts = root.accounts.map(function(item) {
          return item && String(item.account || "") === syncedAccount
            ? Object.assign({}, item, { online: payload.online === true,
                offline_mode: payload.online !== true, sync_active: payload.online === true })
            : item
        })
      }
      if (finishedKind === "quit" || finishedKind === "launch") {
        root.closed = payload.closed === true
        root.syncActive = finishedKind === "launch" && !root.offlineMode
      }
      if (finishedKind === "media-mode")
        root.autoDownloadMedia = payload.auto_download_media !== false
      if (finishedKind === "notify-mode" && payload.notifications) {
        root.notificationsEnabled = payload.notifications.enabled === true
        root.notificationsPreview = payload.notifications.preview !== false
        root.notificationsSound = payload.notifications.sound !== false
      }
      if (finishedKind !== "sync-mode" || accountIsCurrent)
        root.controlCompleted(finishedKind)
      root.refreshStatus()
      root.refreshChats()
    }
  }

  Process {
    id: mediaBrowserProcess
    objectName: "mediaBrowserProcess"
    property string payload: ""
    property string kind: ""
    property var chatRef: ({ account: "", jid: "", key: "" })
    command: [root.helper, "messages", "--limit", "300"]
    stdinEnabled: true
    stdout: StdioCollector { id: mediaBrowserOutput }
    stderr: StdioCollector { }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.browserLoading = false
      var payload = root.parseJson(mediaBrowserOutput.text)
      if (exitCode === 0 && payload && payload.ok === true
          && AccountModel.sameRef(chatRef, root.selectedChatRef()) && kind === root.browserKind)
        root.browserItems = Array.isArray(payload.messages) ? payload.messages : []
      if (root.browserPendingKind !== "") {
        var next = root.browserPendingKind
        root.browserPendingKind = ""
        Qt.callLater(function() { root.browseMedia(next) })
      }
    }
  }

  Process {
    id: groupInfoProcess
    objectName: "groupInfoProcess"
    property string payload: ""
    property var chatRef: ({ account: "", jid: "", key: "" })
    command: [root.helper, "group-info"]
    stdinEnabled: true
    stdout: StdioCollector { id: groupInfoOutput }
    stderr: StdioCollector { id: groupInfoError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.groupSettingsLoading = false
      var payload = root.parseJson(groupInfoOutput.text)
      if (!AccountModel.sameRef(chatRef, root.selectedChatRef())) return
      if (exitCode === 0 && payload && payload.ok === true) root.groupSettings = payload
      else root.groupSettingsError = (payload && payload.error)
        || root.helperErrorText(groupInfoError.text, "WhatsApp could not read the group settings.")
    }
  }

  Process {
    id: stickersProcess
    objectName: "stickersProcess"
    property string payload: ""
    command: [root.helper, "stickers"]
    stdinEnabled: true
    stdout: StdioCollector { id: stickersOutput }
    stderr: StdioCollector { }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.stickersLoading = false
      var payload = root.parseJson(stickersOutput.text)
      if (exitCode === 0 && payload && payload.ok === true)
        root.stickers = (Array.isArray(payload.stickers) ? payload.stickers : [])
          .filter(function(item) { return String(item.path || "") !== "" })
    }
  }

  Process {
    id: olderProcess
    objectName: "olderProcess"
    property string payload: ""
    property var chatRef: ({ account: "", jid: "", key: "" })
    command: [root.helper, "messages", "--limit", "200"]
    stdinEnabled: true
    stdout: StdioCollector { id: olderOutput }
    stderr: StdioCollector { }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.loadingOlder = false
      var payload = root.parseJson(olderOutput.text)
      if (exitCode !== 0 || !payload || payload.ok !== true
          || !AccountModel.sameRef(chatRef, root.selectedChatRef())) return
      var known = {}
      root.olderMessages.forEach(function(item) { known[String(item.id || "")] = true })
      var page = (Array.isArray(payload.messages) ? payload.messages : [])
        .filter(function(item) { return !known[String(item.id || "")] })
      root.olderMessages = root.olderMessages.concat(page)
      root.hasOlderMessages = payload.has_more === true && page.length > 0
    }
  }

  Process {
    id: chatDetailsProcess
    objectName: "chatDetailsProcess"
    property string payload: ""
    property var chatRef: ({ account: "", jid: "", key: "" })
    command: [root.helper, "chat-details"]
    stdinEnabled: true
    stdout: StdioCollector { id: chatDetailsOutput }
    stderr: StdioCollector { }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.chatDetailsLoading = false
      var payload = root.parseJson(chatDetailsOutput.text)
      if (exitCode === 0 && payload && payload.ok === true
          && AccountModel.sameRef(chatRef, root.selectedChatRef()))
        root.chatDetails = payload
      if (root.chatDetailsPending) {
        root.chatDetailsPending = false
        Qt.callLater(root.refreshChatDetails)
      }
    }
  }

  Process {
    id: contactsProcess
    objectName: "contactsProcess"
    property string account: ""
    property string query: ""
    property string payload: ""
    command: [root.helper, "contacts-search"]
    stdinEnabled: true
    stdout: StdioCollector { id: contactsOutput }
    stderr: StdioCollector { id: contactsError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      root.newChatPeopleLoading = false
      var payload = root.parseJson(contactsOutput.text)
      if (exitCode === 0 && payload && payload.ok === true && account === root.statusAccount
          && query === root.newChatPeopleQuery)
        root.newChatPeople = Array.isArray(payload.people) ? payload.people : []
      if (root.newChatPeoplePending || query !== root.newChatPeopleQuery) {
        root.newChatPeoplePending = false
        Qt.callLater(function() { root.searchPeople(root.newChatPeopleQuery) })
      }
    }
  }

  Process {
    id: checkNumberProcess
    objectName: "checkNumberProcess"
    property string account: ""
    property string phone: ""
    property string payload: ""
    command: [root.helper, "check-number"]
    stdinEnabled: true
    stdout: StdioCollector { id: checkNumberOutput }
    stderr: StdioCollector { id: checkNumberError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var payload = root.parseJson(checkNumberOutput.text)
      var result = { account: account, phone: phone, loading: false, registered: false,
        responded: false, jid: "", has_chat: false, name: "", error: "" }
      if (exitCode === 0 && payload && payload.ok === true) {
        result.responded = true
        result.registered = payload.registered === true
        result.jid = String(payload.jid || "")
        result.has_chat = payload.has_chat === true
        result.name = String(payload.name || "")
      } else {
        result.error = (payload && payload.error)
          || root.helperErrorText(checkNumberError.text, "WhatsApp could not check that number.")
      }
      root.numberCheck = result
    }
  }

  Process {
    id: contactProfileProcess
    objectName: "contactProfileProcess"
    property string person: ""
    property string payload: ""
    command: [root.helper, "contact-profile"]
    stdinEnabled: true
    stdout: StdioCollector { id: contactProfileOutput }
    stderr: StdioCollector { id: contactProfileError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var result = root.parseJson(contactProfileOutput.text)
      if (exitCode === 0 && result && result.ok === true)
        root.contactProfile = { jid: person, loading: false, about: String(result.about || ""),
          business: result.business || ({}), error: "" }
      else
        root.contactProfile = { jid: person, loading: false, about: "", business: ({}),
          error: (result && result.error)
            || root.helperErrorText(contactProfileError.text, "WhatsApp did not answer.") }
    }
  }

  Process {
    id: groupRequestProcess
    objectName: "groupRequestProcess"
    property string kind: ""
    property string payload: ""
    command: [root.helper, "create-group"]
    stdinEnabled: true
    stdout: StdioCollector { id: groupRequestOutput }
    stderr: StdioCollector { id: groupRequestError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var result = root.parseJson(groupRequestOutput.text)
      if (exitCode === 0 && result && result.ok === true) {
        root.groupRequest = { kind: kind, loading: false, jid: String(result.jid || ""), error: "" }
        root.lastChatsRaw = ""
        root.refreshChats()
      } else {
        root.groupRequest = { kind: kind, loading: false, jid: "",
          error: (result && result.error)
            || root.helperErrorText(groupRequestError.text, "WhatsApp could not do that.") }
      }
    }
  }

  Process {
    id: aboutProcess
    command: [root.helper, "about"]
    stdinEnabled: true
    stdout: StdioCollector { id: aboutOutput }
    stderr: StdioCollector { id: aboutError }
    onStarted: { write("{}\n"); stdinEnabled = false }
    onExited: function(exitCode) {
      root.aboutLoading = false
      stdinEnabled = true
      var payload = root.parseJson(aboutOutput.text)
      if (exitCode === 0 && payload && payload.ok === true) root.about = payload
    }
  }

  Process {
    id: settingsProcess
    objectName: "settingsProcess"
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
          || root.helperErrorText(settingsError.text, "WhatsApp for Omarchy settings could not be saved.")
        root.errorText = message
        root.settingsFailed(message)
        root.refreshStatus()
        return
      }
      // Receipt preference is account-scoped; badge visibility and dropdown
      // density are one global UI preference shared by every account.
      if (account === String(root.selectedChatAccount || ""))
        root.sendReadReceipts = payload.send_read_receipts === true
      // The composer shows the new signature, and Settings the account's
      // notifications, at once, before the next status.
      var savedAccount = String(payload.account || account || "")
      root.accounts = root.accounts.map(function(item) {
        if (!item || String(item.account || "") !== savedAccount) return item
        var next = Object.assign({}, item)
        if (payload.signature && typeof payload.signature === "object") next.signature = payload.signature
        if (payload.account_notifications !== undefined)
          next.notifications_muted = payload.account_notifications === false
        return next
      })
      root.showUnreadCount = payload.show_unread_count !== false
      root.checkUpdatesOnLaunch = payload.check_updates_on_launch === true
      root.startAtLogin = payload.start_at_login !== false
      root.dropdownRows = [5, 7, 9].indexOf(Number(payload.dropdown_rows)) >= 0
        ? Number(payload.dropdown_rows) : 7
      root.composerMaxLines = [4, 6, 8, 10].indexOf(Number(payload.composer_max_lines)) >= 0
        ? Number(payload.composer_max_lines) : 6
      root.timeFormat = ["auto", "12h", "24h"].indexOf(payload.time_format) >= 0
        ? payload.time_format : "auto"
      root.applyInterfacePreferences(payload)
      root.errorText = ""
      root.settingsCompleted()
      root.refreshStatus()
    }
  }

  Process {
    id: notifyProcess
    objectName: "notifyProcess"
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
      if (root.notifyPending) notifyDebounce.restart()
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
        root.errorText = (payload && payload.error) || root.helperErrorText(messagesError.text, "Messages could not be read.")
      } else if (payload && payload.ok === true && responseIsCurrent) {
        var key = chatRef.key + "\n" + requestedQuery
        var rawMessages = String(messagesOutput.text || "")
        if (key === root.lastMessagesKey && rawMessages === root.lastMessagesRaw) {
          if (root.messagesPending) { root.messagesPending = false; Qt.callLater(root.refreshMessages) }
          return
        }
        root.lastMessagesKey = key
        root.lastMessagesRaw = rawMessages
        root.messages = Array.isArray(payload.messages) ? payload.messages : []
        if (root.olderMessages.length === 0) root.hasOlderMessages = payload.has_more !== false
        root.prunePendingSends()
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
          || root.helperErrorText(membersError.text, "Group members could not be read.")
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
    id: pasteProcess
    objectName: "pasteProcess"
    property string payload: ""
    property var chatRef: AccountModel.chatRef("", "")
    property string owner: "service"
    command: [root.helper, "paste"]
    stdinEnabled: true
    stdout: StdioCollector { id: pasteOutput }
    stderr: StdioCollector { id: pasteError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var result = root.parseJson(pasteOutput.text)
      if (exitCode === 0 && result && result.ok === true && result.kind === "text") {
        root.textPasted(String(result.text || ""), chatRef, owner)
        return
      }
      if (exitCode === 0 && result && result.ok === true
          && (result.kind === "file" || result.kind === "image")) {
        root.attachmentPasted(String(result.path || ""), chatRef, owner)
        return
      }
      root.pasteFailed((result && result.error)
        || root.helperErrorText(pasteError.text, "The clipboard could not be read."), chatRef, owner)
    }
  }

  Timer {
    id: readMarkRetry
    interval: 400
    repeat: false
    onTriggered: root.runNextReadMark()
  }

  Process {
    id: readMarkProcess
    objectName: "readMarkProcess"
    property string payload: ""
    command: [root.helper, "chat-action"]
    stdinEnabled: true
    stdout: StdioCollector { id: readMarkOutput }
    stderr: StdioCollector { id: readMarkError }
    onStarted: { write(payload + "\n"); payload = ""; stdinEnabled = false }
    onExited: function(exitCode) {
      var finished = root.activeReadMark
      root.activeReadMark = null
      var result = root.parseJson(readMarkOutput.text)
      if (finished && (exitCode !== 0 || !result || result.ok !== true)) {
        var message = (result && result.error)
          || root.helperErrorText(readMarkError.text, "WhatsApp could not change the read state.")
        root.chatStateFailed(message, finished.ref, finished.action, finished.owner)
        // Back to what the mirror says.
        root.lastChatsRaw = ""
        refreshDelay.restart()
      } else if (finished) {
        refreshDelay.restart()
      }
      Qt.callLater(root.runNextReadMark)
    }
  }

  Process {
    id: writeProcess
    objectName: "writeProcess"
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
        var message = (payload && payload.error) || root.helperErrorText(writeError.text, "WhatsApp could not complete that request.")
        if (AccountModel.sameRef(finishedChat, root.selectedChatRef()))
          root.errorText = message
        if (finishedKind === "media") root.mediaDownloadId = ""
        if (finishedKind === "voice")
          voiceRecorder.markSendFailed(message, finishedAccount, finishedJid)
        if (finishedKind === "voice") root.voiceOwner = "service"
        if (finishedKind === "files" || finishedKind === "sticker")
          root.dropPendingSend(finishedRequest.local_id)
        if (finishedKind === "send")
          root.updatePendingSend(finishedRequest.local_id, { state: "failed", error: message })
        if (finishedKind === "chat-action") {
          root.lastChatsRaw = ""
          refreshDelay.restart()
        }
        var details = Object.assign({},
          payload && payload.partial ? payload.partial : ({}))
        details.kind = finishedKind
        details.request = finishedRequest
        // The failed text stays on screen as a bubble to retry, so surfaces
        // must not also put it back into the composer.
        if (finishedKind === "send") details.pending_kept = true
        if (finishedKind === "star") {
          root.setStarOverride(finishedChat, finishedRequest.id, null)
          if (String(message).indexOf("cannot star") >= 0) {
            root.starSupported = false
            root.batchJobs.forEach(function(job) {
              if (job.kind === "star") root.setStarOverride(root.writeBatch ? root.writeBatch.origin : finishedChat,
                job.item.id, null)
            })
            root.batchJobs = root.batchJobs.filter(function(job) { return job.kind !== "star" })
          }
        }
        if (["forward", "delete", "send-new", "star"].indexOf(finishedKind) >= 0 && finishedRequest.batch === true)
          root.finishBatchJob(false, message)
        root.writeFailed(message, finishedChat, details, finishedOwner)
        root.runNextQueuedSend()
        root.runNextBatchJob()
        return
      }
      if (AccountModel.sameRef(finishedChat, root.selectedChatRef()))
        root.errorText = ""
      if (finishedKind === "media") root.mediaDownloadId = ""
      if (finishedKind === "voice") {
        voiceRecorder.markSent(finishedAccount, finishedJid)
        root.voiceOwner = "service"
      }
      if (finishedKind === "send-new")
        root.lastStartedChatJid = String(payload.chat_jid || finishedJid)
      if (finishedKind === "files")
        root.updatePendingSend(finishedRequest.local_id, { state: "sent", created: Date.now() })
      if (finishedKind === "group-action") {
        root.lastGroupResult = payload
        // Settings the owner just changed are shown as changed at once.
        var changed = ({ announce: "announce_only", locked: "locked", rename: "name", description: "description" })[
          String(finishedRequest.action || "")]
        if (changed && root.groupSettings && root.groupSettings.ok) {
          var next = Object.assign({}, root.groupSettings)
          next[changed] = finishedRequest.value
          root.groupSettings = next
        }
        if (root.chatDetailsWanted) Qt.callLater(root.refreshChatDetails)
      }
      if (finishedKind === "send" || finishedKind === "sticker")
        root.updatePendingSend(finishedRequest.local_id, {
          state: "sent", message_id: String(payload.message_id || ""), created: Date.now() })
      if (["contact-alias", "contact-tag", "download-pending"].indexOf(finishedKind) >= 0
          && root.chatDetailsWanted) Qt.callLater(root.refreshChatDetails)
      if (["forward", "delete", "send-new", "star"].indexOf(finishedKind) >= 0 && finishedRequest.batch === true)
        root.finishBatchJob(true, "")
      // What the helper answered, for surfaces that report it (exports, downloads).
      root.lastWriteResult = payload
      root.writeCompleted(finishedKind, finishedChat, finishedRequest, finishedOwner)
      // Queued texts go before anything a handler above started later.
      root.runNextQueuedSend()
      root.runNextBatchJob()
      if (root.replyKinds.indexOf(finishedKind) >= 0) root.markReadAfterReply(finishedChat)
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
