import QtQuick
import QtQuick.Controls
import QtTest
import "../plugins/omawhatsapp" as Oma
import qs.Commons

TestCase {
  id: testCase
  name: "ComposerExpansion"
  width: 800
  height: 600

  Component {
    id: appComponent
    Oma.App {
      width: 800
      height: 600
      demoMode: true
    }
  }

  function test_composer_expands_upward_and_caps_at_max_lines() {
    var app = createTemporaryObject(appComponent, testCase)
    verify(app !== null)

    var composerBar = findChild(app, "composerBar")
    var composerInput = findChild(app, "composerInput")
    var composerScrollBar = findChild(app, "composerScrollBar")

    verify(composerBar !== null)
    verify(composerInput !== null)
    verify(composerScrollBar !== null)

    // Base state: 1 line (empty)
    composerInput.text = ""
    var baseHeight = composerBar.height
    compare(composerBar.visibleLines, 1)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOff)

    // 3 lines: expands upward
    composerInput.text = "Line 1\nLine 2\nLine 3"
    compare(composerInput.lineCount, 3)
    compare(composerBar.visibleLines, 3)
    verify(composerBar.height > baseHeight)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOff)

    // 6 lines (default max lines): expands to 6 lines
    composerInput.text = "1\n2\n3\n4\n5\n6"
    compare(composerInput.lineCount, 6)
    compare(composerBar.visibleLines, 6)
    var max6Height = composerBar.height
    verify(max6Height > baseHeight)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOff)

    // 10 lines: capped at 6 lines and scrollbar becomes active
    composerInput.text = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10"
    compare(composerInput.lineCount, 10)
    compare(composerBar.visibleLines, 6)
    compare(composerBar.height, max6Height)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOn)

    // Increase setting to 8 lines: expands further
    app.composerMaxLines = 8
    compare(composerBar.visibleLines, 8)
    verify(composerBar.height > max6Height)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOn)

    // Clearing text collapses back to base height
    composerInput.text = ""
    compare(composerBar.visibleLines, 1)
    compare(composerBar.height, baseHeight)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOff)
  }

  Component {
    id: dropdownComponent
    Oma.Dropdown {
      demoMode: true
      viewMode: "conversation"
    }
  }

  function test_dropdown_composer_expands_upward_and_caps() {
    var dropdown = createTemporaryObject(dropdownComponent, testCase)
    verify(dropdown !== null)
    dropdown.currentChat = dropdown.demoChats[0]

    var composerRowItem = findChild(dropdown, "composerRowItem")
    var composerInput = findChild(dropdown, "composerInput")
    var composerScrollBar = findChild(dropdown, "composerScrollBar")

    verify(composerRowItem !== null)
    verify(composerInput !== null)
    verify(composerScrollBar !== null)

    // Base state: 1 line (empty)
    composerInput.text = ""
    var baseHeight = composerRowItem.height
    compare(composerRowItem.visibleLines, 1)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOff)

    // 3 lines: expands upward
    composerInput.text = "Line 1\nLine 2\nLine 3"
    compare(composerInput.lineCount, 3)
    compare(composerRowItem.visibleLines, 3)
    verify(composerRowItem.height > baseHeight)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOff)

    // 6 lines: expands to 6 lines
    composerInput.text = "1\n2\n3\n4\n5\n6"
    compare(composerInput.lineCount, 6)
    compare(composerRowItem.visibleLines, 6)
    var max6Height = composerRowItem.height
    verify(max6Height > baseHeight)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOff)

    // 10 lines: capped at 6 lines and scrollbar becomes active
    composerInput.text = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10"
    compare(composerInput.lineCount, 10)
    compare(composerRowItem.visibleLines, 6)
    compare(composerRowItem.height, max6Height)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOn)

    // Increase setting to 8 lines: expands further
    dropdown.composerMaxLines = 8
    compare(composerRowItem.visibleLines, 8)
    verify(composerRowItem.height > max6Height)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOn)

    // Clearing text collapses back to base height
    composerInput.text = ""
    compare(composerRowItem.visibleLines, 1)
    compare(composerRowItem.height, baseHeight)
    compare(composerScrollBar.policy, ScrollBar.AlwaysOff)
  }
}
