import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tint.js" as Tint

// Settings as a full window view, in the manner of Omarchy's own apps: a
// section list on the left, one scrollable page on the right, every row a
// title, a one-line explanation and its control. Rows are data (see rowsFor),
// so an option is one entry and the view never drifts from the service.
Rectangle {
  id: settings
  objectName: "settingsView"

  required property var app
  property var service: null
  property var updates: null
  property bool demoMode: false
  property bool narrow: false
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property color accent: Commons.Color.accent
  property color dim: foreground
  property color dimmer: foreground
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family
  signal closeRequested()

  property string current: "reading"
  // The account whose Unlink waits for a second, explicit click.
  property string unlinkConfirming: ""
  // Remove from this computer waits for a second click too.
  property bool removeConfirming: false
  onCurrentChanged: { unlinkConfirming = ""; removeConfirming = false }
  // In the narrow layout the section list and a section page take turns.
  property bool narrowPage: false
  readonly property bool live: !demoMode && !!service

  color: background

  // Clicks on empty space must not reach the conversation underneath.
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

  readonly property var sections: [
    { id: "reading", icon: "󰛐", label: "Reading" },
    { id: "notifications", icon: "󰂜", label: "Notifications" },
    { id: "chats", icon: "󰍪", label: "Chats" },
    { id: "media", icon: "󰥶", label: "Media" },
    { id: "sync", icon: "󰓦", label: "Sync & storage" },
    { id: "accounts", icon: "󰀏", label: "Accounts" },
    { id: "updates", icon: "󰚰", label: "Updates" },
    { id: "shortcuts", icon: "󰥻", label: "Shortcuts" },
    { id: "about", icon: "󰋽", label: "About" }
  ]

  function value(name, fallback) {
    if (!service || service[name] === undefined || service[name] === null) return fallback
    return service[name]
  }
  function megabytes(bytes) {
    var value = Number(bytes || 0)
    if (value < 1024 * 1024) return Math.max(1, Math.round(value / 1024)) + " KB"
    return (value / (1024 * 1024)).toFixed(1) + " MB"
  }
  function sectionLabel(id) {
    for (var i = 0; i < sections.length; i++) if (sections[i].id === id) return sections[i].label
    return ""
  }
  function openSection(id) {
    current = id
    narrowPage = true
    if (id === "sync" || id === "about") refreshAbout()
    pageFlick.contentY = 0
  }
  function refreshAbout() {
    if (live && typeof service.refreshAbout === "function") service.refreshAbout()
  }
  onVisibleChanged: if (visible) {
    narrowPage = false
    unlinkConfirming = ""
    removeConfirming = false
    refreshAbout()
  }
  // Demo captures show repository-owned figures, never this machine's.
  readonly property var demoAccounts: [
    { account: "work", label: "work", main: true, authenticated: true, online: true,
      sync_active: true, notifications_muted: false },
    { account: "personal", label: "personal", main: false, authenticated: true, online: true,
      sync_active: true, notifications_muted: true }
  ]
  readonly property var demoAbout: ({
    app_version: "0.14.0", install_mode: "standalone", wacli_version: "0.18.3",
    wacli_minimum_version: "0.17.1", wacli_tested_version: "0.18.3",
    stores: [{ account: "work", label: "work", database_bytes: 18874368,
               media_bytes: 262144000, media_files: 1240 }],
    avatar_cache_bytes: 1572864
  })

  function rowsFor(section) {
    var busy = value("settingsWriting", false)
    var controlBusy = value("controlWriting", false)
    var notifyOn = value("notificationsEnabled", false)
    var notifyAvailable = value("notifyAvailable", true)
    var multi = value("multiAccount", false)
    var offline = value("offlineMode", false)
    var about = demoMode ? demoAbout : (value("about", ({})) || ({}))
    if (section === "reading") return [
      { kind: "toggle", key: "send_read_receipts",
        title: "Mark chats read when you open them",
        subtitle: "The chat on screen is read, including messages that arrive while it is open."
          + (multi ? " Applies to the account of the open chat." : ""),
        checked: value("sendReadReceipts", true), busy: busy },
      { kind: "toggle", key: "read_on_reply",
        title: "Mark chats read when you reply",
        subtitle: "Replying clears the unread count, as it does on the phone.",
        checked: value("readOnReply", true), busy: busy },
      { kind: "toggle", key: "show_online",
        title: "Show me online while OmaWhatsApp has focus",
        subtitle: "Needed to see who is online, their last seen, and who is typing: WhatsApp only sends them to a device shown online. It also shows the chat when you are typing or recording a voice note. Needs a wacli build that follows presence.",
        checked: value("showOnline", true), busy: busy },
      { kind: "note",
        text: "Marking a chat read only syncs your phone and linked devices. OmaWhatsApp never sends read receipts, so contacts are not told." }
    ]
    if (section === "notifications") return [
      { kind: "toggle", key: "notify", title: "Desktop notifications",
        subtitle: !notifyAvailable ? "Needs notify-send from libnotify."
          : (notifyOn ? "Private popups hide chat names, message text and photos. Right-click the bar icon to mute everything."
            : "Muted; the bar still counts unread chats. Right-click the bar icon to turn them back on."),
        checked: notifyOn, available: notifyAvailable || notifyOn, busy: controlBusy },
      { kind: "toggle", key: "notify_reply", title: "Reply from the bar when clicking a notification",
        subtitle: value("notifyReply", true)
          ? "A small reply view opens by the bar on that chat; Esc closes it."
          : "Clicking a notification opens the full app on that chat.",
        checked: value("notifyReply", true), available: notifyOn, busy: busy },
      { kind: "toggle", key: "notify_sound", title: "Sound",
        subtitle: value("notificationsSound", true)
          ? "One short sound per batch of new messages; silent while Omarchy's do not disturb is on."
          : "Notifications arrive without sound.",
        checked: value("notificationsSound", true), available: notifyOn, busy: controlBusy },
      { kind: "toggle", key: "show_unread_count", title: "Unread count in the bar",
        subtitle: "A local badge on the bar icon.",
        checked: value("showUnreadCount", true), busy: busy },
      { kind: "choice", key: "dropdown_rows", title: "Recent chats in the bar dropdown",
        current: value("dropdownRows", 7), prefix: "settingChoice-dropdown_rows-",
        options: [{ value: 5, label: "5" }, { value: 7, label: "7" }, { value: 9, label: "9" }] }
    ]
    if (section === "chats") return [
      { kind: "signature", key: "signature", busy: busy, multi: multi },
      { kind: "toggle", key: "enter_sends", title: "Enter sends messages",
        subtitle: value("enterSends", true) ? "Shift+Enter adds a line." : "Ctrl+Enter sends; Enter adds a line.",
        checked: value("enterSends", true), busy: busy },
      { kind: "toggle", key: "show_avatars", title: "Chat photos",
        subtitle: "Show contact and group photos in the list and the conversation header.",
        checked: value("showAvatars", true), busy: busy },
      { kind: "choice", key: "rail_density", title: "Chat list density",
        current: value("railDensity", "comfortable"), prefix: "settingChoice-rail_density-",
        options: [{ value: "comfortable", label: "Comfortable" }, { value: "compact", label: "Compact" }] },
      { kind: "choice", key: "time_format", title: "Time format",
        subtitle: "System follows your locale.",
        current: settings.app ? settings.app.timeFormat : "auto", prefix: "timeFormatChoice",
        options: [{ value: "auto", label: "System" }, { value: "12h", label: "12-hour" },
                  { value: "24h", label: "24-hour" }] },
      { kind: "choice", key: "composer_max_lines", title: "Message box grows up to",
        current: settings.app ? settings.app.composerMaxLines : 6, prefix: "composerLineLimit",
        options: [{ value: 4, label: "4 lines" }, { value: 6, label: "6 lines" },
                  { value: 8, label: "8 lines" }, { value: 10, label: "10 lines" }] }
    ]
    if (section === "media") {
      var operations = value("accountOperations", null)
      return [
        { kind: "toggle", key: "auto_download_media", title: "Download received media automatically",
          subtitle: value("autoDownloadMedia", true)
            ? "Photos, videos, audio and documents are saved as they arrive."
            : "Media is downloaded only when you open it.",
          checked: value("autoDownloadMedia", true), busy: controlBusy },
        { kind: "toggle", key: "auto_refresh_avatars", title: "Refresh chat photos automatically",
          subtitle: "Off by default. Checking photos pauses sync for up to 20 seconds, and messages or read state that arrive meanwhile never reach this computer.",
          checked: value("autoRefreshAvatars", false), busy: busy },
        { kind: "action", key: "refresh_avatars", title: "Refresh chat photos now",
          subtitle: operations && operations.statusMessage ? operations.statusMessage
            : "Checks the most recent chats for new photos. Sync pauses for up to 20 seconds.",
          button: operations && operations.avatarBusy ? "Refreshing…" : "Refresh",
          available: live && !!operations && !operations.avatarBusy && !operations.linkBusy }
      ]
    }
    if (section === "sync") {
      var rows = [
        { kind: "toggle", key: "online", title: "Background sync",
          subtitle: offline ? "Paused. The local archive stays readable; nothing is sent or received."
            : "Keeps the local mirror current while the app is closed.",
          checked: demoMode || !offline, available: live && value("statusReady", false),
          busy: controlBusy },
        { kind: "toggle", key: "start_at_login", title: "Start with the system",
          subtitle: value("startAtLogin", true)
            ? "Messages and popups arrive as soon as you log in."
            : "At login OmaWhatsApp stays closed until you open it from the bar or with Super+Shift+W.",
          checked: value("startAtLogin", true), busy: busy },
        { kind: "action", key: "quit", title: "Quit OmaWhatsApp",
          subtitle: "Stops receiving messages, popups and showing you online until you open it again. Ctrl+Q in the app.",
          button: "Quit", available: live },
        { kind: "toggle", key: "agents", title: "Let AI agents use WhatsApp",
          subtitle: value("setupAgents", false)
            ? "The agent skill and the MCP server are installed; agents ask before they change anything on WhatsApp."
            : "No agent can use WhatsApp through this app.",
          checked: value("setupAgents", false), available: live && value("setupKnown", false),
          busy: value("setupWriting", false) },
        { kind: "action", key: "remove_setup",
          title: settings.removeConfirming ? "Remove it from this computer?" : "Remove from this computer",
          subtitle: settings.removeConfirming
            ? "Background sync stops, and the services, the command and the agent skill are removed. Your linked device, chats and settings stay."
            : "Before removing the app: stops background sync and removes what the setup added outside the plugin folder.",
          button: settings.removeConfirming ? "Remove" : "Remove…",
          available: live && !value("setupWriting", false) }
      ]
      var teardown = live ? value("lastTeardown", null) : null
      if (teardown && Array.isArray(teardown.kept) && teardown.kept.length > 0)
        rows.push({ kind: "note", text: "Left as they were, because they were changed after the app wrote them or are not the app's: "
          + teardown.kept.join(", ") })
      if (teardown)
        rows.push({ kind: "action", key: "remove_plugin", title: "Remove the app too",
          subtitle: "Runs omarchy plugin remove " + value("pluginId", "") + " in a terminal, which asks first.",
          button: "Remove the app…", available: true })
      var stores = Array.isArray(about.stores) ? about.stores : []
      for (var i = 0; i < stores.length; i++) {
        var label = multi ? " · " + (stores[i].label || stores[i].account || "primary") : ""
        rows.push({ kind: "info", title: "Messages" + label, value: megabytes(stores[i].database_bytes) })
        rows.push({ kind: "info", title: "Downloaded media" + label,
          value: megabytes(stores[i].media_bytes) + " · " + stores[i].media_files + " files" })
      }
      if (about.avatar_cache_bytes !== undefined)
        rows.push({ kind: "info", title: "Chat photo cache", value: megabytes(about.avatar_cache_bytes) })
      if (stores.length === 0)
        rows.push({ kind: "note", text: value("aboutLoading", false) ? "Measuring local storage…" : "Storage details appear once the account is ready." })
      return rows
    }
    if (section === "accounts") {
      var accounts = demoMode ? demoAccounts : value("accounts", [])
      var list = []
      for (var a = 0; a < accounts.length; a++)
        list.push({ kind: "account", key: "account-" + String(accounts[a].account || ""),
          entry: accounts[a], index: a, multi: accounts.length > 1,
          busy: controlBusy || busy })
      if (list.length === 0) list.push({ kind: "note", text: "No linked account yet." })
      list.push({ kind: "link", key: "link", title: "Link another account",
        subtitle: "Scan the QR code in the terminal that opens.",
        available: live && !(value("accountOperations", null) || {}).linkBusy })
      return list
    }
    if (section === "updates") return [ { kind: "updates" } ]
    if (section === "shortcuts") return [
      { kind: "info", title: "Super+Shift+W", value: "Open or close OmaWhatsApp" },
      { kind: "info", title: "Ctrl+F", value: "Find in this conversation" },
      { kind: "info", title: "Ctrl+B", value: "Hide or show the chat list" },
      { kind: "info", title: "Ctrl+N", value: "Start a new chat" },
      { kind: "info", title: "Ctrl+K", value: "Go to a chat by name" },
      { kind: "info", title: "Ctrl+B · Ctrl+I", value: "Bold or italic for the selected text (Ctrl+B without a selection hides the chat list)" },
      { kind: "info", title: "Ctrl+Shift+X · Ctrl+Shift+M", value: "Strikethrough or monospace; the formatting button has lists, quotes and code" },
      { kind: "info", title: "/", value: "Search chats" },
      { kind: "info", title: "J · K", value: "Move through messages or chats" },
      { kind: "info", title: "R", value: "Reply to the selected message" },
      { kind: "info", title: "C", value: "Write a message" },
      { kind: "info", title: value("enterSends", true) ? "Enter · Shift+Enter" : "Ctrl+Enter · Enter",
        value: "Send · new line" },
      { kind: "info", title: "Ctrl+V", value: "Paste text, an image or a file" },
      { kind: "info", title: "Ctrl+O · Ctrl+Shift+O", value: "Attach documents · photos and videos" },
      { kind: "info", title: "Ctrl+Shift+V", value: "Record a voice note" },
      { kind: "info", title: "Space", value: "Open the selected media" },
      { kind: "info", title: "Esc", value: "Step back" }
    ]
    if (section === "about") return [
      { kind: "info", title: "OmaWhatsApp", value: (about.app_version || "—") + (about.install_mode ? " · " + about.install_mode : "") },
      { kind: "info", title: "wacli", value: (about.wacli_version || "—") + " · supports "
          + (about.wacli_minimum_version || "0.17.1") + " and newer, tested with " + (about.wacli_tested_version || "0.18.3") },
      { kind: "info", title: "Source", value: "github.com/MoizIbnYousaf/Omarchy-Whatsapp" },
      { kind: "note", text: "Settings live in a private preferences file on this device. Chats stay in wacli's local mirror; nothing here sends chat data anywhere." }
    ]
    return []
  }

  // The signature of the account whose chat is open (each account has one).
  readonly property var signature: (demoMode && app ? app.demoSignature
    : (live && typeof service.signatureFor === "function"
      ? service.signatureFor(String(service.selectedChatAccount || "")) : null))
    || ({ enabled: false, name: "", position: "top" })
  function saveSignature(change) {
    var next = Object.assign({}, change)
    if (demoMode && app) {
      app.demoSignature = Object.assign({}, signature, next)
      return true
    }
    if (!live) return false
    return service.setPreference("signature", next)
  }

  function accountState(entry) {
    if (!entry || entry.authenticated !== true) return "Not linked"
    if (entry.online === false) return "Paused · nothing is sent or received"
    return entry.sync_active ? "Syncing" : "Linked · sync is starting"
  }
  function accountSync(entry, next) {
    return live && service.setOnline(next === true, String(entry.account || ""))
  }
  function accountNotifications(entry, next) {
    return live && service.setPreference("account_notifications", next === true, String(entry.account || ""))
  }
  function accountLink(entry) {
    if (!live || !service.accountOperations) return false
    return entry.main === true
      ? service.accountOperations.linkMainAccount(String(entry.label || entry.account || ""))
      : service.accountOperations.linkAccount(String(entry.account || ""))
  }
  function accountUnlink(entry) {
    var name = String(entry && entry.account || "")
    if (unlinkConfirming !== name) {
      unlinkConfirming = name
      return false
    }
    unlinkConfirming = ""
    return live && service.unlinkAccount(name, name)
  }

  function runRow(row, next) {
    if (!row) return false
    if (row.key === "time_format" && demoMode) {
      if (app) app.demoTimeFormat = next
      return true
    }
    if (!live) return false
    switch (row.key) {
    case "notify": return service.setNotifications(next, null)
    case "notify_preview": return service.setNotifications(null, next)
    case "notify_sound": return service.setNotifications(null, null, next)
    case "auto_download_media": return service.setAutoDownloadMedia(next)
    case "online": return service.setOnline(next)
    case "refresh_avatars": return service.accountOperations.refreshAvatars()
    case "agents": return service.runSetup(next, false)
    case "remove_setup":
      if (!removeConfirming) { removeConfirming = true; return false }
      removeConfirming = false
      return service.removeFromComputer()
    case "remove_plugin": return service.removePlugin()
    case "quit": return settings.app && typeof settings.app.quitApp === "function"
      ? settings.app.quitApp() : service.quitApp()
    case "link": return service.accountOperations.linkAccount(next)
    default: return service.setPreference(row.key, next)
    }
  }

  // ------------------------------------------------------------- header

  Item {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(56)

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      PanelActionButton {
        visible: settings.narrow && settings.narrowPage
        width: visible ? implicitWidth : 0
        iconText: "󰁍"
        tooltipText: "All settings"
        foreground: settings.foreground
        fontFamily: settings.fontFamily
        fontSize: Style.font.body
        size: Style.space(30)
        onClicked: settings.narrowPage = false
      }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: settings.narrow && settings.narrowPage ? settings.sectionLabel(settings.current) : "Settings"
        color: settings.foreground
        font.family: settings.fontFamily
        font.pixelSize: Style.font.heading
      }
    }
    PanelActionButton {
      objectName: "settingsCloseButton"
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅖"
      tooltipText: "Close · Esc"
      foreground: settings.dim
      hoverColor: settings.foreground
      fontFamily: settings.fontFamily
      fontSize: Style.font.body
      size: Style.space(30)
      onClicked: settings.closeRequested()
    }
  }

  // ------------------------------------------------------------ sections

  ListView {
    id: sectionList
    objectName: "settingsSections"
    visible: !settings.narrow || !settings.narrowPage
    anchors.top: header.bottom
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    width: settings.narrow ? parent.width - Style.space(16) : Style.space(220)
    clip: true
    spacing: Style.space(2)
    model: settings.sections
    delegate: Rectangle {
      required property var modelData
      objectName: "settingsSection-" + modelData.id
      width: sectionList.width
      height: Style.space(40)
      radius: Style.cornerRadius
      readonly property bool active: !settings.narrow && settings.current === modelData.id
      color: active ? Style.selectedFillFor(settings.foreground, settings.accent)
        : (sectionHover.hovered ? Style.hoverFillFor(settings.foreground, settings.accent) : "transparent")
      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(20)
        text: modelData.icon
        color: parent.active ? settings.accent : settings.dim
        font.family: settings.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(42)
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.label
        color: settings.foreground
        font.family: settings.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      HoverHandler { id: sectionHover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: settings.openSection(modelData.id) }
    }
  }

  Rectangle {
    visible: !settings.narrow
    anchors.top: header.bottom
    anchors.bottom: parent.bottom
    anchors.left: sectionList.right
    anchors.leftMargin: Style.space(8)
    width: 1
    color: Qt.rgba(settings.foreground.r, settings.foreground.g, settings.foreground.b, 0.10)
  }

  // ---------------------------------------------------------------- page

  Flickable {
    id: pageFlick
    objectName: "settingsPage"
    visible: !settings.narrow || settings.narrowPage
    anchors.top: header.bottom
    anchors.bottom: parent.bottom
    anchors.left: settings.narrow ? parent.left : sectionList.right
    anchors.leftMargin: settings.narrow ? Style.space(12) : Style.space(24)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    contentWidth: width
    contentHeight: pageColumn.implicitHeight + Style.space(24)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: pageColumn
      width: Math.min(pageFlick.width, Style.space(720))
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        visible: !settings.narrow
        text: settings.sectionLabel(settings.current)
        color: settings.foreground
        font.family: settings.fontFamily
        font.pixelSize: Style.font.title
        bottomPadding: Style.space(6)
      }

      Repeater {
        model: settings.rowsFor(settings.current)
        delegate: Loader {
          required property var modelData
          property var row: modelData
          width: pageColumn.width
          sourceComponent: modelData.kind === "toggle" ? toggleRow
            : modelData.kind === "choice" ? choiceRow
            : modelData.kind === "info" ? infoRow
            : modelData.kind === "action" ? actionRow
            : modelData.kind === "link" ? linkRow
            : modelData.kind === "updates" ? updatesRow
            : modelData.kind === "signature" ? signatureRow
            : modelData.kind === "account" ? accountRow
            : noteRow
        }
      }
    }
  }

  // --------------------------------------------------------- row kinds

  Component {
    id: toggleRow
    Rectangle {
      readonly property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      height: Math.max(Style.space(60), toggleText.implicitHeight + Style.space(22))
      radius: Style.cornerRadius
      color: Style.normalFillFor(settings.foreground, settings.accent)
      opacity: row.available === false ? 0.55 : 1
      Column {
        id: toggleText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.right: toggle.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          text: row.title || ""
          color: settings.foreground
          font.family: settings.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          visible: text !== ""
          text: row.subtitle || ""
          color: settings.dim
          font.family: settings.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      ToggleSwitch {
        id: toggle
        objectName: "setting-" + (row.key || "")
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        checked: row.checked === true
        enabled: row.available !== false && (settings.live || row.key === "time_format")
        busy: row.busy === true
        foreground: settings.foreground
        accent: settings.accent
        onToggled: settings.runRow(row, !checked)
      }
    }
  }

  Component {
    id: signatureRow
    Rectangle {
      id: signatureCard
      readonly property var row: parent ? parent.row : ({})
      readonly property var current: settings.signature
      width: parent ? parent.width : 0
      height: signatureColumn.implicitHeight + Style.space(24)
      radius: Style.cornerRadius
      color: Style.normalFillFor(settings.foreground, settings.accent)
      function commitName() {
        var name = String(signatureName.text || "").trim()
        if (name === String(current.name || "")) return
        settings.saveSignature(name === "" ? { enabled: false, name: "" } : { name: name })
      }
      Column {
        id: signatureColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)
        Item {
          width: parent.width
          height: Math.max(signatureToggle.height, signatureTitle.implicitHeight)
          Column {
            id: signatureTitle
            anchors.left: parent.left
            anchors.right: signatureToggle.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)
            Text {
              textFormat: Text.PlainText
              text: "Sign my messages"
              color: settings.foreground
              font.family: settings.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              text: "Your name in bold on texts and captions, never on reactions, stickers or audio. "
                + "The message box shows it and can skip it for one message."
                + (signatureCard.row.multi ? " Applies to the account of the open chat." : "")
              color: settings.dim
              font.family: settings.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          ToggleSwitch {
            id: signatureToggle
            objectName: "setting-signature"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: signatureCard.current.enabled === true
            enabled: settings.live || settings.demoMode
            busy: signatureCard.row.busy === true
            foreground: settings.foreground
            accent: settings.accent
            onToggled: {
              var name = String(signatureName.text || "").trim()
              // Nothing to sign with yet: the name comes first.
              if (!checked && name === "") { signatureName.forceActiveFocus(); return }
              settings.saveSignature(checked ? { enabled: false } : { enabled: true, name: name })
            }
          }
        }
        Row {
          spacing: Style.space(8)
          TextField {
            id: signatureName
            objectName: "signatureName"
            width: Math.min(Style.space(260), signatureColumn.width - Style.space(180))
            text: String(signatureCard.current.name || "")
            placeholderText: "Name to sign with"
            maximumLength: 40
            foreground: settings.foreground
            accent: settings.accent
            font.family: settings.fontFamily
            font.pixelSize: Style.font.bodySmall
            validator: RegularExpressionValidator { regularExpression: /[^*\n]*/ }
            onEditingFinished: signatureCard.commitName()
          }
          Repeater {
            model: [{ value: "top", label: "At the top" }, { value: "bottom", label: "At the end" }]
            delegate: Rectangle {
              required property var modelData
              readonly property bool chosen: String(signatureCard.current.position || "top") === modelData.value
              objectName: "signaturePosition-" + modelData.value
              width: signaturePositionLabel.implicitWidth + Style.space(22)
              height: Style.space(32)
              radius: Style.cornerRadius
              color: chosen ? Style.selectedFillFor(settings.foreground, settings.accent)
                : (signaturePositionHover.hovered ? Style.hoverFillFor(settings.foreground, settings.accent) : "transparent")
              border.width: 1
              border.color: chosen ? Qt.rgba(settings.accent.r, settings.accent.g, settings.accent.b, 0.8)
                : Qt.rgba(settings.foreground.r, settings.foreground.g, settings.foreground.b, 0.14)
              Text {
                textFormat: Text.PlainText
                id: signaturePositionLabel
                anchors.centerIn: parent
                text: modelData.label
                color: parent.chosen ? settings.foreground : settings.dim
                font.family: settings.fontFamily
                font.pixelSize: Style.font.caption
              }
              HoverHandler { id: signaturePositionHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: settings.saveSignature({ position: modelData.value }) }
            }
          }
        }
        // How the other side sees it.
        Rectangle {
          objectName: "signaturePreview"
          visible: String(signatureName.text || "").trim() !== ""
          width: Math.min(signatureColumn.width, Style.space(320))
          height: signaturePreviewColumn.implicitHeight + Style.space(14)
          radius: Style.cornerRadius + 2
          color: Qt.rgba(settings.accent.r, settings.accent.g, settings.accent.b, 0.14)
          Column {
            id: signaturePreviewColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            readonly property bool atTop: String(signatureCard.current.position || "top") !== "bottom"
            Text {
              textFormat: Text.PlainText
              visible: signaturePreviewColumn.atTop
              text: String(signatureName.text || "").trim() + ":"
              color: settings.foreground
              font.family: settings.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.Bold
            }
            Text {
              textFormat: Text.PlainText
              text: "Chego às 10h."
              color: settings.foreground
              font.family: settings.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Row {
              visible: !signaturePreviewColumn.atTop
              topPadding: Style.space(6)
              Text {
                textFormat: Text.PlainText
                text: "— "
                color: settings.foreground
                font.family: settings.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                textFormat: Text.PlainText
                text: String(signatureName.text || "").trim()
                color: settings.foreground
                font.family: settings.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.Bold
              }
            }
          }
        }
      }
    }
  }

  // One switch inside an account card.
  component AccountSwitch: Item {
    id: accountSwitch
    property string key: ""
    property string title: ""
    property string subtitle: ""
    property bool checked: false
    property bool busy: false
    signal toggled(bool next)
    height: Math.max(accountSwitchToggle.height, accountSwitchText.implicitHeight)
    Column {
      id: accountSwitchText
      anchors.left: parent.left
      anchors.right: accountSwitchToggle.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: accountSwitch.title
        color: settings.foreground
        font.family: settings.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: accountSwitch.subtitle
        color: settings.dim
        font.family: settings.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    ToggleSwitch {
      id: accountSwitchToggle
      objectName: accountSwitch.key
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: accountSwitch.checked
      enabled: settings.live
      busy: accountSwitch.busy
      foreground: settings.foreground
      accent: settings.accent
      onToggled: accountSwitch.toggled(!checked)
    }
  }

  Component {
    id: accountRow
    Rectangle {
      id: accountCard
      readonly property var row: parent ? parent.row : ({})
      readonly property var entry: row.entry || ({})
      readonly property string name: String(entry.account || "")
      readonly property string label: String(entry.label || entry.account || "primary")
      readonly property bool linked: entry.authenticated === true
      readonly property bool confirming: settings.unlinkConfirming !== "" && settings.unlinkConfirming === name
      objectName: "accountCard-" + name
      width: parent ? parent.width : 0
      height: accountColumn.implicitHeight + Style.space(24)
      radius: Style.cornerRadius
      color: Style.normalFillFor(settings.foreground, settings.accent)
      Column {
        id: accountColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(12)
        Item {
          width: parent.width
          height: Math.max(accountHeading.implicitHeight, accountAction.height)
          Rectangle {
            id: accountDot
            objectName: "accountDot-" + accountCard.name
            visible: accountCard.row.multi === true
            width: visible ? Style.space(10) : 0
            height: width
            radius: width / 2
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: Tint.accountColor(accountCard.row.index, settings.accent)
          }
          Column {
            id: accountHeading
            anchors.left: accountDot.right
            anchors.leftMargin: accountDot.visible ? Style.space(10) : 0
            anchors.right: accountAction.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              text: accountCard.label
              color: settings.foreground
              font.family: settings.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              textFormat: Text.PlainText
              objectName: "accountState-" + accountCard.name
              width: parent.width
              wrapMode: Text.Wrap
              text: settings.accountState(accountCard.entry)
                + (String(accountCard.entry.error || "") !== "" ? " · " + accountCard.entry.error : "")
              color: settings.dim
              font.family: settings.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Button {
            id: accountAction
            objectName: (accountCard.linked ? "accountUnlink-" : "accountLink-") + accountCard.name
            visible: !accountCard.confirming
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: accountCard.linked ? "Unlink…" : "Link"
            enabled: settings.live && accountCard.row.busy !== true
              && !(settings.value("accountOperations", null) || {}).linkBusy
            foreground: settings.foreground
            accent: settings.accent
            fontFamily: settings.fontFamily
            bordered: true
            onClicked: accountCard.linked ? settings.accountUnlink(accountCard.entry)
              : settings.accountLink(accountCard.entry)
          }
        }
        AccountSwitch {
          visible: accountCard.linked
          width: parent.width
          key: "accountSync-" + accountCard.name
          title: "Background sync"
          subtitle: "Receives this account's messages while the app is closed."
          checked: accountCard.entry.online !== false
          busy: accountCard.row.busy === true
          onToggled: function(next) { settings.accountSync(accountCard.entry, next) }
        }
        AccountSwitch {
          visible: accountCard.linked && accountCard.row.multi === true
          width: parent.width
          key: "accountNotify-" + accountCard.name
          title: "Notifications"
          subtitle: accountCard.entry.notifications_muted === true
            ? "Silent. Its chats still count in the bar and the list."
            : "Popups for this account's chats, as set under Notifications."
          checked: accountCard.entry.notifications_muted !== true
          busy: accountCard.row.busy === true
          onToggled: function(next) { settings.accountNotifications(accountCard.entry, next) }
        }
        Column {
          objectName: "accountConfirm-" + accountCard.name
          visible: accountCard.confirming
          width: parent.width
          spacing: Style.space(8)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: "Unlink " + accountCard.label + "? Your phone loses this linked device and "
              + "this computer stops receiving its messages. The chats already here stay on disk; "
              + "linking again means scanning a new QR code."
            color: settings.foreground
            font.family: settings.fontFamily
            font.pixelSize: Style.font.caption
          }
          Row {
            spacing: Style.space(8)
            Button {
              objectName: "accountUnlinkConfirm-" + accountCard.name
              text: "Unlink " + accountCard.label
              enabled: settings.live && accountCard.row.busy !== true
              foreground: settings.urgent
              accent: settings.urgent
              fontFamily: settings.fontFamily
              bordered: true
              onClicked: settings.accountUnlink(accountCard.entry)
            }
            Button {
              objectName: "accountUnlinkCancel-" + accountCard.name
              text: "Cancel"
              foreground: settings.foreground
              accent: settings.accent
              fontFamily: settings.fontFamily
              bordered: true
              onClicked: settings.unlinkConfirming = ""
            }
          }
        }
      }
    }
  }

  Component {
    id: choiceRow
    Rectangle {
      readonly property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      height: choiceColumn.implicitHeight + Style.space(24)
      radius: Style.cornerRadius
      color: Style.normalFillFor(settings.foreground, settings.accent)
      Column {
        id: choiceColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          text: row.title || ""
          color: settings.foreground
          font.family: settings.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: row.subtitle || ""
          color: settings.dim
          font.family: settings.fontFamily
          font.pixelSize: Style.font.caption
        }
        Row {
          spacing: Style.space(6)
          Repeater {
            model: row.options || []
            delegate: Rectangle {
              required property var modelData
              readonly property bool chosen: String(row.current) === String(modelData.value)
              objectName: String(row.prefix || "") + String(modelData.value)
              width: Math.max(Style.space(64), optionLabel.implicitWidth + Style.space(24))
              height: Style.space(32)
              radius: Style.cornerRadius
              color: chosen ? Style.selectedFillFor(settings.foreground, settings.accent)
                : (optionHover.hovered ? Style.hoverFillFor(settings.foreground, settings.accent) : "transparent")
              border.width: 1
              border.color: chosen ? Qt.rgba(settings.accent.r, settings.accent.g, settings.accent.b, 0.8)
                : Qt.rgba(settings.foreground.r, settings.foreground.g, settings.foreground.b, 0.14)
              Text {
                textFormat: Text.PlainText
                id: optionLabel
                anchors.centerIn: parent
                text: modelData.label
                color: parent.chosen ? settings.foreground : settings.dim
                font.family: settings.fontFamily
                font.pixelSize: Style.font.caption
              }
              HoverHandler { id: optionHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: settings.runRow(row, modelData.value) }
            }
          }
        }
      }
    }
  }

  Component {
    id: infoRow
    Item {
      readonly property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      height: Math.max(Style.space(38), infoValue.implicitHeight + Style.space(14))
      Text {
        textFormat: Text.PlainText
        id: infoTitle
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.4
        elide: Text.ElideRight
        text: row.title || ""
        color: settings.foreground
        font.family: settings.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        textFormat: Text.PlainText
        id: infoValue
        anchors.left: infoTitle.right
        anchors.leftMargin: Style.space(12)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.Wrap
        text: row.value || ""
        color: settings.dim
        font.family: settings.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.rgba(settings.foreground.r, settings.foreground.g, settings.foreground.b, 0.06)
      }
    }
  }

  Component {
    id: noteRow
    Text {
      textFormat: Text.PlainText
      readonly property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      leftPadding: Style.space(14)
      rightPadding: Style.space(14)
      topPadding: Style.space(4)
      wrapMode: Text.Wrap
      text: row.text || ""
      color: settings.dimmer
      font.family: settings.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Component {
    id: actionRow
    Rectangle {
      readonly property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      height: Math.max(Style.space(60), actionText.implicitHeight + Style.space(22))
      radius: Style.cornerRadius
      color: Style.normalFillFor(settings.foreground, settings.accent)
      Column {
        id: actionText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.right: actionButton.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: row.title || ""
          color: settings.foreground
          font.family: settings.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          visible: text !== ""
          text: row.subtitle || ""
          color: settings.dim
          font.family: settings.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Button {
        id: actionButton
        objectName: "setting-" + (row.key || "")
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: row.button || ""
        enabled: row.available !== false
        foreground: settings.foreground
        accent: settings.accent
        fontFamily: settings.fontFamily
        bordered: true
        onClicked: settings.runRow(row, true)
      }
    }
  }

  Component {
    id: linkRow
    Rectangle {
      readonly property var row: parent ? parent.row : ({})
      width: parent ? parent.width : 0
      height: linkColumn.implicitHeight + Style.space(24)
      radius: Style.cornerRadius
      color: Style.normalFillFor(settings.foreground, settings.accent)
      Column {
        id: linkColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          text: row.title || ""
          color: settings.foreground
          font.family: settings.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          text: row.subtitle || ""
          color: settings.dim
          font.family: settings.fontFamily
          font.pixelSize: Style.font.caption
        }
        Row {
          spacing: Style.space(8)
          TextField {
            id: accountName
            objectName: "settingsLinkName"
            width: Style.space(220)
            placeholderText: "Account name, e.g. work"
            foreground: settings.foreground
            accent: settings.accent
            font.family: settings.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Button {
            objectName: "setting-link"
            text: "Link"
            enabled: row.available !== false && accountName.text.trim() !== ""
            foreground: settings.foreground
            accent: settings.accent
            fontFamily: settings.fontFamily
            bordered: true
            onClicked: if (settings.runRow(row, accountName.text.trim())) accountName.text = ""
          }
        }
      }
    }
  }

  Component {
    id: updatesRow
    MaintenanceSettings {
      width: parent ? parent.width : 0
      service: settings.service
      updates: settings.updates
      demoMode: settings.demoMode
      showChatPhotos: false
      foreground: settings.foreground
      accent: settings.accent
      fontFamily: settings.fontFamily
    }
  }
}
