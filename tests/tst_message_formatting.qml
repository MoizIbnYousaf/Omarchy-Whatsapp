import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// WhatsApp formatting in a message and shared contacts as cards, through a
// ListView as in the app.
TestCase {
  id: testCase
  name: "MessageFormatting"
  width: 700
  height: 900
  visible: true
  when: windowShown

  Component { id: spyComponent; SignalSpy {} }
  Component {
    id: listComponent
    ListView {
      id: list
      width: 640
      height: 800
      property var rows: []
      model: rows
      delegate: Oma.MessageBubble {
        required property var modelData
        width: list.width
        message: modelData
        foreground: "#eeeeee"; background: "#111111"; accent: "#66ccaa"
        dim: "#999999"; dimmer: "#777777"; fontFamily: "monospace"
      }
    }
  }

  function bubbleFor(message) {
    var list = createTemporaryObject(listComponent, testCase, {
      rows: JSON.parse(JSON.stringify([Object.assign({ id: "m1", sender: "Sam", timestamp: 1790280000,
        from_me: false, media_type: "", reactions: [] }, message)])) })
    tryVerify(function() { return list.count === 1 && list.itemAtIndex(0) !== null })
    return list.itemAtIndex(0)
  }

  function test_formatting_renders_and_plain_text_stays_plain() {
    var formatted = bubbleFor({ text: "a *bold* move" })
    var body = findChild(formatted, "messageText")
    compare(body.textFormat, TextEdit.RichText)
    verify(formatted.bodyHtml.indexOf("<b>bold</b>") >= 0)
    var plain = bubbleFor({ text: "no markers, snake_case" })
    compare(findChild(plain, "messageText").textFormat, TextEdit.PlainText)
  }

  function test_a_message_cannot_inject_markup_through_formatting() {
    var bubble = bubbleFor({ text: "*<img src=x>* <a href=\"http://x\">y</a>" })
    verify(bubble.bodyHtml.indexOf("<img") < 0)
    verify(bubble.bodyHtml.indexOf("<a ") < 0)
    verify(bubble.bodyHtml.indexOf("&lt;img src=x&gt;") >= 0)
  }

  function test_a_shared_contact_is_a_card_with_its_actions() {
    var bubble = bubbleFor({ text: "Contact: Ana Souza (+55 16 99999-0000)",
      contacts: [{ name: "Ana Souza", phone: "+55 16 99999-0000", digits: "5516999990000",
                   jid: "", has_chat: false }] })
    var card = findChild(bubble, "contactCard")
    verify(card !== null)
    compare(findChild(card, "contactName").text, "Ana Souza")
    compare(findChild(card, "contactPhone").text, "+55 16 99999-0000")
    verify(!findChild(bubble, "messageText").visible, "the raw 'Contact:' text is not shown")
    var chats = createTemporaryObject(spyComponent, testCase,
      { target: bubble, signalName: "contactChatRequested" })
    var copies = createTemporaryObject(spyComponent, testCase,
      { target: bubble, signalName: "copyRequested" })
    var message = findChild(card, "contactAction-message")
    mouseClick(message)
    compare(chats.count, 1)
    compare(chats.signalArguments[0][0].digits, "5516999990000")
    mouseClick(findChild(card, "contactAction-copy"))
    compare(copies.signalArguments[0][0], "+55 16 99999-0000")
  }
}
