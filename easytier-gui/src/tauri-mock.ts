/**
 * Dev-only Tauri API mock so the redesigned GUI can be previewed in a plain
 * browser (http://127.0.0.1:1420) without the
 * Tauri webview runtime.
 *
 * It installs `window.__TAURI_INTERNALS__` (the single entry point used by
 * @tauri-apps/api and all plugins) with canned responses for every command the
 * GUI calls at boot. This file is only imported in development builds.
 *
 * NOTE: this module intentionally does NOT import `easytier-frontend-lib`
 * (or anything heavy) — doing so triggers Vite runtime dep re-optimization
 * and makes the dev server stall on first browser load.
 */

declare global {
  interface Window {
    __TAURI_INTERNALS__?: {
      invoke: (cmd: string, args?: any, options?: any) => Promise<unknown>
      [key: string]: any
    }
    // __TAURI_OS_PLUGIN_INTERNALS__ is declared by @tauri-apps/plugin-os itself.
  }
}

const RUNNING_INSTANCE = {
  instance_id: 'a1b2c3d4-1111-2222-3333-444455556666',
}

const DISABLED_INSTANCE = {
  instance_id: 'a1b2c3d4-aaaa-bbbb-cccc-ddddeeeeffff',
}

function defaultNetworkConfig() {
  // Minimal stand-in for easytier-frontend-lib DEFAULT_NETWORK_CONFIG()
  return {
    instance_id: '',
    dhcp: true,
    virtual_ipv4: '',
    network_length: 24,
    network_name: 'easytier',
    network_secret: '',
    credential_file: '',
    networking_method: 1,
    public_server_url: '',
    peer_urls: [],
    proxy_cidrs: [],
    advanced_settings: false,
    listener_urls: ['tcp://0.0.0.0:11010', 'udp://0.0.0.0:11010', 'wg://0.0.0.0:11011'],
    latency_first: false,
    dev_name: '',
    use_smoltcp: false,
    disable_ipv6: false,
    ipv6_public_addr_auto: false,
    enable_kcp_proxy: false,
    disable_kcp_input: false,
    enable_quic_proxy: false,
    disable_quic_input: false,
    disable_p2p: false,
    p2p_only: false,
    lazy_p2p: false,
    bind_device: true,
    no_tun: false,
    enable_exit_node: false,
    relay_all_peer_rpc: false,
    need_p2p: false,
    multi_thread: true,
    proxy_forward_by_system: false,
    disable_encryption: false,
    disable_tcp_hole_punching: false,
    disable_udp_hole_punching: false,
    disable_upnp: false,
    enable_udp_broadcast_relay: false,
    disable_sym_hole_punching: false,
    enable_relay_network_whitelist: false,
    relay_network_whitelist: [],
    enable_manual_routes: false,
    routes: [],
    exit_nodes: [],
    enable_socks5: false,
    socks5_port: 1080,
    mtu: null,
    instance_recv_bps_limit: null,
    mapped_listeners: [],
    enable_magic_dns: false,
    enable_private_mode: false,
    port_forwards: [],
    acl: {
      acl_v1: {
        chains: [],
        group: { declares: [], members: [] },
      },
    },
  }
}

const NETWORK_CONFIG = {
  ...defaultNetworkConfig(),
  network_name: 'mesh-office',
  virtual_ipv4: '10.11.12.13',
  network_length: 24,
  network_secret: 'demo-secret',
  hostname: 'office-router',
  listener_urls: ['tcp://0.0.0.0:11010', 'udp://0.0.0.0:11010', 'wg://0.0.0.0:11011'],
  enable_relay_network_whitelist: true,
  relay_network_whitelist: ['mesh-home', 'mesh-office'],
  enable_manual_routes: true,
  routes: ['192.168.10.0/24', '192.168.20.0/24'],
  enable_socks5: true,
  socks5_port: 1086,
  enable_exit_node: true,
  dev_name: 'tun1',
  mtu: 1380,
}

