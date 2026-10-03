import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "DropdownNotifications"
  width: 700
  height: 800
  visible: true
  when: windowShown

  Component {
    id: serviceStub
    Item {
      property bool writing: true
      property string activeWriteOwner: "service"
      property var chats: []
      // Presence as a wacli without presence support reports it: nothing.
      property int presenceNow: 0
      function presenceSnapshotFor() { return null }
      function setPresenceFocus() {}
      property var messages: []
      property var accounts: []
      property string selectedChatJid: ""
      property string selectedChatAccount: ""
      property bool dropdownConversationVisible: false
      property bool dropdownOpen: false
      function selectChat(chat) {
        selectedChatJid = String(chat.jid)
        selectedChatAccount = String(chat.account || "")
      }
      function discardStages(paths) {}
      function stopVoiceForSurfaceClose() {}
      function refreshMessages() {}
      function refreshChats() {}
      property bool offlineMode: false
      property var sentTexts: []
      property int pastes: 0
      signal pasteFailed(string message, var chatRef, string owner)
      signal textPasted(string text, var chatRef, string owner)
      signal attachmentPasted(string path, var chatRef, string owner)
      // Like the real service: text queues even while another action runs.
      function sendText(ref, text) {
        sentTexts = sentTexts.concat([text])
        return true
      }
      function pasteClipboard(ref, owner) { pastes += 1; return true }
    }
  }

  Component {
    id: dropdownComponent
    Oma.Dropdown { demoMode: true }
  }

  function test_toggle_opens_closes_and_reopens() {
    // No service is attached: this never reads a private store or sends receipts.
    var dropdown = createTemporaryObject(dropdownComponent, testCase, { demoMode: false })
    verify(dropdown !== null)
    compare(dropdown.opened, false)
    dropdown.toggle()
    compare(dropdown.opened, true)
    dropdown.toggle()
    compare(dropdown.opened, false)
    dropdown.toggle()
    compare(dropdown.opened, true)
    dropdown.close()
  }

  function test_new_chat_hands_off_to_the_full_app_dialog() {
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    dropdown.toggle()
    var button = findChild(dropdown, "dropdownNewChatButton")
    verify(button !== null)
    compare(button.tooltipText, "New chat · opens the full app")
    var spy = createTemporaryObject(spyComponent, testCase,
      { target: dropdown, signalName: "fullAppRequested" })
    button.clicked()
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0].newChat, true)
    compare(dropdown.opened, false)
  }

  Component { id: spyComponent; SignalSpy {} }

  function test_clear_all_requires_confirmation_and_stays_local() {
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    verify(dropdown !== null)
    compare(dropdown.notificationCount, 2, "two unread chats, not four messages")

    verify(dropdown.requestClearNotifications())
    compare(dropdown.clearConfirmOpen, true)
    var confirmation = findChild(dropdown, "clearNotificationsConfirm")
    verify(confirmation !== null)
    verify(confirmation.handleKey({ key: Qt.Key_Escape }))
    compare(dropdown.clearConfirmOpen, false)
    compare(dropdown.notificationCount, 2)

    verify(dropdown.requestClearNotifications())
    verify(confirmation.handleKey({ key: Qt.Key_Return }))
    compare(dropdown.clearConfirmOpen, false)
    compare(dropdown.notificationCount, 0)
    compare(dropdown.requestClearNotifications(), false)
  }

  function test_the_count_filters_to_unread_chats() {
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    var all = dropdown.filteredChats.length
    verify(!dropdown.unreadOnly)
    var badge = findChild(dropdown, "notificationBadge")
    verify(badge !== null)
    verify(dropdown.badgeTapped(Qt.LeftButton))
    verify(dropdown.unreadOnly)
    verify(dropdown.filteredChats.length > 0)
    verify(dropdown.filteredChats.length < all)
    verify(dropdown.filteredChats.every(function(chat) { return Number(chat.unread || 0) > 0 }))
    dropdown.badgeTapped(Qt.LeftButton)
    verify(!dropdown.unreadOnly)
    dropdown.badgeTapped(Qt.RightButton)
    verify(dropdown.clearConfirmOpen, "right-click still clears the badge, with confirmation")
  }

  function test_background_writes_neither_show_sending_nor_block_going_back() {
    var service = createTemporaryObject(serviceStub, testCase)
    var dropdown = createTemporaryObject(dropdownComponent, testCase,
      { demoMode: false, service: service })
    verify(!dropdown.sending, "automatic mark-read is not this surface sending")
    dropdown.viewMode = "conversation"
    dropdown.backToChats()
    compare(dropdown.viewMode, "chats")
    service.activeWriteOwner = "dropdown"
    verify(dropdown.sending, "its own send still shows")
  }

  function test_only_the_conversation_view_counts_as_on_screen() {
    var service = createTemporaryObject(serviceStub, testCase)
    service.writing = false
    var dropdown = createTemporaryObject(dropdownComponent, testCase,
      { demoMode: false, service: service })
    dropdown.open()
    verify(dropdown.opened)
    compare(dropdown.viewMode, "chats")
    verify(!service.dropdownConversationVisible, "the chat list is not the conversation")
    dropdown.openConversation({ account: "work", jid: "x@s.whatsapp.net", name: "X" })
    compare(dropdown.viewMode, "conversation")
    verify(service.dropdownConversationVisible)
    dropdown.backToChats()
    verify(!service.dropdownConversationVisible)
    dropdown.close()
  }

  function test_footer_names_what_each_key_does() {
    // The owner found "O · J/K · / · Enter" cryptic (L82); the restyle keeps
    // the keys, each beside its action, and the full app gets a button.
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    var keys = findChild(dropdown, "dropdownKeys")
    verify(keys !== null)
    function words(item, found) {
      if (typeof item.text === "string" && item.text !== "") found.push(item.text)
      for (var i = 0; i < item.children.length; i++) words(item.children[i], found)
      return found
    }
    compare(words(keys, []).join(" "), "↑↓ move Enter reply O full app Esc close")
    verify(findChild(dropdown, "dropdownOpenFullButton") !== null, "the full app has its own button")
    function texts(item, found) {
      if (typeof item.text === "string") found.push(item.text)
      for (var i = 0; i < item.children.length; i++) texts(item.children[i], found)
      return found
    }
    verify(texts(dropdown, []).every(function(text) { return text.indexOf("J/K  ·") < 0 }),
      "no bare list of keys in the footer")
  }

  function test_a_reply_during_a_background_read_mark_goes_out_at_once() {
    // The same report as in the full app: a read mark in flight made the
    // reply do nothing at all, and each reply waited for the one before.
    var service = createTemporaryObject(serviceStub, testCase)
    var dropdown = createTemporaryObject(dropdownComponent, testCase,
      { demoMode: false, service: service })
    dropdown.open()
    dropdown.openConversation({ account: "work", jid: "x@s.whatsapp.net", name: "X" })
    var composer = findChild(dropdown, "composerInput")
    verify(composer !== null)
    verify(!composer.readOnly, "typing never waits for a WhatsApp action")
    composer.text = "on my way"
    dropdown.sendDraft()
    compare(service.sentTexts, ["on my way"], "handed to the send queue at once")
    verify(!dropdown.sendQueued)
    composer.text = "be there in 5"
    dropdown.sendDraft()
    compare(service.sentTexts, ["on my way", "be there in 5"])
    service.writing = true
    dropdown.pasteClipboard()
    compare(service.pastes, 1, "Ctrl+V runs beside the read mark")
    dropdown.close()
  }

  function test_a_clicked_notification_opens_its_chat_ready_for_a_reply() {
    // The owner's report: clicking a notification opened the full app with
    // no way to reply right there. It now opens this reply view on that chat.
    var service = createTemporaryObject(serviceStub, testCase)
    service.writing = false
    service.chats = [{ account: "work", jid: "x@s.whatsapp.net", name: "Known X", kind: "dm" }]
    var dropdown = createTemporaryObject(dropdownComponent, testCase,
      { demoMode: false, service: service })
    dropdown.open()
    verify(dropdown.openChatRef("work", "x@s.whatsapp.net"))
    compare(dropdown.viewMode, "conversation")
    compare(dropdown.currentChat.name, "Known X", "a known chat keeps its name")
    verify(dropdown.openChatRef("work", "new@s.whatsapp.net"))
    compare(dropdown.currentChat.jid, "new@s.whatsapp.net", "a chat not in the list still opens")
    verify(!dropdown.openChatRef("work", ""))
    dropdown.close()
  }

  function test_forwarding_from_the_dropdown_carries_on_in_the_full_app() {
    // The owner's report: forwarding here switched to the full app, where
    // the forward had to be started again.
    var service = createTemporaryObject(serviceStub, testCase)
    service.writing = false
    var dropdown = createTemporaryObject(dropdownComponent, testCase,
      { demoMode: false, service: service })
    dropdown.open()
    dropdown.openConversation({ account: "work", jid: "x@s.whatsapp.net", name: "X" })
    var spy = createTemporaryObject(spyComponent, testCase,
      { target: dropdown, signalName: "fullAppRequested" })
    verify(dropdown.forwardInFullApp({ id: "m1", text: "hello", media_type: "image" }))
    compare(spy.count, 1)
    var payload = spy.signalArguments[0][0]
    compare(payload.jid, "x@s.whatsapp.net")
    compare(payload.forward.id, "m1")
    compare(payload.forward.media_type, "image")
  }

  function test_the_dropdown_formats_and_hands_a_contact_to_the_full_app() {
    var service = createTemporaryObject(serviceStub, testCase)
    service.writing = false
    var dropdown = createTemporaryObject(dropdownComponent, testCase,
      { demoMode: false, service: service })
    dropdown.open()
    dropdown.openConversation({ account: "work", jid: "x@s.whatsapp.net", name: "X" })
    compare(findChild(dropdown, "composerFormatButton"), null)
    verify(findChild(dropdown, "formatBar") !== null, "a bar over selections instead")
    verify(findChild(dropdown, "formatMenu") !== null, "and the right-click menu")
    var composer = findChild(dropdown, "composerInput")
    composer.text = "quick note"
    composer.select(0, 5)
    verify(dropdown.applyFormat("strike"))
    compare(composer.text, "~quick~ note")
    dropdown.composerMenuAction("select-all")
    compare(composer.selectedText, "~quick~ note")
    var spy = createTemporaryObject(spyComponent, testCase,
      { target: dropdown, signalName: "fullAppRequested" })
    verify(dropdown.openContactChat({ name: "Nobody", digits: "15550009999", jid: "" },
      { id: "card", sender: "Sam", from_me: false }))
    compare(spy.count, 1)
    // The full app opens that person's draft chat over this one (L220).
    var handed = spy.signalArguments[0][0]
    compare(handed.jid, "x@s.whatsapp.net")
    compare(handed.contact.digits, "15550009999")
    compare(handed.contact.shared_by, "Sam")
  }
}
