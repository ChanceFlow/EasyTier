import { type } from '@tauri-apps/plugin-os'
import { notification_status, open_notification_settings, update_notification } from 'tauri-plugin-vpnservice-api'
import { ref } from 'vue'

/**
 * Android hides EVERYTHING — even foreground-service notifications — while
 * POST_NOTIFICATIONS is ungranted or the app-wide toggle is off, and the
 * one-shot cold-start dialog is easy to miss. This gate re-checks on every
 * resume and lets the hero surface a tap-through warning card instead of
 * failing silently.
 */
export const notificationsBlocked = ref(false)

export async function checkNotificationGate(): Promise<void> {
  if (type() !== 'android') {
    return
  }
  try {
    const st = await notification_status()
    if (!st) {
      return
    }
    notificationsBlocked.value = !(st.granted && st.enabled)
    if (!notificationsBlocked.value) {
      // allowed but possibly never shown (service posted before the grant,
      // or its start path hiccuped): re-post the idle keepalive note now
      await update_notification(0, 0).catch(() => {})
    }
  }
  catch {
    // plugin unavailable (e.g. non-tauri preview): never nag
  }
}

export async function openNotificationSettings(): Promise<void> {
  await open_notification_settings().catch(() => {})
  // coming back from the settings screen fires visibilitychange too, but the
  // return can be instant on some ROMs - re-probe once after a beat as well
  window.setTimeout(() => {
    void checkNotificationGate()
  }, 1500)
}

if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      void checkNotificationGate()
    }
  })
}