const RUNNING_DETAIL = {
  dev_name: 'tun0',
  running: true,
  error_msg: '',
  events: [
    JSON.stringify({ time: new Date(Date.now() - 90000).toISOString(), event: { PeerAdded: { peer_id: 2 } } }),
    JSON.stringify({ time: new Date(Date.now() - 30000).toISOString(), event: { PeerConnAdded: { peer_id: 2 } } }),
  ],
  routes: [],
  peers: [],
  peer_route_pairs: [
    {
      route: {
        ipv4_addr: { address: { addr: 0x0a000001 }, network_length: 24 },
        hostname: 'nas-01',
        version: '2.2.0',
        stun_info: { udp_nat_type: 3, tcp_nat_type: 3, last_update_time: 0 },
        cost: 1,
      },
      peer: {
        id: 2,
        uuid: { part1: 0, part2: 0, part3: 0, part4: 2 },
        hostname: 'nas-01',
        conns: [
          {
            conn_id: 1,
            loss_rate: 0.005,
            stats: {
              tx_bytes: '1073741824',
              rx_bytes: '536870912',
              tx_rate: 2048,
              rx_rate: 1024,
              latency_us: 12000,
            },
          },
        ],
        tunnel_infos: [
          {
            tunnel_type: 'udp',
            tunnel_state: 'Connected',
            local_addr: { url: 'tcp://192.168.1.10:11010' },
            remote_addr: { url: 'udp://203.0.113.9:11010' },
            conns: [
              {
                conn_id: 1,
                stats: {
                  tx_bytes: '1048576000',
                  rx_bytes: '536870912',
                  tx_rate: 1024,
                  rx_rate: 512,
                  latency_us: 12000,
                },
              },
            ],
          },
        ],
        is_exit_node: false,
        protocol_version: 1,
      },
    },
    {
      route: {
        ipv4_addr: { address: { addr: 0x0a000002 }, network_length: 24 },
        hostname: 'phone-a',
        version: '2.2.0',
        stun_info: { udp_nat_type: 5, tcp_nat_type: 5, last_update_time: 0 },
        cost: 2,
      },
      peer: {
        id: 3,
        uuid: { part1: 0, part2: 0, part3: 0, part4: 3 },
        hostname: 'phone-a',
        conns: [
          {
            conn_id: 1,
            loss_rate: 0.012,
            stats: {
              tx_bytes: '1073741824',
              rx_bytes: '536870912',
              tx_rate: 1024,
              rx_rate: 512,
              latency_us: 45000,
            },
          },
        ],
        tunnel_infos: [
          {
            tunnel_type: 'udp',
            tunnel_state: 'Connected',
            local_addr: { url: 'tcp://192.168.1.10:11010' },
            remote_addr: { url: 'udp://198.51.100.42:31337' },
            conns: [
              {
                conn_id: 1,
                stats: {
                  tx_bytes: '268435456',
                  rx_bytes: '1073741824',
                  tx_rate: 256,
                  rx_rate: 2048,
                  latency_us: 45000,
                },
              },
            ],
          },
        ],
        is_exit_node: false,
        protocol_version: 1,
      },
    },
  ],
  my_node_info: {
    virtual_ipv4: { address: { addr: 0x0a000064 }, network_length: 24 },
    hostname: 'easytier-gw',
    version: '2.2.0',
    ips: {
      public_ipv4: { addr: 0xc0000201 },
      interface_ipv4s: [{ addr: 0xc0a8010a }],
      public_ipv6: { part1: 0, part2: 0, part3: 0, part4: 0 },
      interface_ipv6s: [],
      listeners: [
        { url: 'tcp://0.0.0.0:11010' },
        { url: 'udp://0.0.0.0:11010' },
        { url: 'wg://0.0.0.0:11011' },
      ],
    },
    stun_info: { udp_nat_type: 3, tcp_nat_type: 3, last_update_time: 0 },
    listeners: [
      { url: 'tcp://0.0.0.0:11010' },
      { url: 'udp://0.0.0.0:11010' },
      { url: 'wg://0.0.0.0:11011' },
    ],
    peer_id: 1,
  },
}

