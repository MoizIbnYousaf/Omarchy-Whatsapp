import QtQuick
import QtTest
import "../plugins/omawhatsapp/SettingsPolicy.js" as SettingsPolicy

TestCase {
  name: "SettingsPolicy"

  function test_private_reading_never_sends_automatically() {
    compare(SettingsPolicy.shouldSendAutomaticReceipt(false, false, false), false)
    compare(SettingsPolicy.shouldSendAutomaticReceipt(false, true, false), false)
    compare(SettingsPolicy.shouldSendAutomaticReceipt(false, false, true), false)
  }

  function test_opted_in_receipts_respect_offline_and_busy_guards() {
    compare(SettingsPolicy.shouldSendAutomaticReceipt(true, false, false), true)
    compare(SettingsPolicy.shouldSendAutomaticReceipt(true, true, false), false)
    compare(SettingsPolicy.shouldSendAutomaticReceipt(true, false, true), false)
  }

  function test_warm_chat_selection_is_exact_and_demo_safe() {
    compare(SettingsPolicy.shouldSelectWarmChat(false, false, "", "team@example"), true)
    compare(SettingsPolicy.shouldSelectWarmChat(true, false, "", "team@example"), false)
    compare(SettingsPolicy.shouldSelectWarmChat(false, true, "", "team@example"), false)
    compare(SettingsPolicy.shouldSelectWarmChat(false, false, "pending@example", "team@example"), false)
    compare(SettingsPolicy.shouldSelectWarmChat(false, false, "", ""), false)
  }
}
