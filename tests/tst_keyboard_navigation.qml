import QtQml
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "KeyboardNavigation"

  Component {
    id: navigationComponent
    Oma.KeyboardNavigation {}
  }

  function test_escape_walks_out_one_layer_at_a_time() {
    var navigation = createTemporaryObject(navigationComponent, testCase)
    verify(navigation !== null)

    navigation.enterComposer()
    compare(navigation.backTarget(), "messages")
    navigation.enterMessages(4)
    compare(navigation.backTarget(), "chats")
    navigation.enterChats(4, 2)
    compare(navigation.backTarget(), "close")
  }

  function test_search_returns_to_its_own_list() {
    var navigation = createTemporaryObject(navigationComponent, testCase)
    navigation.enterMessageSearch()
    compare(navigation.backTarget(), "messages")
    navigation.enterChatSearch()
    compare(navigation.backTarget(), "chats")
  }

  function test_j_and_k_keep_independent_bounded_cursors() {
    var navigation = createTemporaryObject(navigationComponent, testCase)
    navigation.enterChats(3, 1)
    compare(navigation.moveChats(1, 3), 2)
    compare(navigation.moveChats(1, 3), 2)
    compare(navigation.moveChats(-1, 3), 1)

    navigation.enterMessages(2)
    compare(navigation.moveMessages(1, 2), 1)
    compare(navigation.moveMessages(1, 2), 1)
    compare(navigation.moveMessages(-1, 2), 0)
    compare(navigation.chatIndex, 1)
  }

  function test_enter_on_chat_moves_directly_to_composer() {
    var navigation = createTemporaryObject(navigationComponent, testCase)
    navigation.enterChats(3, 2)
    compare(navigation.context, "chats")
    compare(navigation.openChat(3), 2)
    compare(navigation.context, "composer")
    compare(navigation.backTarget(), "messages")
  }

  function test_slash_search_is_only_armed_from_the_chat_list() {
    var navigation = createTemporaryObject(navigationComponent, testCase)
    navigation.enterChats(3, 1)
    verify(navigation.wantsChatSearch(Qt.Key_Slash, false))
    verify(!navigation.wantsChatSearch(Qt.Key_Slash, true))
    verify(!navigation.wantsChatSearch(Qt.Key_J, false))
    navigation.enterMessages(3)
    verify(!navigation.wantsChatSearch(Qt.Key_Slash, false))
  }
}