const VPN_PORTAL_INFO = {
  vpn_type: 'wireguard',
  client_config: '',
  connected_clients: [],
  listener: '0.0.0.0:22022',
  clients: [
    {
      name: 'phone-a',
      virtual_ip: '10.1.2.10',
      groups: ['ops'],
      state: 'VPN_PORTAL_CLIENT_STATE_ONLINE',
      peer_id: 7,
      endpoint: '203.0.113.5:51820',
      tunnel_ip: '192.0.2.1',
      client_config: '[Interface]\nPrivateKey = mock-private-key\nAddress = 10.1.2.10/24\n\n[Peer]\nPublicKey = mock-public-key\nAllowedIPs = 0.0.0.0/0\nEndpoint = 192.0.2.1:22022\n',
    },
  ],
}

// ---------------------------------------------------------------------------
// Stateful instance store — so create / run / disable / delete flows work in
// the browser preview instead of returning a fixed snapshot.
// ---------------------------------------------------------------------------

interface MockInstance {
  running: boolean
  config: any // stored in the backend (protobuf-json) shape, as received
}

const instances = new Map<string, MockInstance>()

/** Mirrors Utils.StrToUuid from easytier-frontend-lib. */
const MOCK_START = Date.now()

/** Returns a copy of RUNNING_DETAIL with byte counters that grow over time,
 *  so the Status page's rate deltas (tx/rx B/s) show live-looking traffic. */
function liveRunningDetail() {
  const detail = JSON.parse(JSON.stringify(RUNNING_DETAIL))
  const elapsed = (Date.now() - MOCK_START) / 1000
  const bump = (conn: any, rate: number, base: number) => {
    conn.stats.tx_bytes = String(Math.floor(base + rate * elapsed))
    conn.stats.rx_bytes = String(Math.floor(base / 2 + (rate / 2) * elapsed))
    conn.stats.latency_us = Math.max(1000, Math.floor(12000 + Math.sin(elapsed / 4) * 4000))
  }
  let i = 0
  for (const pair of detail.peer_route_pairs ?? []) {
    const rate = i === 0 ? 2048 : 1024 // different rate per peer
    const base = 1073741824 * (i + 1)
    for (const conn of pair.peer?.conns ?? []) bump(conn, rate, base)
    for (const tun of pair.peer?.tunnel_infos ?? []) {
      for (const conn of tun.conns ?? []) bump(conn, rate, base)
    }
    i += 1
  }
  return detail
}

function strToUuid(uuid: string) {
  const hex = uuid.replace(/-/g, '')
  return {
    part1: Number.parseInt(hex.slice(0, 8), 16) || 0,
    part2: Number.parseInt(hex.slice(8, 16), 16) || 0,
    part3: Number.parseInt(hex.slice(16, 24), 16) || 0,
    part4: Number.parseInt(hex.slice(24, 32), 16) || 0,
  }
}

function seedInstances() {
  instances.set(RUNNING_INSTANCE.instance_id, {
    running: true,
    config: {
      ...JSON.parse(JSON.stringify(NETWORK_CONFIG)),
      instance_id: RUNNING_INSTANCE.instance_id,
      network_name: 'mesh-home',
    },
  })
  instances.set(DISABLED_INSTANCE.instance_id, {
    running: false,
    config: {
      ...JSON.parse(JSON.stringify(NETWORK_CONFIG)),
      instance_id: DISABLED_INSTANCE.instance_id,
      network_name: 'mesh-office',
    },
  })
}
seedInstances()

function toToml(cfg: any): string {
  const lines = ['# EasyTier network configuration (dev mock)']
  if (cfg) {
    if (cfg.network_name) lines.push(`network_name = "${cfg.network_name}"`)
    if (cfg.virtual_ipv4) lines.push(`virtual_ipv4 = "${cfg.virtual_ipv4}"`)
    if (cfg.network_length !== undefined) lines.push(`network_length = ${cfg.network_length}`)
    lines.push(`dhcp = ${cfg.dhcp ?? true}`)
    if (cfg.network_secret) lines.push(`network_secret = "${cfg.network_secret}"`)
    if (Array.isArray(cfg.listener_urls) && cfg.listener_urls.length) lines.push(`listeners = ${JSON.stringify(cfg.listener_urls)}`)
    if (Array.isArray(cfg.peer_urls) && cfg.peer_urls.length) lines.push(`peers = ${JSON.stringify(cfg.peer_urls)}`)
  }
  return lines.join('\n')
}

