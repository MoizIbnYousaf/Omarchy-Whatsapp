import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

TestCase {
  id: testCase
  name: "MessageBubble"

  Component {
    id: bubbleComponent
    Oma.MessageBubble {
      width: 420
      message: ({
        id: "demo-message",
        text: "A message that stays comfortably inside its bubble.",
        sender: "You",
        timestamp: 1787540100,
        from_me: true,
        media_type: "",
        reactions: []
      })
      foreground: "#eeeeee"
      background: "#111111"
      accent: "#66ccaa"
      dim: "#999999"
      dimmer: "#777777"
      fontFamily: "monospace"
    }
  }

  function test_content_has_balanced_vertical_padding() {
    var messageBubble = createTemporaryObject(bubbleComponent, testCase)
    verify(messageBubble !== null)

    var surface = findChild(messageBubble, "messageBubbleSurface")
    var content = findChild(messageBubble, "messageBubbleContent")
    verify(surface !== null)
    verify(content !== null)

    compare(content.y, 9)
    compare(surface.height - content.y - content.implicitHeight, 9)
  }
}
