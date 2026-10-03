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

  Component {
    id: videoBubbleComponent
    Oma.MessageBubble {
      width: 1600
      message: ({
        id: "synthetic-video",
        text: "",
        sender: "Demo",
        timestamp: 1787540100,
        from_me: true,
        media_type: "video",
        mime_type: "video/mp4",
        local_path: "__demo_video__",
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

  function allTexts(item, found) {
    found = found || []
    if (item.text !== undefined && typeof item.text === "string") found.push(item)
    for (var i = 0; i < item.children.length; i++) allTexts(item.children[i], found)
    return found
  }

  function test_sent_message_claims_no_delivery_state() {
    var messageBubble = createTemporaryObject(bubbleComponent, testCase)
    verify(messageBubble !== null)
    verify(messageBubble.message.from_me)
    var ticks = allTexts(messageBubble).filter(function(item) {
      return item.text === "✓" || item.text === "✓✓"
    })
    compare(ticks.length, 0, "wacli stores no receipts, so no tick may be drawn")
  }

  function test_content_has_balanced_vertical_padding() {
    var messageBubble = createTemporaryObject(bubbleComponent, testCase)
    verify(messageBubble !== null)

    var surface = findChild(messageBubble, "messageBubbleSurface")
    var content = findChild(messageBubble, "messageBubbleContent")
    verify(surface !== null)
    verify(content !== null)

    compare(content.y, 9)
    // The time sits on the last line or just under it; either way the space
    // below whatever is lowest matches the top.
    var meta = findChild(messageBubble, "messageMeta")
    var lowest = Math.max(content.y + content.implicitHeight, meta.y + meta.height)
    var bottom = surface.height - lowest
    verify(bottom >= 6 && bottom <= 9, "bottom padding " + bottom)
  }

  function test_visual_media_does_not_span_a_wide_timeline() {
    var messageBubble = createTemporaryObject(videoBubbleComponent, testCase)
    verify(messageBubble !== null)

    var surface = findChild(messageBubble, "messageBubbleSurface")
    verify(surface !== null)
    compare(surface.width, 560)

    messageBubble.width = 480
    compare(surface.width, 364.8)
  }

  Component {
    id: stickerBubbleComponent
    Oma.MessageBubble {
      width: 800
      message: ({ id: "synthetic-sticker", text: "", sender: "Demo", timestamp: 1787540100,
        from_me: false, media_type: "sticker", mime_type: "image/webp",
        local_path: "/nonexistent/synthetic-sticker.webp", reactions: [] })
      foreground: "#eeeeee"; background: "#111111"; accent: "#66ccaa"
      dim: "#999999"; dimmer: "#777777"; fontFamily: "monospace"
    }
  }

  function test_a_sticker_stands_alone_without_a_bubble() {
    // The owner found stickers odd: a card with a "sticker" badge, frozen on
    // the first frame, opening an external viewer on click.
    var bubble = createTemporaryObject(stickerBubbleComponent, testCase)
    verify(bubble.sticker)
    var surface = findChild(bubble, "messageBubbleSurface")
    compare(surface.color.a, 0, "no bubble behind a sticker")
    compare(bubble.desiredWidth, 176)
    var image = findChild(bubble, "stickerSurface")
    verify(image !== null, "stickers get their own surface, not the GIF card")
    compare(image.width, 160)
    verify(findChild(bubble, "animatedMediaSurface") === null)
  }
}
