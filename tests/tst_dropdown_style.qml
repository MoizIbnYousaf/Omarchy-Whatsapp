import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// The bar dropdown of the approved restyle: a compact list with the time on
// every row and quick actions on hover, a "3 new" divider, and a composer
// that says what its keys do.
TestCase {
  id: testCase
  name: "DropdownStyle"
  width: 520
  height: 760
  visible: true
  when: windowShown

  Component { id: dropdownComponent; Oma.Dropdown { demoMode: true } }
  property var panelItem: null

  // The test panel has no size of its own; give it the one it asks for.
  function openDropdown() {
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    var item = findChild(dropdown, "dropdownKeys")
    while (item && item.contentWidth === undefined) item = item.parent
    verify(item !== null, "the panel")
    // The dropdown itself is not an item; put its panel in this window.
    item.parent = testCase
    item.width = Qt.binding(function() { return item.contentWidth })
    item.height = Qt.binding(function() { return item.contentHeight })
    panelItem = item
    return dropdown
  }

  function rows(dropdown) {
    var found = []
    function walk(item) {
      if (item.objectName === "dropdownChatRow") found.push(item)
      for (var i = 0; i < item.children.length; i++) walk(item.children[i])
    }
    tryVerify(function() { found = []; walk(panelItem); return found.length === 3 }, 3000)
    found.sort(function(a, b) { return a.index - b.index })
    return found
  }

  function test_the_header_counts_unread_and_clears_on_request() {
    var dropdown = openDropdown()
    var badge = findChild(dropdown, "notificationBadge")
    verify(badge.visible)
    compare(findChild(dropdown, "dropdownUnreadCount").text, "2 unread")
    var clear = findChild(dropdown, "dropdownClearBadges")
    verify(clear.visible, "there is something to clear")
    verify(dropdown.requestClearNotifications())
    verify(dropdown.clearConfirmOpen, "clearing still asks first")
  }

  function test_rows_show_time_kind_and_badge() {
    var dropdown = openDropdown()
    var list = rows(dropdown)
    var first = list[0]
    verify(findChild(first, "dropdownChatTime").text !== "")
    compare(findChild(first, "dropdownChatName").font.weight, Font.Bold, "unread: bold")
    compare(String(findChild(first, "dropdownChatTime").color), String(dropdown.accent))
    verify(findChild(first, "dropdownChatBadge").visible)
    compare(findChild(list[2], "dropdownChatName").font.weight, Font.Medium, "read: regular")
    verify(!findChild(list[2], "dropdownChatBadge").visible)
    var avatar = findChild(first, "chatAvatarBackdrop")
    verify(avatar.width <= 34, "a small avatar")
  }

  function test_hover_offers_mark_read_and_reply_here() {
    var dropdown = openDropdown()
    var first = rows(dropdown)[0]
    var toggle = findChild(first, "dropdownChatReadToggle")
    var reply = findChild(first, "dropdownChatReply")
    verify(!toggle.visible && !reply.visible, "hidden until hovered")
    // The rows sit below the header once the column has laid out.
    tryVerify(function() { return first.mapToItem(null, 0, 0).y > 60 }, 2000)
    mouseMove(first, first.width / 2, first.height / 2)
    tryVerify(function() { return toggle.visible && reply.visible })
    verify(!findChild(first, "dropdownChatBadge").visible, "the actions take the badge's place")
    mouseClick(reply, reply.width / 2, reply.height / 2)
    compare(dropdown.viewMode, "conversation", "reply here opens the chat in place")
    dropdown.backToChats()
    toggle.clicked()
    compare(Number(dropdown.demoChats[0].unread), 0, "marked read")
  }

  function test_the_conversation_marks_new_messages_and_names_its_keys() {
    var dropdown = openDropdown()
    dropdown.openConversation(dropdown.demoChats[0])
    compare(dropdown.viewMode, "conversation")
    var hint = findChild(dropdown, "dropdownComposerHint")
    verify(hint.visible)
    verify(hint.text.indexOf("Enter sends") === 0)
    verify(hint.text.indexOf("Esc goes back") > 0)
  }

  function test_voice_notes_play_on_across_new_messages_and_in_sequence() {
    var dropdown = openDropdown()
    var voice = function(id, ts) {
      return { id: id, text: "", sender: "Alex", timestamp: ts, from_me: false, media_type: "audio",
        mime_type: "audio/ogg", local_path: "/nonexistent/omaw-" + id + ".ogg", reactions: [] }
    }
    dropdown.openDemo()
    dropdown.openConversation(dropdown.demoChats[0])
    verify(dropdown.opened)
    dropdown.demoItems = [voice("v2", 20), voice("v1", 10)]
    var audio = findChild(dropdown, "dropdownAudio")
    verify(dropdown.requestPlayback("v1"))
    compare(audio.currentId, "v1")
    dropdown.demoItems = [voice("v3", 30)].concat(dropdown.demoItems)
    compare(audio.currentId, "v1", "a new message does not stop it")
    verify(audio.finishCurrent())
    compare(audio.currentId, "v2", "the next voice note plays")
  }

  function test_the_dropdown_marks_unread_mentions_too() {
    var dropdown = openDropdown()
    dropdown.demoChats = dropdown.demoChats.map(function(chat, index) {
      return index === 0 ? Object.assign({}, chat, { mentioned: true }) : chat })
    var first = rows(dropdown)[0]
    verify(findChild(first, "dropdownMentionBadge").visible)
    verify(!findChild(rows(dropdown)[2], "dropdownMentionBadge").visible)
  }

  // L236: the dropdown marks each chat's account the way the list does.
  function test_each_account_marks_its_chats() {
    var dropdown = openDropdown()
    var list = rows(dropdown)
    var colors = {}
    for (var i = 0; i < list.length; i++) {
      var stripe = findChild(list[i], "dropdownAccountStripe")
      verify(stripe.visible, "demo mode links two accounts")
      colors[String(list[i].modelData.account)] = stripe.color
    }
    verify(colors.work !== undefined && colors.personal !== undefined)
    verify(!Qt.colorEqual(colors.work, colors.personal))
  }
}
