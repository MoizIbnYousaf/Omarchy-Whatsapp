import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// Attach, field and send share one height and one bottom edge, so a one-line
// draft reads as centred and a longer one grows upward; the placeholder sits
// on the line the typed text will occupy.
TestCase {
  id: testCase
  name: "ComposerGeometry"
  width: 800
  height: 600
  visible: true
  when: windowShown

  Component {
    id: appComponent
    Oma.App { width: 800; height: 600; demoMode: true }
  }

  Component {
    id: dropdownComponent
    Oma.Dropdown { demoMode: true; viewMode: "conversation" }
  }

  function bottomOf(item, space) {
    var point = item.mapToItem(space, 0, item.height)
    return Math.round(point.y)
  }
  function topOf(item, space) {
    return Math.round(item.mapToItem(space, 0, 0).y)
  }

  function test_app_controls_share_one_bottom_edge_and_height() {
    var app = createTemporaryObject(appComponent, testCase)
    var bar = findChild(app, "composerBar")
    var attach = findChild(app, "composerAttachButton")
    var emoji = findChild(app, "composerEmojiButton")
    var field = findChild(app, "composerSurface")
    var send = findChild(app, "composerSendButton")
    var input = findChild(app, "composerInput")
    verify(bar && attach && emoji && field && send && input)
    input.text = ""
    compare(bottomOf(attach, bar), bottomOf(field, bar))
    compare(bottomOf(emoji, bar), bottomOf(field, bar))
    compare(bottomOf(send, bar), bottomOf(field, bar))
    compare(Math.round(field.height), Math.round(attach.height))
    compare(Math.round(send.height), Math.round(attach.height))

    input.text = "one\ntwo\nthree"
    verify(field.height > attach.height, "a longer draft grows the field")
    compare(bottomOf(attach, bar), bottomOf(field, bar), "and keeps the shared bottom edge")
    compare(bottomOf(send, bar), bottomOf(field, bar))
  }

  function test_app_placeholder_sits_on_the_first_text_line() {
    var app = createTemporaryObject(appComponent, testCase)
    var field = findChild(app, "composerSurface")
    var flick = findChild(app, "composerFlickable")
    var placeholder = findChild(app, "composerPlaceholder")
    var input = findChild(app, "composerInput")
    app.opened = true
    input.text = ""
    verify(placeholder.visible)
    compare(topOf(placeholder, field), topOf(flick, field))
  }

  function test_dropdown_controls_share_one_bottom_edge_and_height() {
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    dropdown.currentChat = dropdown.demoChats[0]
    var row = findChild(dropdown, "composerRowItem")
    var attach = findChild(dropdown, "composerAttachButton")
    var paste = findChild(dropdown, "composerEmojiButton")
    var field = findChild(dropdown, "composerFieldSurface")
    var send = findChild(dropdown, "composerSendButton")
    var input = findChild(dropdown, "composerInput")
    verify(row && attach && paste && field && send && input)
    input.text = ""
    for (var control of [attach, paste, send])
      compare(bottomOf(control, row), bottomOf(field, row))
    compare(Math.round(field.height), Math.round(attach.height))
    compare(Math.round(send.height), Math.round(attach.height))
  }

  function test_enter_instructions_are_a_field_tooltip_not_a_subtitle() {
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    dropdown.currentChat = dropdown.demoChats[0]
    compare(dropdown.composerHint, "Enter sends · Shift+Enter adds a line")
    function texts(item, found) {
      if (typeof item.text === "string") found.push(item.text)
      for (var i = 0; i < item.children.length; i++) texts(item.children[i], found)
      return found
    }
    verify(texts(dropdown, []).indexOf("Enter sends · Shift+Enter adds a line") < 0,
      "no visible Text carries the instructions")
  }
}
