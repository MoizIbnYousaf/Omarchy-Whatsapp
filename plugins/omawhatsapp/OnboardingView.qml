import QtQuick
import qs.Commons
import qs.Ui

// First run after `omarchy plugin add`: install wacli if it is missing, set up
// what lives outside the plugin folder (with consent), then link the phone
// with the QR code. What stays on this computer is said up front.
Rectangle {
  id: root

  property var service: null
  property bool demoMode: false
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color dim: foreground
  property string fontFamily: Style.font.family
  readonly property var operations: service ? service.accountOperations : null
  readonly property bool wacliTooOld: !demoMode && !!service && service.wacliTooOld === true
  readonly property bool wacliMissing: !demoMode && !!service
    && (service.wacliInstalled === false || wacliTooOld)
  readonly property bool setupNeeded: !demoMode && !!service && !wacliMissing
    && service.needsSetup === true
  readonly property bool linking: !!operations && operations.linkBusy === true
  property bool allowAgents: !service || service.setupAgents !== false

  function startLink() {
    if (demoMode || !service || !operations) return false
    return operations.linkMainAccount(service.defaultAccountName)
  }

  color: background
  MouseArea { anchors.fill: parent }

  Flickable {
    anchors.fill: parent
    contentHeight: Math.max(height, welcomeColumn.implicitHeight + Style.space(64))
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: welcomeColumn
      width: Math.min(Style.space(560), parent.width - Style.space(48))
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(Style.space(32), (parent.height - implicitHeight) / 2)
      spacing: Style.space(20)

      Row {
        spacing: Style.space(14)
        Rectangle {
          width: Style.space(52)
          height: width
          radius: width / 2
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "󰖣"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.space(28)
          }
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)
          Text {
            textFormat: Text.PlainText
            objectName: "onboardingTitle"
            text: root.wacliMissing ? "One more piece first"
              : root.setupNeeded ? "Set it up on this computer" : "Link your WhatsApp"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading + 4
            font.weight: Font.Bold
          }
          Text {
            textFormat: Text.PlainText
            text: "WhatsApp on your Omarchy desktop, kept on this computer."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // No wacli: nothing can link yet.
      Rectangle {
        objectName: "onboardingWacliMissing"
        visible: root.wacliMissing
        width: parent.width
        height: missingColumn.implicitHeight + Style.space(28)
        radius: Style.cornerRadius + 4
        color: Style.normalFillFor(root.foreground, root.accent)
        Column {
          id: missingColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.space(16)
          spacing: Style.space(8)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: root.wacliTooOld
              ? "Your wacli " + String(root.service.wacliVersion || "") + " is older than this app supports. Update it with Omarchy's package manager:"
              : "WhatsApp for Omarchy talks to WhatsApp through wacli, which is not installed yet. Install it with Omarchy's package manager:"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Rectangle {
            width: parent.width
            height: wacliCommand.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            Text {
              textFormat: Text.PlainText
              id: wacliCommand
              objectName: "onboardingWacliCommand"
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "omarchy pkg aur add wacli-bin"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
          Rectangle {
            objectName: "onboardingInstallWacli"
            width: installWacliLabel.implicitWidth + Style.space(36)
            height: Style.space(40)
            radius: Style.cornerRadius + 2
            color: installWacliHover.hovered ? Qt.lighter(root.accent, 1.1) : root.accent
            Text {
              textFormat: Text.PlainText
              id: installWacliLabel
              anchors.centerIn: parent
              text: "Install in a terminal"
              color: root.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.Bold
            }
            HoverHandler { id: installWacliHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: if (root.service) root.service.installWacli() }
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: "This screen goes on by itself once wacli is installed. A wacli of your own at ~/.local/bin/wacli is used first."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // What the setup writes outside the plugin folder, asked once.
      Rectangle {
        objectName: "onboardingSetup"
        visible: root.setupNeeded
        width: parent.width
        height: setupColumn.implicitHeight + Style.space(32)
        radius: Style.cornerRadius + 4
        color: Style.normalFillFor(root.foreground, root.accent)
        Column {
          id: setupColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.space(18)
          spacing: Style.space(12)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: "Setting up adds, in your home folder only:"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Repeater {
            model: [
              "Background sync: a user service keeps your chats current while the app is closed. It runs sandboxed and needs no password.",
              "The omawhatsapp command, linked in ~/.local/bin."
            ]
            delegate: Row {
              required property var modelData
              width: setupColumn.width
              spacing: Style.space(10)
              Text {
                textFormat: Text.PlainText
                text: "󰄬"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width - Style.space(24)
                wrapMode: Text.Wrap
                text: modelData
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
          Item {
            width: parent.width
            height: Math.max(agentsSwitch.height, agentsText.implicitHeight)
            Column {
              id: agentsText
              anchors.left: parent.left
              anchors.right: agentsSwitch.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "Let AI agents use WhatsApp"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                text: "Adds the agent skill and the MCP server. Agents ask before they change anything on WhatsApp. You can turn this off later in Settings."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            ToggleSwitch {
              id: agentsSwitch
              objectName: "onboardingAgents"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.allowAgents
              foreground: root.foreground
              accent: root.accent
              onToggled: root.allowAgents = !checked
            }
          }
          Text {
            textFormat: Text.PlainText
            objectName: "onboardingReplaceOriginal"
            visible: !!root.service && root.service.originalPluginEnabled === true
            width: parent.width
            wrapMode: Text.Wrap
            text: "OmaWhatsApp is installed and turned on. Setting up turns it off (it is not deleted), since only one of the two can run."
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            textFormat: Text.PlainText
            objectName: "onboardingConflicts"
            readonly property var paths: root.service && Array.isArray(root.service.setupConflicts)
              ? root.service.setupConflicts : []
            visible: paths.length > 0
            width: parent.width
            wrapMode: Text.Wrap
            text: "These paths belong to something else, or were changed after the app wrote them, so the setup leaves them as they are. Move them away, then set up:\n"
              + paths.join("\n")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Rectangle {
            objectName: "onboardingSetUp"
            width: setUpLabel.implicitWidth + Style.space(36)
            height: Style.space(40)
            radius: Style.cornerRadius + 2
            readonly property bool blocked: !!root.service && Array.isArray(root.service.setupConflicts)
              && root.service.setupConflicts.length > 0
            readonly property bool busy: !!root.service && root.service.setupWriting === true
            opacity: busy || blocked ? 0.6 : 1
            color: setUpHover.hovered && !busy ? Qt.lighter(root.accent, 1.1) : root.accent
            Text {
              textFormat: Text.PlainText
              id: setUpLabel
              anchors.centerIn: parent
              text: parent.busy ? "Setting up…" : "Set up"
              color: root.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.Bold
            }
            HoverHandler { id: setUpHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
              enabled: !parent.busy && !parent.blocked
              onTapped: if (root.service)
                root.service.runSetup(root.allowAgents, root.service.originalPluginEnabled === true)
            }
          }
        }
      }

      // The three steps, and the button that shows the QR code.
      Rectangle {
        objectName: "onboardingSteps"
        visible: !root.wacliMissing && !root.setupNeeded
        width: parent.width
        height: stepsColumn.implicitHeight + Style.space(32)
        radius: Style.cornerRadius + 4
        color: Style.normalFillFor(root.foreground, root.accent)
        Column {
          id: stepsColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.space(18)
          spacing: Style.space(14)
          Repeater {
            model: [
              "On your phone, open WhatsApp → Settings → Linked devices → Link a device.",
              "Click Show QR code: a terminal opens with the code.",
              "Scan it with the phone. This window fills in by itself; the first sync can take a few minutes."
            ]
            delegate: Row {
              required property var modelData
              required property int index
              width: stepsColumn.width
              spacing: Style.space(12)
              Rectangle {
                width: Style.space(24)
                height: width
                radius: width / 2
                color: root.accent
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: String(index + 1)
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.Bold
                }
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width - Style.space(36)
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.Wrap
                text: modelData
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
          Row {
            spacing: Style.space(14)
            Rectangle {
              id: linkButton
              objectName: "onboardingLink"
              width: linkButtonLabel.implicitWidth + Style.space(36)
              height: Style.space(40)
              radius: Style.cornerRadius + 2
              opacity: root.linking ? 0.6 : 1
              color: linkHover.hovered && !root.linking ? Qt.lighter(root.accent, 1.1) : root.accent
              Text {
                textFormat: Text.PlainText
                id: linkButtonLabel
                anchors.centerIn: parent
                text: root.linking ? "Waiting for your phone…" : "Show QR code"
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.Bold
              }
              HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { enabled: !root.linking; onTapped: root.startLink() }
            }
            Text {
              textFormat: Text.PlainText
              objectName: "onboardingStatus"
              anchors.verticalCenter: parent.verticalCenter
              visible: text !== ""
              text: root.operations ? String(root.operations.statusMessage || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // What stays here, before anyone links anything.
      Column {
        width: parent.width
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          text: "WHAT STAYS ON THIS COMPUTER"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - 1
          font.letterSpacing: 1.4
        }
        Repeater {
          model: [
            "Your chats and media are kept in a local copy, readable even offline.",
            "Messages go only to WhatsApp itself: there is no WhatsApp for Omarchy server or account.",
            "It is a linked device, like WhatsApp Web: your phone stays the main one."
          ]
          delegate: Row {
            required property var modelData
            width: parent.width
            spacing: Style.space(10)
            Text {
              textFormat: Text.PlainText
              text: "󰄬"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width - Style.space(24)
              wrapMode: Text.Wrap
              text: modelData
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
