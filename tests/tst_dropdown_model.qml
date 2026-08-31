import QtQuick
import QtTest
import "../plugins/omawhatsapp/DropdownModel.js" as DropdownModel

TestCase {
  name: "DropdownModel"

  function test_cursor_is_bounded() {
    compare(DropdownModel.clampIndex(-2, 3), 0)
    compare(DropdownModel.clampIndex(1, 3), 1)
    compare(DropdownModel.clampIndex(8, 3), 2)
    compare(DropdownModel.clampIndex(8, 0), 0)
  }

  function test_message_cursor_uses_visual_bottom_to_top_direction() {
    compare(DropdownModel.visualMessageIndex(0, 1, 3), 0)
    compare(DropdownModel.visualMessageIndex(0, -1, 3), 1)
    compare(DropdownModel.visualMessageIndex(1, -1, 3), 2)
    compare(DropdownModel.visualMessageIndex(2, -1, 3), 2)
    compare(DropdownModel.visualMessageIndex(2, 1, 3), 1)
    compare(DropdownModel.visualMessageIndex(0, 1, 1), 0)
    compare(DropdownModel.visualMessageIndex(0, -1, 1), 0)
    compare(DropdownModel.visualMessageIndex(0, 1, 0), 0)
  }

  function test_expand_payload_is_exact() {
    compare(DropdownModel.fullAppPayload(null), {})
    compare(DropdownModel.fullAppPayload({
      account: "work", jid: "demo@example"
    }), {
      account: "work", jid: "demo@example", conversation: true
    })
  }

  function test_demo_send_never_needs_a_transport() {
    var message = DropdownModel.demoMessage("release-safe demo", true, 123000)
    compare(message.id, "demo-123000")
    compare(message.text, "release-safe demo")
    compare(message.timestamp, 123)
    compare(message.from_me, true)
    compare(message.media_type, "document")
  }
}
