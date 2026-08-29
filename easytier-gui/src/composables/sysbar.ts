import { watch, type Ref } from 'vue'
import { type } from '@tauri-apps/plugin-os'
import { set_ui_chrome } from 'tauri-plugin-vpnservice-api'

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

  const apply = (theme: string) => {
    set_ui_chrome(theme === 'm3Dark').catch((err) => {
      console.warn('set_ui_chrome failed:', err)
    })
  }

  // adopt the current theme once, then follow every switch
  apply(themeRef.value)
  watch(themeRef, (theme) => apply(theme))
}