const invokeHandlers: Record<string, (args: any) => unknown> = {
  // ---- Tauri core / plugin internals ----
  'plugin:os|type': () => 'linux',
  'plugin:event|listen': () => 1,
  'plugin:event|unlisten': () => null,
  'plugin:shell|open': () => null,
  'plugin:process|exit': () => null,
  'plugin:clipboard-manager|write_text': () => null,
  'plugin:window|is_visible': () => true,
  'plugin:window|show': () => null,
  'plugin:window|hide': () => null,
  'plugin:window|set_focus': () => null,
  'plugin:window|set_title': () => null,
  'plugin:window|set_always_on_top': () => null,
  'plugin:menu|new': () => nextResourceId(),
  'plugin:menu|get': () => null,
  'plugin:menu|text': () => '',
  'plugin:menu|get_target_menu_items': () => [],
  'plugin:menu|get_menu_items': () => [],
  'plugin:menu|append': () => null,
  'plugin:menu|prepend': () => null,
  'plugin:menu|popup': () => null,
  'plugin:menu|remove': () => null,
  'plugin:menu|set_as_app_menu': () => null,
  'plugin:menu|set_as_window_menu': () => null,
  'plugin:menu|create_default': () => null,
  'plugin:menu|is_enabled': () => true,
  'plugin:menu|set_enabled': () => null,
  'plugin:menu|set_text': () => null,
  'plugin:menu|set_accelerator': () => null,
  'plugin:menu|set_checked': () => null,
  'plugin:menu|set_as_help_menu_for_nsapp': () => null,
  'plugin:menu|set_as_windows_menu_for_nsapp': () => null,
  'plugin:menu|new_submenu': () => nextResourceId(),
  'plugin:menu|new_predefined': () => nextResourceId(),
  'plugin:menu|new_menu_item': () => nextResourceId(),
  'plugin:menu|new_check_menu_item': () => nextResourceId(),
  'plugin:menu|new_icon_menu_item': () => nextResourceId(),
  'plugin:tray|new': () => nextResourceId(),
  'plugin:tray|get_by_id': () => null,
  'plugin:tray|remove_by_id': () => null,
  'plugin:tray|set_icon': () => null,
  'plugin:tray|set_menu': () => null,
  'plugin:tray|set_tooltip': () => null,
  'plugin:tray|set_title': () => null,
  'plugin:tray|show': () => null,
  'plugin:tray|hide': () => null,
  'plugin:tray|set_show_menu_on_left_click': () => null,
  'plugin:tray|set_temp_dir_path': () => null,
  'plugin:image|new': () => null,
  'plugin:image|new_from_bytes': () => null,
  'plugin:image|new_from_path': () => null,
  'plugin:vpnservice|init': () => null,
  'plugin:vpnservice|sync': () => null,

  // ---- EasyTier custom commands ----
  easytier_version: () => '2.2.0',
  get_service_status: () => 'Running',
  set_service_status: () => null,
  is_client_running: () => true,
  is_web_client_connected: () => false,
  get_log_dir_path: () => '/tmp/easytier/logs',
  set_logging_level: () => null,
  init_rpc_connection: () => null,
  init_web_client: () => null,
  list_network_instance_ids: () => {
    const running: any[] = []
    const disabled: any[] = []
    for (const [id, inst] of instances) {
      ;(inst.running ? running : disabled).push(strToUuid(id))
    }
    return { running_inst_ids: running, disabled_inst_ids: disabled }
  },
  get_network_metas: (args) => ({
    metas: Object.fromEntries((args?.instanceIds ?? []).map((id: string) => {
      const inst = instances.get(id)
      return [id, {
        config_permission: 0xffffffff,
        inst_id: strToUuid(id),
        instance_name: inst?.config?.network_name ?? id,
        network_name: inst?.config?.network_name ?? id,
        source: inst?.running ? 1 : 2,
      }]
    })),
  }),
  get_network_config: (args) => JSON.parse(JSON.stringify(instances.get(args?.instanceId)?.config ?? NETWORK_CONFIG)),
  get_config: (args) => JSON.parse(JSON.stringify(instances.get(args?.instanceId)?.config ?? NETWORK_CONFIG)),
  collect_network_info: () => ({
    // Rust serializes HashMap-in-struct as { map: {...} } (see Api.CollectNetworkInfoResponse)
    info: {
      map: Object.fromEntries(
        [...instances]
          .filter(([, inst]) => inst.running)
          .map(([id]) => [id, liveRunningDetail()]),
      ),
    },
  }),
  get_vpn_portal_info: () => JSON.parse(JSON.stringify(VPN_PORTAL_INFO)),
  patch_vpn_portal_clients: () => null,
  save_network_config: (args) => {
    const cfg = args?.cfg
    if (cfg?.instance_id) {
      const existing = instances.get(cfg.instance_id)
      instances.set(cfg.instance_id, { running: existing?.running ?? false, config: JSON.parse(JSON.stringify(cfg)) })
    }
    return null
  },
  validate_config: () => ({ valid: true }),
  run_network_instance: (args) => {
    const id = args?.cfg?.instance_id
    if (id && instances.has(id)) instances.get(id)!.running = true
    return null
  },
  remove_network_instance: (args) => {
    instances.delete(args?.instanceId)
    return null
  },
  update_network_config_state: (args) => {
    const inst = instances.get(args?.instanceId)
    if (inst) inst.running = !args?.disabled
    return null
  },
  load_configs: () => null,
  parse_network_config: (args) => toToml(args?.cfg ?? {}),
  generate_network_config: () => JSON.parse(JSON.stringify(NETWORK_CONFIG)),
  init_service: () => null,
  set_tun_fd: () => null,
}

