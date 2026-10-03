import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// L236: with several accounts, sync, notifications and unlinking act on the
// account the card names, not on the open chat's.
TestCase {
  id: testCase
  name: "ServiceAccounts"

  Component { id: serviceComponent; Oma.Service {} }

  function accounts() {
    return [
      { account: "work", label: "work", authenticated: true, online: true, sync_active: true,
        notifications_muted: false },
      { account: "home", label: "home", authenticated: true, online: true, sync_active: true,
        notifications_muted: false }
    ]
  }
  function create() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.ready = true
    service.accounts = accounts()
    service.selectedChatAccount = "work"
    return service
  }
  function finish(process, payload) {
    process.stdout.text = JSON.stringify(payload)
    process.running = false
    process.exited(0)
  }
  function entry(service, name) {
    return service.accounts.find(function(item) { return item.account === name })
  }

  function test_sync_pauses_the_named_account_only() {
    var service = create()
    verify(service.multiAccount)
    verify(service.setOnline(false, "home"))
    var process = findChild(service, "controlProcess")
    compare(process.account, "home")
    compare(JSON.parse(process.payload), { account: "home", online: false })
    finish(process, { ok: true, kind: "sync-mode", account: "home", online: false })
    compare(entry(service, "home").online, false, "the card shows it paused at once")
    compare(entry(service, "work").online, true)
    verify(!service.offlineMode, "the open chat's account keeps syncing")
  }

  function test_sync_without_an_account_is_the_open_chats() {
    var service = create()
    verify(service.setOnline(false))
    compare(findChild(service, "controlProcess").account, "work")
  }

  function test_notifications_mute_the_named_account() {
    var service = create()
    verify(service.setPreference("account_notifications", false, "home"))
    var process = findChild(service, "settingsProcess")
    compare(JSON.parse(process.payload), { account: "home", settings: { account_notifications: false } })
    finish(process, { ok: true, kind: "settings", account: "home", account_notifications: false,
      send_read_receipts: false })
    compare(entry(service, "home").notifications_muted, true)
    compare(entry(service, "work").notifications_muted, false)
  }

  function test_unlink_names_the_account_to_the_helper() {
    var service = create()
    verify(service.unlinkAccount("home", "home"))
    var process = findChild(service, "controlProcess")
    compare(process.command[process.command.length - 1], "unlink-account")
    compare(JSON.parse(process.payload), { name: "home", confirm: "home" })
    verify(!service.unlinkAccount("home", "home"), "one change at a time")
  }
}
