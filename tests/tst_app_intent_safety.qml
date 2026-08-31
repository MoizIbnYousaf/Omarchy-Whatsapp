import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma
import "../plugins/omawhatsapp/AccountModel.js" as AccountModel

TestCase {
  id: testCase
  name: "AppIntentSafety"

  readonly property var workChat: ({
    account: "work", jid: "shared@example", name: "Synthetic work",
    kind: "dm", preview: "", unread: 0
  })
  readonly property var homeChat: ({
    account: "home", jid: "shared@example", name: "Synthetic home",
    kind: "dm", preview: "", unread: 0
  })
  readonly property var workTarget: ({
    account: "work", jid: "target@example", name: "Synthetic target",
    kind: "dm", preview: "", unread: 0
  })
  readonly property var homeTarget: ({
    account: "home", jid: "target@example", name: "Synthetic target home",
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
      property var accounts: []
      property var messages: []
      property var members: []
      property var accountOperations: ({
        linkBusy: false, avatarBusy: false, statusMessage: ""
      })
      property var lastDelete: null
      property var lastForward: null
      property var lastPoll: null
      property var discarded: []

      Oma.PlaybackCoordinator { id: playbackCoordinator }

      signal textPasted(string text, var chatRef, string owner)
      signal attachmentPasted(string path, var chatRef, string owner)
      signal writeCompleted(string kind, var chatRef, var request, string owner)
      signal writeFailed(string message, var chatRef, var details, string owner)
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
      function pasteClipboard() { return false }
      function sendFilesReply() { return false }
      function sendSticker() { return false }
      function sendText() { return false }
      function editMessage() { return false }
      function search() {}
      function closeApp() {}
      function selectItem() {}
      function chatAction() { return false }
      function downloadMedia() { return false }
      function reactTo() { return false }
      function selectOption() { return false }
      function setNotifications() { return false }
      function setOnline() { return false }
      function setPreference() { return false }
    }
  }

  Component {
    id: appComponent
    Oma.App { width: 1000; height: 700 }
  }

  function createHarness() {
    var service = createTemporaryObject(serviceComponent, testCase)
    verify(service !== null)
    service.chats = [workChat, homeChat, workTarget, homeTarget]
    var app = createTemporaryObject(appComponent, testCase, { service: service })
    verify(app !== null)
    app.composerChatKey = AccountModel.refOf(homeChat).key
    return { app: app, service: service }
  }

  function test_picker_result_is_saved_to_the_captured_account_not_same_jid_selection() {
    var harness = createHarness()
    var app = harness.app
    var service = harness.service
    service.selectChat(homeChat)
    app.pendingAttachments = []
    app.composerStates = ({})

    verify(app.acceptFilePickerResult(AccountModel.refOf(workChat),
      ["file:///tmp/synthetic-document.pdf"], "document"))
    compare(app.pendingAttachments, [])
    compare(app.composerStates[AccountModel.refOf(workChat).key].attachments,
            ["file:///tmp/synthetic-document.pdf"])
    verify(app.composerStates[AccountModel.refOf(homeChat).key] === undefined)
  }

  function test_picker_result_survives_the_deferred_selection_sync_gap() {
    var harness = createHarness()
    var app = harness.app
    var service = harness.service
    var workKey = AccountModel.refOf(workChat).key
    var homeKey = AccountModel.refOf(homeChat).key
    service.selectChat(workChat)
    app.composerChatKey = workKey
    app.pendingAttachments = []
    app.composerStates = ({})

    // The shared Service moves first; App's mounted composer still belongs to
    // work until its queued sync callback runs.
    service.selectChat(homeChat)
    verify(app.acceptFilePickerResult(AccountModel.refOf(workChat),
      ["file:///tmp/synthetic-race.pdf"], "document"))
    compare(app.pendingAttachments, ["file:///tmp/synthetic-race.pdf"])

    wait(0)
    compare(app.composerChatKey, homeKey)
    compare(app.pendingAttachments, [])
    compare(app.composerStates[workKey].attachments,
            ["file:///tmp/synthetic-race.pdf"])
  }

  function test_modal_actions_keep_their_exact_origin_after_selection_changes() {
    var harness = createHarness()
    var app = harness.app
    var service = harness.service
    var message = { id: "synthetic-message" }
    var origin = AccountModel.refOf(workChat)

    service.selectChat(workChat)
    app.requestDelete(message, true)
    verify(AccountModel.sameRef(app.deleteOriginRef, origin))
    service.selectChat(homeChat)
    verify(app.confirmDelete())
    compare(service.lastDelete.ref.account, "work")
    compare(service.lastDelete.ref.jid, "shared@example")

    service.selectChat(workChat)
    app.startForward(message)
    verify(AccountModel.sameRef(app.forwardOriginRef, origin))
    service.selectChat(homeChat)
    compare(app.forwardCandidates.length, 1)
    compare(app.forwardCandidates[0].account, "work")
    verify(app.forwardTo(workTarget))
    compare(service.lastForward.ref.account, "work")
    compare(service.lastForward.targetJid, "target@example")

    service.selectChat(workChat)
    app.startPoll()
    verify(AccountModel.sameRef(app.pollOriginRef, origin))
    service.selectChat(homeChat)
    verify(app.submitPoll("Synthetic question?", ["First", "Second"], false))
    compare(service.lastPoll.ref.account, "work")
    compare(service.lastPoll.ref.jid, "shared@example")
    compare(service.lastPoll.selectable, 1)
  }
}
