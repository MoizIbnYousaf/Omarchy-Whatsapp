.pragma library

// Keep receipt decisions small, explicit, and independently testable. Merely
// reading OmaWhatsApp's local mirror must never become a WhatsApp write.
function shouldSendAutomaticReceipt(enabled, offline, writing) {
  return enabled === true && offline !== true && writing !== true
}

// Opening the warm full window counts as viewing its already-selected chat,
// unless an exact-chat request is still resolving or already selected it.
// Demo mode must remain completely detached from the user's real account.
function shouldSelectWarmChat(demoMode, selectedFromPayload, pendingJid, selectedJid) {
  return demoMode !== true
    && selectedFromPayload !== true
    && String(pendingJid || "") === ""
    && String(selectedJid || "") !== ""
}
