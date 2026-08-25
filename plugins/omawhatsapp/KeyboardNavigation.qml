import QtQml

// Keyboard navigation is a small state machine instead of an accidental
// consequence of whichever text field last owned focus. The window supplies
// the focus changes; this object owns the composer -> messages -> chats ladder
// and the two independent cursors.
QtObject {
  id: root

  property string context: "composer"
  property int chatIndex: 0
  property int messageIndex: 0

  function boundedIndex(index, count) {
    var length = Math.max(0, Number(count) || 0)
    if (length === 0) return 0
    return Math.max(0, Math.min(length - 1, Number(index) || 0))
  }

  function enterComposer() { context = "composer" }
  function enterMessageSearch() { context = "message-search" }
  function enterChatSearch() { context = "chat-search" }

  function enterMessages(count) {
    messageIndex = boundedIndex(messageIndex, count)
    context = "messages"
  }

  function enterChats(count, preferredIndex) {
    var preferred = Number(preferredIndex)
    if (preferred >= 0) chatIndex = preferred
    chatIndex = boundedIndex(chatIndex, count)
    context = "chats"
  }

  function moveMessages(delta, count) {
    messageIndex = boundedIndex(messageIndex + Number(delta || 0), count)
    return messageIndex
  }

  function moveChats(delta, count) {
    chatIndex = boundedIndex(chatIndex + Number(delta || 0), count)
    return chatIndex
  }

  function backTarget() {
    if (context === "composer" || context === "message-search") return "messages"
    if (context === "messages" || context === "chat-search") return "chats"
    return "close"
  }
}
