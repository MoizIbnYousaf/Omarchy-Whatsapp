import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// A message landing in the mirror pops its notification right away instead of
// waiting for the 12-second tick, and a burst folds into one helper pass.
TestCase {
  id: testCase
  name: "ServiceNotify"

  Component { id: serviceComponent; Oma.Service {} }

  function createService() {
    var service = createTemporaryObject(serviceComponent, testCase)
    service.railReady = true
    service.notificationsEnabled = true
    var process = findChild(service, "notifyProcess")
    tryVerify(function() { return process.running }, 2000, "the startup tick runs once")
    process.running = false
    process.exited(0)
    return service
  }

  function test_a_store_change_notifies_without_waiting_for_the_tick() {
    var service = createService()
    var process = findChild(service, "notifyProcess")
    verify(!process.running)
    service.refreshFromStore()
    service.refreshFromStore()
    service.refreshFromStore()
    verify(!process.running, "a burst waits for the debounce")
    tryVerify(function() { return process.running }, 3000)
  }

  function test_a_change_during_a_pass_runs_one_more_pass() {
    var service = createService()
    var process = findChild(service, "notifyProcess")
    service.runNotify()
    verify(process.running)
    service.runNotify()
    verify(service.notifyPending)
    process.running = false
    process.exited(0)
    tryVerify(function() { return process.running }, 3000, "the pending pass runs")
    verify(!service.notifyPending)
  }

  function test_nothing_runs_with_notifications_off() {
    var service = createService()
    var process = findChild(service, "notifyProcess")
    service.notificationsEnabled = false
    service.refreshFromStore()
    wait(1300)
    verify(!process.running)
  }
  // The owner asked for a way to silence notifications from the bar icon.
  function finishControl(service, enabled) {
    var control = findChild(service, "controlProcess")
    control.stdout.text = JSON.stringify({ ok: true, kind: "notify-mode",
      notifications: { enabled: enabled, preview: true, sound: true } })
    control.running = false
    control.exited(0)
  }

  function test_right_click_mutes_at_once_through_the_settings_switch() {
    var service = createService()
    var control = findChild(service, "controlProcess")
    verify(!service.notificationsMuted)
    verify(service.toggleNotificationsMuted())
    verify(service.notificationsMuted, "the bar shows the mute before the helper answers")
    compare(service.notificationsEnabled, false)
    compare(service.lastOsdMessage, "WhatsApp notifications muted")
    compare(control.command[1], "notify-mode")
    compare(JSON.parse(control.payload).enabled, false)
    compare(JSON.parse(control.payload).preview, undefined, "only the switch changes")
    finishControl(service, false)
    service.refreshFromStore()
    wait(1300)
    verify(!findChild(service, "notifyProcess").running, "no popup and no sound while muted")
  }

  function test_right_click_again_unmutes() {
    var service = createService()
    verify(service.toggleNotificationsMuted())
    finishControl(service, false)
    verify(service.toggleNotificationsMuted())
    verify(!service.notificationsMuted)
    compare(service.lastOsdMessage, "WhatsApp notifications on")
    compare(JSON.parse(findChild(service, "controlProcess").payload).enabled, true)
    finishControl(service, true)
    service.refreshFromStore()
    tryVerify(function() { return findChild(service, "notifyProcess").running }, 3000)
  }

  function test_a_mute_during_a_send_waits_for_it_and_then_applies() {
    var service = createService()
    var control = findChild(service, "controlProcess")
    service.writing = true
    verify(!service.toggleNotificationsMuted())
    verify(service.notificationsMuted, "the bar already shows the mute")
    compare(service.lastOsdMessage, "WhatsApp notifications muted")
    wait(400)
    verify(!control.running, "the settings write waits for the send")
    service.writing = false
    tryVerify(function() { return control.running }, 1000)
    compare(JSON.parse(control.payload).enabled, false)
    verify(!service.notificationsEnabled)
    verify(service.notificationsMuted)
  }

  function test_a_status_read_in_flight_does_not_undo_the_mute() {
    var service = createService()
    verify(service.toggleNotificationsMuted())
    var status = findChild(service, "statusProcess")
    status.stdout.text = JSON.stringify({ ok: true, account: "", authenticated: true,
      notifications: { enabled: true, preview: true, sound: true } })
    status.exited(0)
    verify(service.notificationsMuted, "an answer read before the write keeps the mute")
    finishControl(service, false)
    status.exited(0)
    compare(service.notificationsEnabled, true, "later status answers apply again")
  }
}
