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
}
