import QtQuick
import qs.Commons
import "AccountModel.js" as AccountModel

// Public UI deliberately names only configured account labels. Private store
// paths and diagnostic text stay inside the helper boundary.
Rectangle {
  id: root

  required property var accounts
  required property color foreground
  required property color accent
  required property string fontFamily
  property bool compact: false

  readonly property string summary: AccountModel.unreadyAccountSummary(accounts)
  readonly property bool hasUnavailableAccounts: summary !== ""

  visible: hasUnavailableAccounts
  implicitHeight: hasUnavailableAccounts ? Style.space(compact ? 28 : 30) : 0
  height: implicitHeight
  radius: Style.cornerRadius
  color: Qt.rgba(accent.r, accent.g, accent.b, 0.10)
  border.width: 1
  border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.28)

  Text {
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.leftMargin: Style.space(9)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
    text: "△  " + root.summary
    color: root.foreground
    elide: Text.ElideRight
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
