import { watch, type Ref } from 'vue'
import { type } from '@tauri-apps/plugin-os'
import { set_ui_chrome } from 'tauri-plugin-vpnservice-api'
import { clearNotificationDegraded, reportNotificationDegraded } from './mobile_vpn'

/**
 * Keep the Android status/navigation bar icons in sync with the Vuetify theme.
 * Light theme -> dark bar icons (readable on #eef1f6); dark theme -> light bar
 * icons (readable on #07080a). No-op on every other platform.
 *
 * The native contract is `set_ui_chrome({ dark })` where `dark` means "the app
 * is in dark theme"; the plugin then sets isAppearanceLightStatusBars = !dark.
 */
export function initSysBarSync(themeRef: Ref<string>) {
  if (type() !== 'android')
    return

  const apply = async (theme: string) => {
    try {
      await set_ui_chrome(theme === 'm3Dark')
      clearNotificationDegraded('set_ui_chrome')
    }
    catch (error) {
      // used to be a bare console.warn; this command has been ACL-rejected in
      // the field, so it shares the same once-per-outage degraded state as the
      // notification commands (visible on mobileStats.notificationDegraded)
      reportNotificationDegraded('set_ui_chrome', error)
    }
  }

  // adopt the current theme once, then follow every switch
  void apply(themeRef.value)
  watch(themeRef, (theme) => { void apply(theme) })
}
