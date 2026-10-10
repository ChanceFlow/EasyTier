import { type } from '@tauri-apps/plugin-os'
import { notification_status, open_notification_settings, update_notification } from 'tauri-plugin-vpnservice-api'
import { ref } from 'vue'
import { clearNotificationDegraded, reportNotificationDegraded } from './mobile_vpn'

/**
 * Android hides EVERYTHING — even foreground-service notifications — while
 * POST_NOTIFICATIONS is ungranted or the app-wide toggle is off, and the
 * one-shot cold-start dialog is easy to miss. This gate re-checks on every
 * resume and lets the hero surface a tap-through warning card instead of
 * failing silently.
 */
export const notificationsBlocked = ref(false)

/** Re-post the idle keepalive note, reporting (once) if the command is broken. */
async function repostIdleNotification(): Promise<void> {
  try {
    await update_notification(0, 0, false)
    clearNotificationDegraded('update_notification')
  }
  catch (error) {
    reportNotificationDegraded('update_notification', error)
  }
}

export async function checkNotificationGate(): Promise<void> {
  if (type() !== 'android') {
    return
  }
  try {
    const st = await notification_status()
    clearNotificationDegraded('notification_status')
    if (!st) {
      return
    }
    notificationsBlocked.value = !(st.granted && st.enabled)
    if (!notificationsBlocked.value) {
      // allowed but possibly never shown (service posted before the grant,
      // or its start path hiccuped): re-post the idle keepalive note now
      await repostIdleNotification()
    }
  }
  catch (error) {
    // NOT the same thing as the user having notifications turned off: the
    // plugin is absent (non-tauri preview) or the command was rejected — a Tauri
    // ACL denial on `notification_status` is exactly what kept this gate
    // permanently silent in the field. The blocked card would be a lie, so leave
    // `notificationsBlocked` untouched and record a diagnosable degraded state
    // instead of swallowing the error with a bare catch.
    reportNotificationDegraded('notification_status', error)
  }
}

export async function openNotificationSettings(): Promise<void> {
  try {
    await open_notification_settings()
    clearNotificationDegraded('open_notification_settings')
  }
  catch (error) {
    reportNotificationDegraded('open_notification_settings', error)
  }
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
