import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// Every option in the settings view writes through the service call that owns
// it; demo mode writes nothing; the narrow layout shows sections, then a page.
TestCase {
  id: testCase
  name: "SettingsView"
  width: 1000
  height: 700
  visible: true
  when: windowShown

  Component {
    id: serviceComponent
    Item {
      property bool settingsWriting: false
      property bool controlWriting: false
      property bool statusReady: true
      property bool offlineMode: false
      property bool multiAccount: false
      property bool sendReadReceipts: true
      property bool readOnReply: true
      property bool enterSends: true
      property bool showAvatars: true
      property bool autoRefreshAvatars: true
      property bool autoDownloadMedia: true
      property bool notificationsEnabled: true
      property bool notificationsPreview: true
      property bool notificationsSound: true
      property bool notifyAvailable: true
      property bool showUnreadCount: true
      property int dropdownRows: 7
      property string railDensity: "comfortable"
      property var accounts: [{ account: "", label: "primary", authenticated: true, online: true, sync_active: true }]
      property var about: ({ app_version: "0.14.0", install_mode: "standalone", wacli_version: "0.18.3",
        stores: [{ account: "", label: "primary", database_bytes: 2097152, media_bytes: 1048576, media_files: 3 }],
        avatar_cache_bytes: 4096 })
      property bool aboutLoading: false
      property var accountOperations: QtObject {
        property bool linkBusy: false
        property bool avatarBusy: false
        property string statusMessage: ""
        property int refreshes: 0
        property string linked: ""
        function refreshAvatars() { refreshes += 1; return true }
        function linkAccount(name) { linked = name; return true }
        function linkMainAccount(name) { linked = "main:" + name; return true }
      }
      property var calls: []
      function record(name, args) { calls = calls.concat([{ name: name, args: args }]) }
      function setPreference(key, value, account) {
        record("setPreference", account === undefined ? [key, value] : [key, value, account]); return true }
      function setNotifications(enabled, preview, sound) {
        record("setNotifications", [enabled, preview, sound === undefined ? null : sound]); return true }
      function setAutoDownloadMedia(enabled) { record("setAutoDownloadMedia", [enabled]); return true }
      function setOnline(online, account) {
        record("setOnline", account === undefined ? [online] : [online, account]); return true }
      function unlinkAccount(name, confirm) { record("unlinkAccount", [name, confirm]); return true }
      property bool setupAgents: true
      property bool setupKnown: true
      property bool setupWriting: false
      property var lastTeardown: null
      property string pluginId: "io.github.moizibnyousaf.omawhatsapp"
      function runSetup(agents, replaceOriginal) { record("runSetup", [agents, replaceOriginal]); return true }
      function removeFromComputer() { record("removeFromComputer", []); return true }
      function removePlugin() { record("removePlugin", []); return true }
      property bool startAtLogin: true
      function quitApp() { record("quitApp", []); return true }
      property int aboutRequests: 0
      function refreshAbout() { aboutRequests += 1; return true }
    }
  }

  Component {
    id: appStub
    Item {
      property string demoTimeFormat: "auto"
      property string timeFormat: "auto"
      property int composerMaxLines: 6
      property int quits: 0
      function quitApp() { quits += 1; return true }
    }
  }

  Component {
    id: viewComponent
    Oma.SettingsView { width: 1000; height: 700 }
  }

  function create(extra) {
    var service = createTemporaryObject(serviceComponent, testCase)
    var app = createTemporaryObject(appStub, testCase)
    var props = { service: service, app: app }
    for (var key in (extra || {})) props[key] = extra[key]
    var view = createTemporaryObject(viewComponent, testCase, props)
    verify(view !== null)
    return { view: view, service: service, app: app }
  }

  function last(service) { return service.calls[service.calls.length - 1] }

  function test_sections_cover_every_area() {
    var h = create()
    compare(h.view.sections.map(function(item) { return item.id }),
      ["reading", "notifications", "chats", "media", "sync", "accounts", "updates", "shortcuts", "about"])
    for (var i = 0; i < h.view.sections.length; i++)
      verify(h.view.rowsFor(h.view.sections[i].id).length > 0, h.view.sections[i].id)
  }

  function test_each_toggle_writes_through_its_owner() {
    var h = create()
    var cases = [
      ["reading", "send_read_receipts", "setPreference", ["send_read_receipts", false]],
      ["reading", "read_on_reply", "setPreference", ["read_on_reply", false]],
      ["notifications", "notify", "setNotifications", [false, null, null]],
      ["notifications", "notify_sound", "setNotifications", [null, null, false]],
      ["notifications", "show_unread_count", "setPreference", ["show_unread_count", false]],
      ["chats", "enter_sends", "setPreference", ["enter_sends", false]],
      ["chats", "show_avatars", "setPreference", ["show_avatars", false]],
      ["media", "auto_download_media", "setAutoDownloadMedia", [false]],
      ["media", "auto_refresh_avatars", "setPreference", ["auto_refresh_avatars", false]],
      ["sync", "online", "setOnline", [false]],
      ["sync", "start_at_login", "setPreference", ["start_at_login", false]]
    ]
    for (var i = 0; i < cases.length; i++) {
      h.view.openSection(cases[i][0])
      wait(0)
      var toggle = findChild(h.view, "setting-" + cases[i][1])
      verify(toggle !== null, cases[i][1])
      toggle.toggled()
      compare(last(h.service).name, cases[i][2], cases[i][1])
      compare(last(h.service).args, cases[i][3], cases[i][1])
    }
  }

  function test_choices_write_their_value() {
    var h = create()
    h.view.openSection("chats")
    wait(0)
    var compact = findChild(h.view, "settingChoice-rail_density-compact")
    verify(compact !== null)
    mouseClick(compact, compact.width / 2, compact.height / 2)
    compare(last(h.service).args, ["rail_density", "compact"])
    var lines = findChild(h.view, "composerLineLimit10")
    mouseClick(lines, lines.width / 2, lines.height / 2)
    compare(last(h.service).args, ["composer_max_lines", 10])
    h.view.openSection("notifications")
    wait(0)
    var rows = findChild(h.view, "settingChoice-dropdown_rows-9")
    mouseClick(rows, rows.width / 2, rows.height / 2)
    compare(last(h.service).args, ["dropdown_rows", 9])
  }

  function test_media_action_and_account_link_reach_account_operations() {
    var h = create()
    h.view.openSection("media")
    wait(0)
    findChild(h.view, "setting-refresh_avatars").clicked()
    compare(h.service.accountOperations.refreshes, 1)
    h.view.openSection("accounts")
    wait(0)
    findChild(h.view, "settingsLinkName").text = "work"
    findChild(h.view, "setting-link").clicked()
    compare(h.service.accountOperations.linked, "work")
  }

  function test_storage_and_versions_come_from_about() {
    var h = create()
    h.view.openSection("sync")
    verify(h.service.aboutRequests >= 1)
    var titles = h.view.rowsFor("sync").map(function(row) { return row.title + "=" + (row.value || "") })
    verify(titles.indexOf("Messages=2.0 MB") >= 0, titles.join(" | "))
    verify(titles.indexOf("Downloaded media=1.0 MB · 3 files") >= 0, titles.join(" | "))
    var about = h.view.rowsFor("about").map(function(row) { return row.value || "" })
    verify(about[0].indexOf("0.14.0") === 0)
    verify(about[1].indexOf("0.18.3") === 0)
  }

  function test_demo_mode_writes_nothing_and_keeps_time_format_local() {
    var h = create({ demoMode: true })
    h.view.openSection("chats")
    wait(0)
    findChild(h.view, "setting-enter_sends").toggled()
    var option = findChild(h.view, "timeFormatChoice24h")
    mouseClick(option, option.width / 2, option.height / 2)
    compare(h.service.calls.length, 0)
    compare(h.app.demoTimeFormat, "24h")
  }

  function test_demo_mode_shows_demo_storage_not_this_machine() {
    var h = create({ demoMode: true })
    var values = h.view.rowsFor("sync").map(function(row) { return row.value || "" })
    verify(values.indexOf("18.0 MB") >= 0, values.join(" | "))
    verify(values.indexOf("2.0 MB") < 0, "the service's real figures stay out of demo captures")
  }

  function test_reopening_the_narrow_view_starts_at_the_section_list() {
    var h = create({ narrow: true })
    h.view.openSection("about")
    h.view.visible = false
    h.view.visible = true
    verify(findChild(h.view, "settingsSections").visible)
  }

  function test_narrow_layout_shows_sections_then_a_page() {
    var h = create({ narrow: true })
    var sections = findChild(h.view, "settingsSections")
    var page = findChild(h.view, "settingsPage")
    verify(sections.visible)
    verify(!page.visible)
    h.view.openSection("media")
    verify(!sections.visible)
    verify(page.visible)
  }

  function test_quit_lives_with_sync_and_goes_through_the_app() {
    var h = create()
    h.view.openSection("sync")
    wait(0)
    verify(h.view.runRow({ key: "quit" }, true))
    compare(h.app.quits, 1, "the app closes its window and quits")
  }

  readonly property var twoAccounts: [
    { account: "work", label: "work", main: true, authenticated: true, online: true,
      sync_active: true, notifications_muted: false },
    { account: "home", label: "home", main: false, authenticated: true, online: true,
      sync_active: true, notifications_muted: false }
  ]

  function test_each_account_has_its_own_card_and_switches() {
    var h = create()
    h.service.accounts = twoAccounts
    h.view.openSection("accounts")
    wait(0)
    verify(findChild(h.view, "accountCard-work") !== null)
    verify(findChild(h.view, "accountCard-home") !== null)
    var workDot = findChild(h.view, "accountDot-work")
    var homeDot = findChild(h.view, "accountDot-home")
    verify(workDot.visible && homeDot.visible, "several accounts show their color")
    verify(!Qt.colorEqual(workDot.color, homeDot.color), "each account keeps its own color")
    findChild(h.view, "accountSync-home").toggled()
    compare(last(h.service).name, "setOnline")
    compare(last(h.service).args, [false, "home"], "only that account pauses")
    findChild(h.view, "accountNotify-home").toggled()
    compare(last(h.service).name, "setPreference")
    compare(last(h.service).args, ["account_notifications", false, "home"])
  }

  function test_one_account_has_no_color_or_notification_switch() {
    var h = create()
    h.view.openSection("accounts")
    wait(0)
    verify(!findChild(h.view, "accountDot-").visible)
    verify(!findChild(h.view, "accountNotify-").visible, "the Notifications section already covers it")
    verify(findChild(h.view, "accountSync-").visible)
  }

  function test_unlink_asks_first_and_names_the_account() {
    var h = create()
    h.service.accounts = twoAccounts
    h.view.openSection("accounts")
    wait(0)
    var calls = h.service.calls.length
    findChild(h.view, "accountUnlink-home").clicked()
    compare(h.service.calls.length, calls, "the first click only asks")
    verify(findChild(h.view, "accountConfirm-home").visible)
    verify(!findChild(h.view, "accountConfirm-work").visible, "only that account asks")
    compare(findChild(h.view, "accountUnlinkConfirm-home").text, "Unlink home")
    findChild(h.view, "accountUnlinkCancel-home").clicked()
    verify(!findChild(h.view, "accountConfirm-home").visible)
    compare(h.service.calls.length, calls)
    findChild(h.view, "accountUnlink-home").clicked()
    findChild(h.view, "accountUnlinkConfirm-home").clicked()
    compare(last(h.service).name, "unlinkAccount")
    compare(last(h.service).args, ["home", "home"])
    verify(!findChild(h.view, "accountConfirm-home").visible)
  }

  function test_leaving_the_section_drops_a_pending_unlink() {
    var h = create()
    h.service.accounts = twoAccounts
    h.view.openSection("accounts")
    wait(0)
    findChild(h.view, "accountUnlink-home").clicked()
    compare(h.view.unlinkConfirming, "home")
    h.view.openSection("sync")
    compare(h.view.unlinkConfirming, "", "no confirmation waits out of sight")
  }

  function test_an_account_that_is_not_linked_offers_to_link_it() {
    var h = create()
    h.service.accounts = [
      { account: "primary", label: "primary", main: true, authenticated: false, online: true },
      { account: "home", label: "home", main: false, authenticated: false, online: true }
    ]
    h.view.openSection("accounts")
    wait(0)
    compare(findChild(h.view, "accountState-home").text, "Not linked")
    verify(!findChild(h.view, "accountSync-home").visible)
    findChild(h.view, "accountLink-primary").clicked()
    compare(h.service.accountOperations.linked, "main:primary", "the main account links with wacli auth")
    findChild(h.view, "accountLink-home").clicked()
    compare(h.service.accountOperations.linked, "home")
  }

  function test_agents_can_be_turned_off_from_settings() {
    var h = create()
    h.view.openSection("sync")
    wait(0)
    var toggle = findChild(h.view, "setting-agents")
    verify(toggle.checked)
    toggle.toggled()
    compare(last(h.service).name, "runSetup")
    compare(last(h.service).args, [false, false])
  }

  function test_removing_from_this_computer_asks_first() {
    var h = create()
    h.view.openSection("sync")
    wait(0)
    var calls = h.service.calls.length
    verify(!h.view.runRow({ key: "remove_setup" }, true), "the first click only asks")
    compare(h.service.calls.length, calls)
    verify(h.view.removeConfirming)
    verify(h.view.runRow({ key: "remove_setup" }, true))
    compare(last(h.service).name, "removeFromComputer")
    verify(!h.view.removeConfirming)
    verify(findChild(h.view, "setting-remove_plugin") === null, "the app itself only after that")
    h.service.lastTeardown = { ok: true, remove_command: "omarchy plugin remove io.github.moizibnyousaf.omawhatsapp" }
    wait(0)
    findChild(h.view, "setting-remove_plugin").clicked()
    compare(last(h.service).name, "removePlugin")
  }

  function test_files_the_removal_left_are_named() {
    var h = create()
    function notes() {
      return h.view.rowsFor("sync").filter(function(row) { return row.kind === "note" })
        .map(function(row) { return row.text }).join("\n")
    }
    h.service.lastTeardown = { ok: true, kept: [] }
    verify(notes().indexOf("Left as they were") < 0, "nothing is named when nothing was left")
    h.service.lastTeardown = { ok: true, kept: ["/home/u/.config/systemd/user/wacli-sync@.service"] }
    verify(notes().indexOf("Left as they were") >= 0, notes())
    verify(notes().indexOf("/home/u/.config/systemd/user/wacli-sync@.service") >= 0, notes())
  }

  function test_a_pending_removal_is_dropped_when_leaving() {
    var h = create()
    h.view.openSection("sync")
    wait(0)
    h.view.runRow({ key: "remove_setup" }, true)
    verify(h.view.removeConfirming)
    h.view.openSection("reading")
    verify(!h.view.removeConfirming)
  }
}
