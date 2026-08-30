import { invoke } from '@tauri-apps/api/core'

export async function ping(value: string): Promise<string | null> {
  return await invoke<{ value?: string }>('plugin:vpnservice|ping', {
    payload: {
      value,
    },
  }).then((r) => (r.value ? r.value : null));
}

export interface InvokeResponse {
  errorMsg?: string;
  granted?: boolean;
}

export interface StartVpnRequest {
  ipv4Addr?: string;
  routes?: string[];
  dns?: string;
  disallowedApplications?: string[];
  mtu?: number;
}

export interface VpnStatusResponse {
  running: boolean;
  ipv4Addr?: string;
  routes?: string[];
  dns?: string;
}

export async function prepare_vpn(): Promise<InvokeResponse | null> {
  return await invoke<InvokeResponse>('plugin:vpnservice|prepare_vpn', {})
}

export async function start_vpn(request: StartVpnRequest): Promise<InvokeResponse | null> {
  return await invoke<InvokeResponse>('plugin:vpnservice|start_vpn', {
    ...request,
  })
}

export async function stop_vpn(): Promise<InvokeResponse | null> {
  return await invoke<InvokeResponse>('plugin:vpnservice|stop_vpn', {})
}

export async function get_vpn_status(): Promise<VpnStatusResponse | null> {
  return await invoke<VpnStatusResponse>('plugin:vpnservice|get_vpn_status', {})
}

// Update the ongoing notification with live tunnel throughput (bytes/sec).
// When both rates are 0 the notification falls back to the idle text.
export async function update_notification(rxRate: number, txRate: number): Promise<InvokeResponse | null> {
  return await invoke<InvokeResponse>('plugin:vpnservice|update_notification', { rxRate, txRate })
}

// Sync the native system bars (status bar / navigation bar) with the app theme.
// dark=true keeps light (white) bar icons for the dark theme; dark=false makes
// Android render dark bar icons so they stay readable on the light theme.
export async function set_ui_chrome(dark: boolean): Promise<InvokeResponse | null> {
  return await invoke<InvokeResponse>('plugin:vpnservice|set_ui_chrome', { dark })
}

export interface NotificationStatusResponse {
  granted: boolean;
  enabled: boolean;
}

// Are system notifications usable (runtime permission granted AND the app-wide
// toggle on)? When false the app should surface its own warning + settings jump.
export async function notification_status(): Promise<NotificationStatusResponse | null> {
  return await invoke<NotificationStatusResponse>('plugin:vpnservice|notification_status', {})
}

// Open this app's notification settings screen (fallback: app details page).
export async function open_notification_settings(): Promise<InvokeResponse | null> {
  return await invoke<InvokeResponse>('plugin:vpnservice|open_notification_settings', {})
}