interface TauriInternals {
  invoke: (cmd: string, args?: any, options?: any) => Promise<unknown>
  transformCallback: (callback: (response: any) => void, once?: boolean) => number
  unregisterCallback: (id: number) => void
  convertFileSrc: (filePath: string, protocol?: string) => string
  metadata: { currentWindow: { label: string } }
  event: {
    listen: (event: string, handler: (event: any) => void) => Promise<number>
    unlisten: (event: string, id: number) => Promise<void>
  }
}

let callbackCounter = 0
let resourceCounter = 0

/** All menu/tray resources are identified by `[rid, id]` tuples. */
function nextResourceId(): [number, string] {
  resourceCounter += 1
  return [resourceCounter, `mock-resource-${resourceCounter}`]
}

export function installTauriMock(): void {
  if (window.__TAURI_INTERNALS__) {
    return
  }

  // @tauri-apps/plugin-os reads OS info synchronously from this global —
  // `type()` (used by the GUI's mounted hook) reads `.os_type` directly.
  ;(window as any).__TAURI_OS_PLUGIN_INTERNALS__ = {
    eol: '\n',
    family: 'unix',
    platform: 'linux',
    os_type: 'linux',
    version: '6.8.0',
    arch: 'x86_64',
    locale: 'en-US',
  }

  const internals: TauriInternals = {
    invoke: async (cmd: string, args?: any, _options?: any) => {
      // Some commands are invoked with a camelCase alias handled by the backend
      const handler = invokeHandlers[cmd]
      if (handler) {
        return handler(args)
      }
      // Normalize a few commonly used aliases for robustness
      const normalized = cmd.replace('plugin:os|type', 'plugin:os|type')
      const handler2 = invokeHandlers[normalized]
      if (handler2) {
        return handler2(args)
      }
      console.warn(`[tauri-mock] unhandled invoke: ${cmd}`, args)
      return null
    },
    transformCallback: (_callback: (response: any) => void, _once?: boolean) => {
      return ++callbackCounter
    },
    unregisterCallback: (_id: number) => {},
    convertFileSrc: (filePath: string, _protocol?: string) => filePath,
    metadata: {
      currentWindow: { label: 'main' },
    },
    event: {
      listen: async () => 1,
      unlisten: async () => {},
    },
  }

  ;(window as any).__TAURI_INTERNALS__ = internals
  console.info('[tauri-mock] installed dev mock for browser preview')
}
