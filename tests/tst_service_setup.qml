import QtQuick
import QtTest
import "../plugins/omawhatsapp" as Oma

// After omarchy plugin add, the first run sets up what lives outside the
// plugin folder. The app asks once; consent already given, or an install by
// the old script, is applied by itself; replacing OmaWhatsApp always asks.
TestCase {
  id: testCase
  name: "ServiceSetup"

  Component { id: serviceComponent; Oma.Service { manifest: ({ id: "io.github.atoslins.whatsapp", version: "0.15.0" }) } }

  function status(service, setup, extra) {
    var process = findChild(service, "statusProcess")
    var payload = { ok: true, installed: true, authenticated: true, database_ready: true,
      sync_active: true, any_authenticated: true, account: "", accounts: [],
      helper_version: "0.15.0", setup: setup }
    for (var key in (extra || {})) payload[key] = extra[key]
    process.stdout.text = JSON.stringify(payload)
    process.stderr.text = ""
    process.running = false
    process.exited(0)
  }
  function setup(extra) {
    var value = { consented: false, agents: true, previous_install: false, complete: false,
      units: "missing", links: {}, legacy_copies: false, zenity: true,
      wacli: { path: "/usr/bin/wacli", found: true },
      original_plugin: { installed: false, enabled: false } }
    for (var key in (extra || {})) value[key] = extra[key]
    return value
  }
  function finishSetup(service, result) {
    var process = findChild(service, "setupProcess")
    process.stdout.text = JSON.stringify(result)
    process.stderr.text = ""
    process.running = false
    process.exited(0)
  }

  function test_the_helper_comes_from_the_checkout() {
    var service = createTemporaryObject(serviceComponent, testCase)
    verify(service.helper.charAt(0) === "/", service.helper)
    verify(/\/bin\/omawhatsapp$/.test(service.helper), service.helper)
    verify(service.helper.indexOf(".local/bin") < 0, "never a copy in ~/.local/bin")
  }

  function test_a_fresh_install_asks_before_writing_anything() {
    var service = createTemporaryObject(serviceComponent, testCase)
    status(service, setup())
    verify(service.needsSetup)
    verify(service.needsOnboarding)
    verify(!findChild(service, "setupProcess").running, "nothing runs without consent")
    verify(service.runSetup(true, false))
    var process = findChild(service, "setupProcess")
    compare(process.command[process.command.length - 1], "setup")
    compare(JSON.parse(process.payload), { agents: true, replace_original: false })
    finishSetup(service, { ok: true, kind: "setup", setup: setup({ consented: true, complete: true, units: "ok" }) })
    verify(!service.needsSetup)
  }

  function test_given_consent_or_an_old_install_is_applied_by_itself() {
    var service = createTemporaryObject(serviceComponent, testCase)
    status(service, setup({ previous_install: true, units: "ok", legacy_copies: true }))
    verify(!service.needsSetup, "an install by the old script already had consent")
    var process = findChild(service, "setupProcess")
    verify(process.running, "it moves to links by itself")
    compare(JSON.parse(process.payload), { agents: null, replace_original: false })
    finishSetup(service, { ok: false, error: "boom" })
    status(service, setup({ previous_install: true, units: "ok", legacy_copies: true }))
    verify(!process.running, "one automatic try per session, never a loop")
  }

  function test_replacing_the_original_always_asks() {
    var service = createTemporaryObject(serviceComponent, testCase)
    status(service, setup({ previous_install: true, units: "stale",
      original_plugin: { installed: true, enabled: true } }))
    verify(service.originalPluginEnabled)
    verify(service.needsSetup)
    verify(!findChild(service, "setupProcess").running)
    verify(service.runSetup(true, true))
    compare(JSON.parse(findChild(service, "setupProcess").payload), { agents: true, replace_original: true })
  }

  function test_without_wacli_the_welcome_says_what_to_install() {
    var service = createTemporaryObject(serviceComponent, testCase)
    var process = findChild(service, "statusProcess")
    process.stdout.text = JSON.stringify({ ok: false, installed: false, error: "wacli is not installed.",
      helper_version: "0.15.0", setup: setup({ wacli: { path: "/home/u/.local/bin/wacli", found: false } }) })
    process.running = false
    process.exited(1)
    verify(!service.wacliInstalled)
    verify(service.needsOnboarding)
    verify(!findChild(service, "setupProcess").running)
  }

  function test_removing_keeps_the_archive_and_offers_the_plugin_removal() {
    var service = createTemporaryObject(serviceComponent, testCase)
    var done = []
    service.setupCompleted.connect(function(kind) { done.push(kind) })
    verify(service.removeFromComputer())
    compare(JSON.parse(findChild(service, "setupProcess").payload), { confirm: "remove" })
    finishSetup(service, { ok: true, kind: "teardown", removed: ["x"],
      remove_command: "omarchy plugin remove io.github.atoslins.whatsapp" })
    compare(done, ["teardown"])
    compare(service.lastTeardown.remove_command, "omarchy plugin remove io.github.atoslins.whatsapp")
  }

  function test_an_old_wacli_keeps_the_welcome_until_it_is_updated() {
    var service = createTemporaryObject(serviceComponent, testCase)
    var process = findChild(service, "statusProcess")
    process.stdout.text = JSON.stringify({ ok: false, installed: true, wacli_too_old: true,
      wacli_version: "0.16.9", error: "wacli 0.16.9 is older than 0.17.1", helper_version: "0.15.0",
      setup: setup() })
    process.running = false
    process.exited(1)
    verify(service.wacliTooOld)
    compare(service.wacliVersion, "0.16.9")
    verify(service.needsOnboarding)
    status(service, setup({ consented: true, complete: true, units: "ok" }), { wacli_version: "0.19.0" })
    verify(!service.wacliTooOld)
    verify(!service.needsOnboarding)
  }

  function test_a_path_of_something_else_is_never_set_up_by_itself() {
    var service = createTemporaryObject(serviceComponent, testCase)
    status(service, setup({ consented: true, units: "ok",
      conflicts: ["/home/u/.local/bin/omawhatsapp"] }))
    compare(service.setupConflicts, ["/home/u/.local/bin/omawhatsapp"])
    verify(!findChild(service, "setupProcess").running, "no automatic try while it is there")
    verify(service.needsSetup, "the welcome says what to move")
  }
}
