<script setup lang="ts">
import { useTimeAgo } from '@vueuse/core'
import { NetworkInstance, VpnPortalClientState, type TunnelInfo, type NodeInfo, type PeerRoutePair, type VpnPortalClientInfo, type VpnPortalInfo } from '../types/network'
import type { RemoteClient } from '../modules/api'
import { useI18n } from 'vue-i18n';
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useDisplay } from 'vuetify';
import { ipv4InetToString, ipv4ToString, ipv6ToString } from '../modules/utils';
import { latencyMs, lossRate, numericValue, peerConns } from '../modules/statusDisplay';
import NetworkChart from './NetworkChart.vue';
import HumanEvent from './HumanEvent.vue';

const props = withDefaults(defineProps<{
  curNetworkInst: NetworkInstance | null,
  api: RemoteClient,
  activeTab?: string,
  /** 已弃用:宿主从未传入,组件不再绑定任何 class(旧 .is-refreshing 会拦截点击)。保留仅为兼容。 */
  refreshing?: boolean,
  /** 宿主未传入 curNetworkInst(首刷未回)时显示骨架。 */
  loading?: boolean,
  /** 移动端 Hero 是唯一控制入口:为 true 时 orb 只读,不渲染可交互按钮。 */
  hidePowerToggle?: boolean,
  /** 权威运行态(VPN 感知,来自 Hero)。缺省(undefined)时回退到 RPC running,桌面行为不变。 */
  networkRunning?: boolean,
}>(), {
  activeTab: 'all',
  refreshing: false,
  loading: false,
  // hidePowerToggle 刻意不给 default:缺省(undefined)时组件只呈现"纯状态",
  // 只有宿主显式传 false 时才保留 v1 的电源球交互(见 showPowerToggle)。
  // 必须显式写 undefined:Boolean prop 若没有 default,Vue 会在缺省时把它转成
  // false,从而吞掉 RPC running 状态;显式 undefined 才能让 ?? 回退生效。
  networkRunning: undefined,
})

defineEmits(['switch-tab', 'start-network', 'stop-network', 'toggle-network'])

const { t } = useI18n()
const { smAndDown } = useDisplay()

// 触觉反馈:组件内局部实现,不动共享 utils(避免与其他 agent 冲突)
function vibrate(ms = 8) {
  try {
    navigator.vibrate?.(ms)
  } catch {
    /* ignore */
  }
}

// 骨架屏:宿主首刷未回(既无实例也无错误)时给出占位而不是空白闪现
const showSkeleton = computed(() => props.loading || !props.curNetworkInst)

// 列表进出场的稳定 key:优先 peer_id,退化到 IP/主机名
function peerKey(info: any, i: number): string {
  const id = info?.route?.peer_id ?? info?.peer?.peer_id
  if (id !== undefined && id !== null && id !== '') {
    return `pid-${id}`
  }
  const ip = ipFormat(info)
  if (ip) {
    return `ip-${ip}`
  }
  return `idx-${info?.route?.hostname ?? 'na'}-${i}`
}

const peerRouteInfos = computed<any[]>(() => {
  if (props.curNetworkInst) {
    const my_node_info = props.curNetworkInst.detail?.my_node_info
    return [{
      route: {
        ipv4_addr: my_node_info?.virtual_ipv4,
        hostname: my_node_info?.hostname,
        version: my_node_info?.version,
        stun_info: my_node_info?.stun_info
      },
    }, ...(props.curNetworkInst.detail?.peer_route_pairs || [])]
  }

  return []
})

const peerFilter = ref<'all' | 'direct' | 'relay' | 'server'>('all')
const peerSearch = ref('')
const peersFilteredActive = computed(() => peerFilter.value !== 'all' || peerSearch.value.trim() !== '')

function resetPeerFilters() {
  peerFilter.value = 'all'
  peerSearch.value = ''
}

// ---------------------------------------------------------------------------
// PeerRow 契约:状态点 / 虚拟 IP / 路径 / 延迟(右对齐等宽),行高 --et-row-h。
//
// 离线节点不隐藏:v1 里节点一离开就从列表消失,用户会以为"设备没添加"。后端
// 只在 route 表里留痕、不再返回 peer 记录(甚至整条不再返回),所以这里在本组件
// 记住最近见过的节点,离线后继续以 neutral 呈现,并给出"离线 Nh"——时长是本
// 组件观测到的,不是后端字段。保留窗口 24h,切换网络时清空。
// ---------------------------------------------------------------------------
const OFFLINE_RETENTION_MS = 24 * 60 * 60 * 1000

interface PeerPresence {
  info: any
  /** 最后一次在后端列表里看到它的时间 */
  lastSeen: number
  /** 首次观测到离线的时刻;在线时为 undefined */
  offlineSince?: number
}

interface PeerRow {
  key: string
  info: any
  offline: boolean
  offlineSince?: number
}

const peerPresence = ref<Record<string, PeerPresence>>({})
// 让"离线 Nh"随时间前进:网络不动时 peerRouteInfos 不更新,仍需刷新时长
const presenceNow = ref(Date.now())

/** 本机路由没有 cost;它永远在线,不能当离线处理。 */
function isLocalRoute(info: any): boolean {
  return !info?.route?.cost
}

/** 路由还在但对端记录消失 = 连接已丢失(后端不再返回该 peer)。 */
function isPeerOffline(info: any): boolean {
  if (!info?.route || isLocalRoute(info))
    return false
  return !info?.peer
}

function refreshPeerPresence() {
  const now = Date.now()
  presenceNow.value = now
  const next: Record<string, PeerPresence> = {}
  for (const [key, entry] of Object.entries(peerPresence.value)) {
    if (now - (entry.offlineSince ?? entry.lastSeen) <= OFFLINE_RETENTION_MS)
      next[key] = entry
  }
  peerRouteInfos.value.forEach((info, i) => {
    const key = peerKey(info, i)
    const prev = next[key]
    if (isPeerOffline(info)) {
      next[key] = {
        info,
        lastSeen: prev?.lastSeen ?? now,
        offlineSince: prev?.offlineSince ?? now,
      }
    } else {
      next[key] = { info, lastSeen: now }
    }
  })
  peerPresence.value = next
}

watch(peerRouteInfos, refreshPeerPresence, { immediate: true })
watch(() => props.curNetworkInst?.instance_id, () => {
  // 换网络时旧网络的节点不能以"离线"身份跟过来
  peerPresence.value = {}
  refreshPeerPresence()
})

const peerRowsAll = computed<PeerRow[]>(() => {
  const rows: PeerRow[] = []
  const liveKeys = new Set<string>()
  peerRouteInfos.value.forEach((info, i) => {
    const key = peerKey(info, i)
    liveKeys.add(key)
    rows.push({
      key,
      info,
      offline: isPeerOffline(info),
      offlineSince: peerPresence.value[key]?.offlineSince,
    })
  })
  for (const [key, entry] of Object.entries(peerPresence.value)) {
    if (liveKeys.has(key))
      continue
    rows.push({
      key,
      info: entry.info,
      offline: true,
      offlineSince: entry.offlineSince ?? entry.lastSeen,
    })
  }
  return rows
})

function matchesPeerFilters(row: PeerRow): boolean {
  const route = row.info?.route
  if (peerFilter.value === 'direct' && route?.cost && route.cost !== 1)
    return false
  if (peerFilter.value === 'relay' && !(route?.cost && route.cost > 1))
    return false
  if (peerFilter.value === 'server' && !isPublicServerRoute(row.info))
    return false

  const q = peerSearch.value.trim().toLowerCase()
  if (!q)
    return true
  const hostname = (route?.hostname || '').toLowerCase()
  const ip = ipFormat(row.info).toLowerCase()
  return hostname.includes(q) || ip.includes(q)
}

const filteredPeerRows = computed(() => peerRowsAll.value.filter(matchesPeerFilters))

function offlineFor(since: number | undefined): string {
  if (!since)
    return ''
  const elapsed = Math.max(0, presenceNow.value - since)
  const hours = Math.floor(elapsed / 3600000)
  if (hours >= 1)
    return `${hours}h`
  return `${Math.max(1, Math.floor(elapsed / 60000))}m`
}

function peerPathLabel(row: PeerRow): string {
  const info = row.info
  if (row.offline) {
    const elapsed = offlineFor(row.offlineSince)
    return elapsed ? `${t('web.device.offline')} ${elapsed}` : t('web.device.offline')
  }
  const route = info?.route
  if (!route)
    return t('status.lost', 'Lost')
  if (isLocalRoute(info))
    return t('status.local')
  if (route.cost === 1)
    return t('status.filter_direct')
  const via = relayVia(info)
  return via ? `${t('status.relay')} via ${via}` : t('status.relay')
}

/** 中继跳点的主机名(route.next_hop_peer_id 指向的 peer)。 */
function relayVia(info: any): string {
  const hopId = info?.route?.next_hop_peer_id
  if (!hopId)
    return ''
  const hop = peerRouteInfos.value.find(p => (p.route?.peer_id ?? p.peer?.peer_id) === hopId)
  return hop?.route?.hostname || `#${hopId}`
}

function peerRttText(row: PeerRow): string {
  if (row.offline)
    return '—'
  return latencyMs(row.info) || '—'
}

function peerRttClass(row: PeerRow): string {
  if (row.offline)
    return 'is-idle'
  const latency = latencyMs(row.info)
  if (!latency)
    return 'is-idle'
  const ms = Number.parseInt(latency)
  if (Number.isNaN(ms))
    return 'is-idle'
  if (ms >= 110)
    return 'is-warn'
  if (ms >= 45)
    return 'is-mid'
  return 'is-good'
}

function peerDotClass(row: PeerRow): string {
  if (row.offline)
    return 'is-idle'
  const loss = lossRate(row.info)
  if (loss && Number.parseFloat(loss) > 0)
    return 'is-warn'
  const rtt = peerRttClass(row)
  if (rtt === 'is-idle')
    return isLocalRoute(row.info) ? 'is-good' : 'is-idle'
  return rtt
}

function routeCost(info: any) {
  if (!info?.route) {
    return '?'
  }
  const cost = info.route.cost
  return cost ? cost === 1 ? 'p2p' : `relay(${cost})` : t('status.local')
}

function peerDeviceIcon(info: any): string {
  if (!info?.route?.cost) return 'mdi-laptop'
  const hostname = (info.route?.hostname || '').toLowerCase()
  if (hostname.includes('phone') || hostname.includes('iphone') || hostname.includes('android')) return 'mdi-cellphone'
  if (hostname.includes('mac') || hostname.includes('apple') || hostname.includes('darwin')) return 'mdi-apple'
  if (hostname.includes('win') || hostname.includes('pc')) return 'mdi-microsoft-windows'
  if (hostname.includes('linux') || hostname.includes('ubuntu') || hostname.includes('debian')) return 'mdi-linux'
  if (hostname.includes('nas') || hostname.includes('synology') || hostname.includes('qnap')) return 'mdi-nas'
  if (hostname.includes('server') || hostname.includes('node') || hostname.includes('vps')) return 'mdi-server'
  if (hostname.includes('gw') || hostname.includes('router') || hostname.includes('openwrt')) return 'mdi-router-wireless'
  return info.route.cost === 1 ? 'mdi-lightning-bolt' : 'mdi-transit-connection-variant'
}

function resolveObjPath(path: string, obj: any = globalThis, separator = '.') {
  const properties = path.split(separator)
  return properties.reduce((prev, curr) => prev?.[curr], obj)
}

function statsCommon(info: any, field: string): number | undefined {
  if (!info?.peer)
    return undefined

  let sum = 0
  let hasValue = false
  for (const conn of peerConns(info)) {
    const value = numericValue(resolveObjPath(field, conn))
    if (value === undefined)
      continue

    sum += value
    hasValue = true
  }
  return hasValue ? sum : undefined
}

function humanFileSize(bytes: number, si = false, dp = 1) {
  const thresh = si ? 1000 : 1024

  if (Math.abs(bytes) < thresh)
    return `${bytes} B`

  const units = si
    ? ['kB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB']
    : ['KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB', 'ZiB', 'YiB']
  let u = -1
  const r = 10 ** dp

  do {
    bytes /= thresh
    ++u
  } while (Math.round(Math.abs(bytes) * r) / r >= thresh && u < units.length - 1)

  return `${bytes.toFixed(dp)} ${units[u]}`
}

function txBytes(info: PeerRoutePair) {
  const tx = statsCommon(info, 'stats.tx_bytes')
  return tx ? humanFileSize(tx) : '0 B'
}

function rxBytes(info: PeerRoutePair) {
  const rx = statsCommon(info, 'stats.rx_bytes')
  return rx ? humanFileSize(rx) : '0 B'
}

function version(info: PeerRoutePair) {
  return info?.route?.version === '' ? 'unknown' : (info?.route?.version ?? '—')
}

function ipFormat(info: PeerRoutePair) {
  if (!info?.route)
    return ''
  const ip = info.route.ipv4_addr
  if (typeof ip === 'string')
    return ip
  return ip ? ipv4InetToString(ip) : ''
}

function oneTunnelProto(tunnel?: TunnelInfo): string {
  if (!tunnel)
    return ''

  const local_addr = tunnel.local_addr
  let isIPv6 = false;
  if (local_addr?.url) {
    try {
      const urlObj = new URL(local_addr.url, 'http://dummy');
      isIPv6 = /^\[.*:.*\]$/.test(urlObj.hostname);
    } catch (e) {
      isIPv6 = local_addr.url.indexOf('[') >= 0;
    }
  }
  if (isIPv6)
    return `${tunnel.tunnel_type}6`
  else
    return tunnel.tunnel_type
}

function tunnelProto(info: PeerRoutePair) {
  return [...new Set(peerConns(info).map(c => oneTunnelProto(c.tunnel)))].join(',')
}

const myNodeInfo = computed(() => {
  if (!props.curNetworkInst)
    return {} as NodeInfo

  return props.curNetworkInst.detail?.my_node_info
})

interface Chip {
  label: string
  icon: string
}

enum NatType {
  Unknown = 0,
  OpenInternet = 1,
  NoPAT = 2,
  FullCone = 3,
  Restricted = 4,
  PortRestricted = 5,
  Symmetric = 6,
  SymUdpFirewall = 7,
  SymmetricEasyInc = 8,
  SymmetricEasyDec = 9,
}

const udpNatTypeKeyMap: Record<number, string> = {
  [NatType.Unknown]: 'nat.unknown',
  [NatType.OpenInternet]: 'nat.open_internet',
  [NatType.NoPAT]: 'nat.no_pat',
  [NatType.FullCone]: 'nat.full_cone',
  [NatType.Restricted]: 'nat.restricted',
  [NatType.PortRestricted]: 'nat.port_restricted',
  [NatType.Symmetric]: 'nat.symmetric',
  [NatType.SymUdpFirewall]: 'nat.sym_udp_firewall',
  [NatType.SymmetricEasyInc]: 'nat.symmetric_easy_inc',
  [NatType.SymmetricEasyDec]: 'nat.symmetric_easy_dec',
}

function natTypeLabel(nat: number | undefined): string {
  if (nat === undefined)
    return ''
  return t(udpNatTypeKeyMap[nat] ?? 'nat.unknown')
}

function dash(value: string | undefined | null): string {
  return value ? value : '—'
}

const myNodeInfoChips = computed(() => {
  if (!props.curNetworkInst)
    return []

  const chips: Array<Chip> = []
  const my_node_info = myNodeInfo.value
  if (!my_node_info)
    return chips

  chips.push({
    label: `${t('status.peer_id')}: ${my_node_info.peer_id}`,
    icon: 'mdi-identifier',
  } as Chip)

  const dev_name = props.curNetworkInst.detail?.dev_name
  if (dev_name) {
    chips.push({
      label: `TUN: ${dev_name}`,
      icon: 'mdi-network-interface',
    } as Chip)
  }

  chips.push({
    label: `IPv4: ${ipv4InetToString(my_node_info.virtual_ipv4)}`,
    icon: 'mdi-ip',
  } as Chip)

  const local_ipv4s = my_node_info.ips?.interface_ipv4s
  for (const [idx, ip] of local_ipv4s?.entries() ?? []) {
    chips.push({
      label: `IPv4 (${idx}): ${ipv4ToString(ip)}`,
      icon: 'mdi-lan',
    } as Chip)
  }

  const local_ipv6s = my_node_info.ips?.interface_ipv6s
  for (const [idx, ip] of local_ipv6s?.entries() ?? []) {
    chips.push({
      label: `IPv6 (${idx}): ${ipv6ToString(ip)}`,
      icon: 'mdi-lan',
    } as Chip)
  }

  const public_ip = my_node_info.ips?.public_ipv4
  if (public_ip) {
    chips.push({
      label: `${t('status.public_ipv4')}: ${ipv4ToString(public_ip)}`,
      icon: 'mdi-earth',
    } as Chip)
  }

  const public_ipv6 = my_node_info.ips?.public_ipv6
  if (public_ipv6) {
    chips.push({
      label: `${t('status.public_ipv6')}: ${ipv6ToString(public_ipv6)}`,
      icon: 'mdi-earth',
    } as Chip)
  }

  const listeners = my_node_info.listeners
  for (const [idx, listener] of listeners?.entries() ?? []) {
    chips.push({
      label: `${t('status.listener')} ${idx}: ${listener.url}`,
      icon: 'mdi-access-point',
    } as Chip)
  }

  const udpNatType: NatType = my_node_info.stun_info?.udp_nat_type
  if (udpNatType !== undefined) {
    chips.push({
      label: `NAT: ${natTypeLabel(udpNatType)}`,
      icon: 'mdi-shield-check',
    } as Chip)
  }

  return chips
})

function globalSumCommon(field: string) {
  let sum = 0
  if (!peerRouteInfos.value)
    return sum

  for (const info of peerRouteInfos.value) {
    const tx = statsCommon(info, field)
    if (tx)
      sum += tx
  }
  return sum
}

function txGlobalSum() {
  return globalSumCommon('stats.tx_bytes')
}

function rxGlobalSum() {
  return globalSumCommon('stats.rx_bytes')
}

const totalTxFormatted = computed(() => humanFileSize(txGlobalSum()))
const totalRxFormatted = computed(() => humanFileSize(rxGlobalSum()))

function natType(info: PeerRoutePair): string {
  return natTypeLabel(info?.route?.stun_info?.udp_nat_type)
}

function isPublicServerRoute(info: PeerRoutePair): boolean {
  return info.route?.feature_flag?.is_public_server ?? false
}

function shouldAvoidRelayData(info: PeerRoutePair): boolean {
  return info.route?.feature_flag?.avoid_relay_data ?? false
}

let rateIntervalId = 0
const rateInterval = 2000
let prevTxSum = 0
let prevRxSum = 0
const txRate = ref('0 B')
const rxRate = ref('0 B')

const showNodeDetails = ref(false)
const selectedPeer = ref<any | null>(null)
const selectedPeerOffline = ref(false)
const peerSheetOpen = ref(false)

function inspectPeer(row: PeerRow) {
  selectedPeer.value = row?.info ?? row
  selectedPeerOffline.value = !!row?.offline
  peerSheetOpen.value = true
}

const ipCopied = ref(false)
const copyToast = ref(false)
async function copyText(text: string) {
  if (!text)
    return
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
    } else {
      const textarea = document.createElement('textarea')
      textarea.value = text
      textarea.style.position = 'fixed'
      textarea.style.opacity = '0'
      document.body.appendChild(textarea)
      textarea.select()
      document.execCommand('copy')
      textarea.remove()
    }
    ipCopied.value = true
    copyToast.value = true
    vibrate(8)
    setTimeout(() => { ipCopied.value = false }, 2000)
  } catch (e) {
    console.error('Failed to copy', e)
  }
}

onMounted(() => {
  rateIntervalId = window.setInterval(() => {
    // 离线时长("离线 Nh")要跟着时钟走
    presenceNow.value = Date.now()

    const curTxSum = txGlobalSum()
    txRate.value = humanFileSize((curTxSum - prevTxSum) / (rateInterval / 1000))
    prevTxSum = curTxSum

    const curRxSum = rxGlobalSum()
    rxRate.value = humanFileSize((curRxSum - prevRxSum) / (rateInterval / 1000))
    prevRxSum = curRxSum
  }, rateInterval)
})

onUnmounted(() => {
  clearInterval(rateIntervalId)
})

const dialogVisible = ref(false)
const dialogContent = ref<any>('')
const dialogHeader = ref('event_log')
const vpnPortalInfo = ref<VpnPortalInfo>()
const vpnPortalClients = computed(() => vpnPortalInfo.value?.clients ?? [])
const vpnPortalLoading = ref(false)
const vpnPortalError = ref('')
const copiedVpnPortalClient = ref('')

async function showVpnPortalConfig() {
  const instanceId = props.curNetworkInst?.instance_id
  if (!instanceId)
    return

  dialogHeader.value = 'vpn_portal_config'
  dialogVisible.value = true
  vpnPortalLoading.value = true
  vpnPortalError.value = ''

  try {
    vpnPortalInfo.value = await props.api.get_vpn_portal_info(instanceId)
  }
  catch (error: any) {
    console.error('Failed to load VPN Portal info', error)
    vpnPortalError.value = error?.message || t('vpn_portal_load_failed')
  }
  finally {
    vpnPortalLoading.value = false
  }
}

function vpnPortalStateKey(state: VpnPortalClientState | string): string {
  if (typeof state === 'number') {
    switch (state) {
      case VpnPortalClientState.ONLINE:
        return 'vpn_portal_state_online'
      case VpnPortalClientState.CONNECTING:
        return 'vpn_portal_state_connecting'
      case VpnPortalClientState.OFFLINE:
        return 'vpn_portal_state_offline'
      case VpnPortalClientState.ERROR:
        return 'vpn_portal_state_error'
      default:
        return 'vpn_portal_state_unspecified'
    }
  }

  const normalized = typeof state === 'string'
    ? state.toLowerCase().replace('vpn_portal_client_state_', '')
    : VpnPortalClientState[state]?.toLowerCase()
  return `vpn_portal_state_${normalized ?? 'unspecified'}`
}

function vpnPortalStateColor(state: VpnPortalClientState | string): string {
  const key = vpnPortalStateKey(state)
  if (key.endsWith('online')) return 'success'
  if (key.endsWith('connecting')) return 'warning'
  if (key.endsWith('error')) return 'error'
  return 'grey'
}

async function copyVpnPortalClientConfig(client: VpnPortalClientInfo) {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(client.client_config)
    } else {
      const textarea = document.createElement('textarea')
      textarea.value = client.client_config
      textarea.style.position = 'fixed'
      textarea.style.opacity = '0'
      document.body.appendChild(textarea)
      textarea.select()
      document.execCommand('copy')
      textarea.remove()
    }
    copiedVpnPortalClient.value = client.name
    vibrate(8)
  } catch (error) {
    console.error('Failed to copy VPN Portal client config', error)
  }
}

/** 事件日志的稳定 key:时间 + 事件内容,同一个事件重渲染不会错位。 */
function eventTimelineKey(item: any): string {
  try {
    return `${item?.time ?? 'na'}-${JSON.stringify(item?.event ?? {})}`
  } catch {
    return `${item?.time ?? 'na'}`
  }
}

function showEventLogs() {
  const detail = props.curNetworkInst?.detail
  if (!detail)
    return

  dialogContent.value = detail.events?.map((event: string) => JSON.parse(event)) ?? []
  dialogHeader.value = 'event_log'
  dialogVisible.value = true
}

const myVirtualIp = computed(() => {
  const my_node = props.curNetworkInst?.detail?.my_node_info
  if (!my_node?.virtual_ipv4) return ''
  return ipv4InetToString(my_node.virtual_ipv4)
})

const myNatTypeStr = computed(() => {
  const nat = props.curNetworkInst?.detail?.my_node_info?.stun_info?.udp_nat_type
  return nat !== undefined ? natTypeLabel(nat) : t('nat.unknown')
})

const otherPeerCount = computed(() => {
  return props.curNetworkInst?.detail?.peer_route_pairs?.length ?? 0
})

const showHome = computed(() => props.activeTab === 'home' || props.activeTab === 'all')
const showDevices = computed(() => props.activeTab === 'devices')

const myDevName = computed(() => {
  return props.curNetworkInst?.detail?.dev_name || 'tun'
})

const isRunning = computed(() => {
  return props.curNetworkInst?.running ?? false
})

// 显示态:移动端 Hero 传入的 VPN 感知状态优先;未传入时保持原有 RPC running 语义。
// 这样高级控制台不会和 Hero 显示互相矛盾的状态。
const displayRunning = computed(() => props.networkRunning ?? isRunning.value)

const myHostname = computed(() => {
  return props.curNetworkInst?.detail?.my_node_info?.hostname || 'easytier-node'
})

// ---------------------------------------------------------------------------
// 状态信号(三重编码:色 + 形 + 文)。五态形状映射见 index.html 的 .signal:
//   已连接=圆·accent / 连接中=方·info·呼吸 / 降级=三角·warn / 已断开=横条·danger
//   / 未启动=空环·neutral。文字始终存在,灰度下也能区分。
// ---------------------------------------------------------------------------
type SignalState = 'up' | 'sync' | 'warn' | 'down' | 'idle'

// 连接开关只在宿主显式传 hidePowerToggle=false 时保留(v1 桌面控制台兼容);
// 缺省(undefined)与 true 都是纯状态,连接/断开由宿主自己的主操作承担。
const showPowerToggle = computed(() => props.hidePowerToggle === false)

const degradedPeerCount = computed(() => {
  const list = props.curNetworkInst?.detail?.peer_route_pairs ?? []
  return list.filter((info) => {
    const latency = latencyMs(info)
    if (latency && Number.parseInt(latency) >= 110)
      return true
    const loss = lossRate(info)
    return !!loss && Number.parseFloat(loss) > 0
  }).length
})

const signalState = computed<SignalState>(() => {
  if (props.curNetworkInst?.error_msg)
    return 'down'
  // 权威运行态(VPN 感知)与 RPC 运行态不一致 → 降级:进程在跑但隧道没通,或反之
  if (props.networkRunning !== undefined && props.networkRunning !== isRunning.value)
    return 'warn'
  if (!displayRunning.value)
    return 'idle'
  if (otherPeerCount.value === 0)
    return 'sync'
  if (degradedPeerCount.value > 0)
    return 'warn'
  return 'up'
})

const signalClass = computed(() => `is-${signalState.value}`)

const signalText = computed(() => {
  switch (signalState.value) {
    case 'up':
      return t('status.connected')
    case 'sync':
      return t('vpn_portal_state_connecting')
    case 'warn':
      return t('status.degraded', 'Degraded')
    case 'down':
      return t('status.disconnected')
    default:
      return t('network_stopped')
  }
})

const orbIcon = computed(() => {
  switch (signalState.value) {
    case 'up':
      return 'mdi-shield-check'
    case 'sync':
      return 'mdi-lan-connect'
    case 'warn':
      return 'mdi-shield-alert-outline'
    case 'down':
      return 'mdi-shield-off'
    default:
      return 'mdi-power'
  }
})

const heroHint = computed(() => {
  if (props.hidePowerToggle === true)
    return t('status.controls_on_overview')
  if (props.hidePowerToggle === undefined)
    return t('status.status_only_hint', 'Live status only')
  return displayRunning.value ? t('status.tap_to_disconnect') : t('status.tap_to_connect')
})

</script>

<template>
  <div class="frontend-lib status-root">
    <v-dialog v-model="dialogVisible" max-width="500px" :fullscreen="smAndDown" transition="dialog-bottom-transition">
      <v-card :title="t(dialogHeader)" rounded="xl" class="et-dialog-sheet">
        <v-card-text class="pa-4">
          <div v-if="dialogHeader === 'vpn_portal_config'" class="vpn-dialog-body">
            <div v-if="vpnPortalLoading" role="progressbar" aria-hidden="true" class="et-skeleton-stack py-2">
              <v-skeleton-loader class="et-skeleton" type="list-item-two-line" boilerplate />
              <v-skeleton-loader class="et-skeleton" type="list-item-two-line@2" boilerplate />
            </div>
            <div v-else-if="vpnPortalError" class="pa-4 text-error">
              {{ vpnPortalError }}
            </div>
            <div v-else-if="!vpnPortalInfo || ((!vpnPortalInfo.vpn_type || vpnPortalInfo.vpn_type === 'null') && vpnPortalClients.length === 0)"
              class="et-empty">
              <div class="et-empty__icon"><v-icon size="26" color="primary">mdi-vpn</v-icon></div>
              <div class="et-empty__title">{{ t('vpn_portal_not_configured') }}</div>
              <div class="et-empty__hint">{{ t('status.vpn_portal_empty_hint', 'Enable VPN Portal in the config tab to share WireGuard access') }}</div>
            </div>
            <div v-else class="d-flex flex-column ga-3">
              <div class="et-group pa-3 mb-2">
                <div class="text-caption text-medium-emphasis mb-1">{{ t('status.vpn_portal') }}</div>
                <div class="d-flex justify-space-between py-1 border-b text-body-2">
                  <span>{{ t('vpn_portal_type') }}</span>
                  <span class="font-weight-medium">{{ vpnPortalInfo.vpn_type }}</span>
                </div>
                <div class="d-flex justify-space-between py-1 text-body-2">
                  <span>{{ t('vpn_portal_listener') }}</span>
                  <span class="text-mono font-weight-medium et-selectable">{{ vpnPortalInfo.listener }}</span>
                </div>
              </div>

              <TransitionGroup tag="div" name="et-list-fade" class="d-flex flex-column ga-3 et-list-wrap">
                <div v-for="client in vpnPortalClients" :key="client.name" class="et-group pa-3">
                <div class="d-flex align-center justify-space-between mb-2">
                  <div class="font-weight-bold text-body-1">{{ client.name }} · {{ client.virtual_ip }}</div>
                  <v-chip :color="vpnPortalStateColor(client.state)" size="x-small" variant="tonal" class="font-weight-medium">
                    {{ t(vpnPortalStateKey(client.state)) }}
                  </v-chip>
                </div>
                <div class="text-caption text-medium-emphasis mb-2">
                  <span v-if="client.groups.length">{{ t('vpn_portal_client_groups') }}: {{ client.groups.join(', ') }}</span>
                  <span v-if="client.endpoint" class="ms-2">{{ t('vpn_portal_endpoint') }}: {{ client.endpoint }}</span>
                </div>
                <div class="d-flex align-center justify-space-between pt-1">
                  <span class="text-caption font-weight-medium">Config</span>
                  <v-btn size="small" variant="tonal" color="primary" rounded="pill" :prepend-icon="'mdi-content-copy'"
                    @click="copyVpnPortalClientConfig(client)">
                    {{ copiedVpnPortalClient === client.name ? t('config_copied') : t('vpn_portal_copy_client_config') }}
                  </v-btn>
                </div>
                  <pre class="vpn-client-config mt-2 et-selectable">{{ client.client_config }}</pre>
                </div>
              </TransitionGroup>
            </div>
          </div>

          <div v-else class="event-log-body">
            <v-timeline v-if="dialogContent.length" side="end" density="compact" class="pa-2">
              <v-timeline-item
                v-for="item in dialogContent"
                :key="eventTimelineKey(item)"
                dot-color="primary"
                size="small"
              >
                <small class="text-caption text-medium-emphasis d-block mb-1">{{ useTimeAgo(Date.parse(item.time)) }}</small>
                <HumanEvent :event="item.event" />
              </v-timeline-item>
            </v-timeline>
            <div v-else class="et-empty">
              <div class="et-empty__icon"><v-icon size="26" color="primary">mdi-history</v-icon></div>
              <div class="et-empty__title">{{ t('no_events') }}</div>
              <div class="et-empty__hint">{{ t('status.event_log_empty_hint', 'Events will appear once the instance starts reporting') }}</div>
            </div>
          </div>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="dialogVisible = false">{{ t('close') }}</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-card v-if="curNetworkInst?.error_msg" class="mb-4" color="error" variant="tonal" rounded="xl">
      <v-card-title class="text-subtitle-1 font-weight-bold">{{ t('error_msg') }}</v-card-title>
      <v-card-text class="text-error">{{ curNetworkInst.error_msg }}</v-card-text>
    </v-card>

    <!-- 首刷未回:hero+分组形状的骨架,避免空白闪现 -->
    <div v-else-if="showSkeleton" role="progressbar" aria-hidden="true" class="et-skeleton-stack pt-4">
      <v-skeleton-loader class="et-skeleton" type="article" boilerplate />
      <v-skeleton-loader class="et-skeleton" type="list-item-avatar-two-line@3" boilerplate />
    </div>

    <template v-else>
      <div v-if="showHome" class="home-tab-content">
        <div class="et-hero">
          <div class="et-hero-mesh" aria-hidden="true" />
          <!-- 迁移期可选:只有宿主显式传 hide-power-toggle=false 才保留 v1 的
               可交互电源球(桌面控制台尚未把主操作移出状态卡)。emit / aria 与
               之前完全一致。 -->
          <button
            v-if="showPowerToggle"
            type="button"
            class="et-power-orb"
            :class="signalClass"
            :aria-pressed="displayRunning"
            :aria-label="displayRunning ? t('status.disconnect') : t('status.connect')"
            @click="vibrate(12); $emit('toggle-network')"
          >
            <span class="et-orb-ring r1" />
            <span class="et-orb-ring r2" />
            <div class="et-orb-center">
              <v-icon size="40">{{ orbIcon }}</v-icon>
            </div>
          </button>

          <!-- v2 默认:只读状态球。非 button、不可聚焦、无 click/aria-pressed,
               状态语义完全由下方 role="status" 的信号药丸承载。 -->
          <div
            v-else
            class="et-power-orb is-readonly"
            :class="signalClass"
            aria-hidden="true"
          >
            <span class="et-orb-ring r1" />
            <span class="et-orb-ring r2" />
            <div class="et-orb-center">
              <v-icon size="40">{{ orbIcon }}</v-icon>
            </div>
          </div>

          <!-- 三重编码:形状(圆/方/三角/横条/环) + 颜色 + 文字 -->
          <span class="et-signal mt-3" :class="signalClass" role="status">
            <span class="et-signal__glyph" aria-hidden="true" />
            <span class="et-signal__text">{{ signalText }}</span>
          </span>
          <div class="et-hero-meta mono">
            {{ myHostname }} · <span :key="otherPeerCount" class="et-num et-tick font-weight-bold">{{ otherPeerCount }}</span> {{ t('status.devices_unit') }}
          </div>
          <div class="et-hero-hint">{{ heroHint }}</div>
        </div>

        <div class="et-section">
          <div class="et-section-label">{{ t('status.network_identity') }}</div>
          <div class="et-id-card et-group pa-3 mb-3">
            <div class="d-flex align-center justify-space-between">
              <div class="d-flex align-center ga-3 min-w-0">
                <div class="et-squircle" style="background: var(--et-accent-quiet);">
                  <v-icon size="20" color="primary">mdi-ip-network</v-icon>
                </div>
                <div class="min-w-0">
                  <div class="text-caption text-medium-emphasis">{{ t('status.virtual_ip') }}</div>
                  <div class="text-h6 font-weight-bold text-mono et-selectable" style="color: var(--et-accent); line-height: 1.2;">
                    {{ myVirtualIp || '—.—.—.—' }}
                  </div>
                </div>
              </div>
              <v-btn
                v-if="myVirtualIp"
                :icon="ipCopied ? 'mdi-check' : 'mdi-content-copy'"
                :color="ipCopied ? 'success' : 'primary'"
                variant="tonal"
                size="small"
                class="rounded-pill"
                :aria-label="t('status.copy_ip')"
                @click="copyText(myVirtualIp); vibrate(8)"
              />
            </div>

            <div class="d-flex align-center ga-2 mt-3 pt-2 border-t flex-wrap">
              <div class="et-badge et-badge--cyan">
                <v-icon size="12">mdi-router-wireless</v-icon>
                <span class="mono">{{ myDevName }}</span>
              </div>
              <div class="et-badge" :class="myNatTypeStr.includes('全锥') || myNatTypeStr.includes('Full') || myNatTypeStr.includes('开放') ? 'et-badge--teal' : 'et-badge--amber'">
                <v-icon size="12">mdi-shield-check</v-icon>
                <span>NAT: {{ myNatTypeStr }}</span>
              </div>
            </div>
          </div>
        </div>

        <div class="et-section">
          <div class="et-section-label">{{ t('status.live_bandwidth') }}</div>
          <div class="speed-cards-grid mb-2">
            <div class="speed-box">
              <div class="d-flex align-center ga-1 text-caption font-weight-bold" style="color: var(--et-accent);">
                <v-icon size="14" color="primary">mdi-arrow-up</v-icon>
                <span>{{ t('upload') }}</span>
              </div>
              <div class="speed-val text-mono et-num"><span :key="txRate" class="et-tick">{{ txRate }}</span>/s</div>
              <div class="text-caption text-medium-emphasis text-mono et-num"><span :key="totalTxFormatted" class="et-tick">{{ totalTxFormatted }}</span> {{ t('status.total') }}</div>
            </div>
            <div class="speed-box">
              <div class="d-flex align-center ga-1 text-caption font-weight-bold" style="color: var(--et-info);">
                <v-icon size="14" color="info">mdi-arrow-down</v-icon>
                <span>{{ t('download') }}</span>
              </div>
              <div class="speed-val text-mono et-num"><span :key="rxRate" class="et-tick">{{ rxRate }}</span>/s</div>
              <div class="text-caption text-medium-emphasis text-mono et-num"><span :key="totalRxFormatted" class="et-tick">{{ totalRxFormatted }}</span> {{ t('status.total') }}</div>
            </div>
          </div>
          <div class="et-group pa-2">
            <NetworkChart :upload-rate="txRate" :download-rate="rxRate" />
          </div>
        </div>

        <div class="et-section">
          <div class="et-section-label">{{ t('status.features') }}</div>
          <div class="et-group">
            <div class="et-row">
              <div class="d-flex align-center ga-3">
                <div class="et-squircle" style="background: var(--et-accent-quiet);">
                  <v-icon size="18" color="primary">mdi-vpn</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">{{ t('status.vpn_portal') }}</span>
              </div>
              <v-btn variant="text" size="small" color="primary" rounded="pill" @click="showVpnPortalConfig">
                {{ t('show_vpn_portal_config') }}
              </v-btn>
            </div>

            <div class="et-row">
              <div class="d-flex align-center ga-3">
                <div class="et-squircle" style="background: var(--et-warn-quiet);">
                  <v-icon size="18" color="warning">mdi-pulse</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">{{ t('event_log') }}</span>
              </div>
              <v-btn variant="text" size="small" color="primary" rounded="pill" @click="showEventLogs">
                {{ t('show_event_log') }}
              </v-btn>
            </div>

            <button type="button" class="et-row et-row-pressable et-press-row" :aria-expanded="showNodeDetails" @click="showNodeDetails = !showNodeDetails">
              <div class="d-flex align-center ga-3">
                <div class="et-squircle" style="background: var(--et-info-quiet);">
                  <v-icon size="18" color="info">mdi-information-outline</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">{{ showNodeDetails ? t('hide_node_details') : t('show_node_details') }}</span>
              </div>
              <v-icon size="20" color="medium-emphasis">{{ showNodeDetails ? 'mdi-chevron-up' : 'mdi-chevron-down' }}</v-icon>
            </button>
          </div>

          <v-expand-transition>
            <div v-show="showNodeDetails" class="mt-2 px-1">
              <TransitionGroup tag="div" name="et-list-fade" class="d-flex flex-wrap ga-1 et-list-wrap">
                <v-chip v-for="chip in myNodeInfoChips" :key="chip.label" size="x-small" variant="tonal" class="rounded-pill">
                  <v-icon v-if="chip.icon" start size="12">{{ chip.icon }}</v-icon>
                  {{ chip.label }}
                </v-chip>
              </TransitionGroup>
            </div>
          </v-expand-transition>
        </div>
      </div>

      <div v-if="showDevices" class="devices-tab-content">
        <div class="et-search mb-3">
          <v-text-field
            v-model="peerSearch"
            prepend-inner-icon="mdi-magnify"
            :placeholder="t('status.search_devices')"
            variant="solo"
            flat
            hide-details
            type="search"
            enterkeyhint="search"
            autocomplete="off"
            class="et-search-field"
          />
        </div>

        <div class="et-filter-scroll mb-3">
          <button type="button" class="et-filter" :class="{ 'is-on': peerFilter === 'all' }" :aria-pressed="peerFilter === 'all'" @click="peerFilter = 'all'">
            {{ t('status.filter_all') }} {{ peerRowsAll.length }}
          </button>
          <button type="button" class="et-filter" :class="{ 'is-on': peerFilter === 'direct' }" :aria-pressed="peerFilter === 'direct'" @click="peerFilter = 'direct'">
            {{ t('status.filter_direct') }}
          </button>
          <button type="button" class="et-filter" :class="{ 'is-on': peerFilter === 'relay' }" :aria-pressed="peerFilter === 'relay'" @click="peerFilter = 'relay'">
            {{ t('status.filter_relay') }}
          </button>
          <button type="button" class="et-filter" :class="{ 'is-on': peerFilter === 'server' }" :aria-pressed="peerFilter === 'server'" @click="peerFilter = 'server'">
            {{ t('status.filter_server') }}
          </button>
        </div>

        <div class="et-section">
          <div class="et-section-label">
            {{ t('status.mesh_devices') }} (<span class="et-num">{{ filteredPeerRows.length }}</span>)
          </div>
          <div class="et-group">
            <TransitionGroup tag="div" name="et-list-fade" class="et-list-wrap">
              <!-- PeerRow:状态点 / 虚拟 IP / 路径 / 延迟(右对齐等宽) -->
              <button
                v-for="row in filteredPeerRows"
                :key="row.key"
                type="button"
                class="et-peer et-row-pressable et-press-row"
                :class="{ 'is-offline': row.offline }"
                @click="inspectPeer(row)"
              >
                <span class="et-peer__dot" :class="peerDotClass(row)" aria-hidden="true" />
                <span class="et-peer__id">
                  <span class="et-peer__head">
                    <span class="et-peer__name et-nowrap">{{ row.info?.route?.hostname || '—' }}</span>
                    <span v-if="isPublicServerRoute(row.info)" class="et-peer__tag">{{ t('status.server') }}</span>
                    <span v-else-if="shouldAvoidRelayData(row.info)" class="et-peer__tag is-warn">{{ t('status.relay') }}</span>
                  </span>
                  <span class="et-peer__ip et-nowrap" :title="ipFormat(row.info)">{{ ipFormat(row.info) || '—' }}</span>
                </span>
                <span class="et-peer__path" :title="peerPathLabel(row)">{{ peerPathLabel(row) }}</span>
                <span class="et-peer__rtt" :class="peerRttClass(row)">{{ peerRttText(row) }}</span>
              </button>
            </TransitionGroup>

            <!-- 统一空态:图标 + 引导 + 条件性主操作(清除筛选) -->
            <div v-if="filteredPeerRows.length === 0" class="et-empty">
              <div class="et-empty__icon">
                <v-icon size="26" color="primary">{{ peersFilteredActive ? 'mdi-magnify-close' : 'mdi-devices-plus' }}</v-icon>
              </div>
              <div class="et-empty__title">{{ t('status.no_devices') }}</div>
              <div class="et-empty__hint">
                {{ peersFilteredActive
                  ? t('status.no_devices_filtered_hint', 'No match for current search or filter')
                  : t('status.no_devices_hint', 'Waiting for peers to join this network') }}
              </div>
              <v-btn
                v-if="peersFilteredActive"
                class="mt-3"
                size="small"
                variant="tonal"
                color="primary"
                rounded="pill"
                :prepend-icon="'mdi-filter-remove-outline'"
                @click="resetPeerFilters"
              >
                {{ t('status.clear_filters', 'Clear filters') }}
              </v-btn>
            </div>
          </div>
        </div>
      </div>
    </template>

    <v-bottom-sheet v-model="peerSheetOpen" scrollable>
      <v-card rounded="t-xl" class="et-sheet">
        <!-- 关闭热区:原生 button,键盘可聚焦,视觉仍是一根小药丸 -->
        <button type="button" class="sheet-grabber-hit" :aria-label="t('close')" @click="peerSheetOpen = false">
          <span class="sheet-grabber" aria-hidden="true" />
        </button>
        <v-card-title class="d-flex align-center ga-3 pt-2">
          <div class="device-squircle is-direct">
            <v-icon size="20">{{ peerDeviceIcon(selectedPeer) }}</v-icon>
          </div>
          <div class="min-w-0">
            <div class="text-subtitle-1 font-weight-bold truncate">{{ selectedPeer?.route?.hostname }}</div>
            <div class="text-caption text-mono text-medium-emphasis et-selectable">{{ ipFormat(selectedPeer) }}</div>
          </div>
          <v-spacer />
          <v-btn
            icon="mdi-close"
            variant="text"
            size="small"
            :aria-label="t('close')"
            @click="peerSheetOpen = false"
          />
        </v-card-title>
        <v-card-text class="pa-4 pt-0">
          <div class="et-section mb-3">
            <div class="et-section-label">{{ t('status.connectivity') }}</div>
            <div class="et-group">
              <div class="et-row">
                <span>{{ t('web.device.status') }}</span>
                <span :class="selectedPeerOffline ? 'text-medium-emphasis' : ''">
                  {{ selectedPeerOffline ? t('web.device.offline') : t('status.connected') }}
                </span>
              </div>
              <div class="et-row">
                <span>{{ t('status.route_cost') }}</span>
                <span class="font-weight-medium">{{ routeCost(selectedPeer) }}</span>
              </div>
              <div class="et-row">
                <span>{{ t('status.ping') }}</span>
                <span class="text-mono font-weight-bold" :style="{ color: selectedPeerOffline ? 'var(--et-text-3)' : 'var(--et-accent)' }">
                  {{ selectedPeer && !selectedPeerOffline ? dash(latencyMs(selectedPeer)) : '—' }}
                </span>
              </div>
              <div class="et-row">
                <span>{{ t('status.packet_loss') }}</span>
                <span class="text-mono">{{ selectedPeer && !selectedPeerOffline ? dash(lossRate(selectedPeer)) : '—' }}</span>
              </div>
              <div class="et-row">
                <span>{{ t('tunnel_proto') }}</span>
                <span class="text-mono">{{ selectedPeer ? dash(tunnelProto(selectedPeer)) : '—' }}</span>
              </div>
              <div class="et-row">
                <span>{{ t('nat_type') }}</span>
                <span>{{ selectedPeer ? dash(natType(selectedPeer)) : '—' }}</span>
              </div>
              <div class="et-row">
                <span>{{ t('status.version') }}</span>
                <span class="text-mono">{{ selectedPeer ? version(selectedPeer) : '—' }}</span>
              </div>
            </div>
          </div>

          <div class="et-section mb-4">
            <div class="et-section-label">{{ t('status.traffic') }}</div>
            <div class="et-group">
              <div class="et-row">
                <span>{{ t('status.uploaded') }}</span>
                <span class="text-mono">{{ selectedPeer ? txBytes(selectedPeer) : '—' }}</span>
              </div>
              <div class="et-row">
                <span>{{ t('status.downloaded') }}</span>
                <span class="text-mono">{{ selectedPeer ? rxBytes(selectedPeer) : '—' }}</span>
              </div>
            </div>
          </div>

          <v-btn block color="primary" variant="flat" size="large" rounded="pill" @click="copyText(ipFormat(selectedPeer))">
            <v-icon start>mdi-content-copy</v-icon>
            {{ t('status.copy_ip') }}
          </v-btn>
        </v-card-text>
      </v-card>
    </v-bottom-sheet>

    <v-snackbar v-model="copyToast" timeout="1600" location="top" rounded="pill" color="success">
      {{ t('status.copied') }}
    </v-snackbar>
  </div>
</template>

<style scoped>
.status-root {
  width: 100%;
}

/* Rows rendered as a native <button> need UA chrome stripped while keeping the
 * global .et-row layout and .et-row-pressable feedback. */
button.et-row {
  width: 100%;
  border: 0;
  background: transparent;
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
  appearance: none;
  -webkit-appearance: none;
}

/* Non-colour selection cue for the filter pills (aria-pressed also carries the
 * state for assistive tech). */
.et-filter.is-on::after {
  content: '';
  display: inline-block;
  width: 5px;
  height: 5px;
  margin-left: 6px;
  border-radius: 50%;
  background: currentColor;
  vertical-align: middle;
}

/* Bottom sheet grabber hit area: a real <button> so it is keyboard focusable,
 * >=48px tall, and has an accessible name. The 40x4.5px visual bar is unchanged. */
.sheet-grabber-hit {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  min-height: var(--et-touch);
  margin-top: var(--et-space-1);
  padding: 0;
  border: 0;
  background: transparent;
  cursor: pointer;
  appearance: none;
  -webkit-appearance: none;
}

.sheet-grabber-hit .sheet-grabber {
  margin: 0;
}

.et-hero {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: var(--et-space-5) 0 var(--et-space-6);
  overflow: hidden;
}

.et-hero-mesh {
  position: absolute;
  inset: -20% -10% 20%;
  background:
    radial-gradient(circle at 50% 40%, var(--et-accent-quiet), transparent 58%),
    repeating-radial-gradient(circle at 50% 42%, transparent 0 18px, color-mix(in srgb, var(--et-accent) 5%, transparent) 19px 20px);
  /* Keep the decorative mesh on a lower layer than the z-index:1 hero content
   * so it never swallows taps. */
  z-index: var(--et-z-base);
  mask-image: linear-gradient(to bottom, black 40%, transparent);
}

.et-power-orb {
  position: relative;
  width: 112px;
  height: 112px;
  border-radius: 50%;
  border: none;
  background: var(--et-surface-1);
  color: var(--et-text-2);
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: var(--et-shadow-2);
  z-index: var(--et-z-base);
  -webkit-tap-highlight-color: transparent;
}

.et-orb-ring {
  position: absolute;
  border-radius: 50%;
}

.et-orb-ring.r1 {
  inset: -6px;
  border: 2px solid var(--et-border);
}

.et-orb-ring.r2 {
  inset: -14px;
  border: 1px dashed var(--et-border);
}

/* 五态配色。形状与文字由下方 .et-signal 承担,这里只做颜色层。 */
.et-power-orb.is-up {
  color: var(--et-accent);
  background: color-mix(in srgb, var(--et-accent) 14%, var(--et-surface-1));
}

.et-power-orb.is-sync {
  color: var(--et-info);
  background: color-mix(in srgb, var(--et-info) 14%, var(--et-surface-1));
}

.et-power-orb.is-warn {
  color: var(--et-warn);
  background: color-mix(in srgb, var(--et-warn) 14%, var(--et-surface-1));
}

.et-power-orb.is-down {
  color: var(--et-danger);
  background: color-mix(in srgb, var(--et-danger) 14%, var(--et-surface-1));
}

.et-power-orb.is-idle {
  color: var(--et-text-2);
  background: var(--et-surface-1);
}

.et-power-orb.is-up .et-orb-ring.r1,
.et-power-orb.is-sync .et-orb-ring.r1 {
  border-color: color-mix(in srgb, currentColor 65%, transparent);
}

.et-power-orb.is-up .et-orb-ring.r2,
.et-power-orb.is-sync .et-orb-ring.r2 {
  border-color: color-mix(in srgb, currentColor 28%, transparent);
}

/* 呼吸动画只在"连接中"使用 */
.et-power-orb.is-sync .et-orb-ring.r1 {
  box-shadow: 0 0 28px color-mix(in srgb, var(--et-info) 45%, transparent);
  animation: et-orb 2.8s var(--et-ease-standard) infinite;
}

/* ---------- 状态信号:色 + 形 + 字 ---------- */
.et-signal {
  display: inline-flex;
  align-items: center;
  gap: var(--et-space-2);
  padding: 5px 12px 5px 10px;
  border-radius: var(--et-radius-pill);
  font-size: var(--et-font-caption);
  font-weight: var(--et-weight-medium);
  z-index: var(--et-z-base);
}

.et-signal__glyph {
  width: 12px;
  height: 12px;
  flex: 0 0 auto;
  display: grid;
  place-items: center;
}

.et-signal__glyph::before {
  content: '';
  display: block;
  background: currentColor;
}

.et-signal.is-up {
  background: var(--et-accent-quiet);
  color: var(--et-accent);
}

.et-signal.is-up .et-signal__glyph::before {
  width: 12px;
  height: 12px;
  border-radius: 50%;
}

.et-signal.is-sync {
  background: var(--et-info-quiet);
  color: var(--et-info);
}

.et-signal.is-sync .et-signal__glyph::before {
  width: 12px;
  height: 12px;
  border-radius: 3px;
  animation: et-signal-pulse 1.4s var(--et-ease-standard) infinite;
}

.et-signal.is-warn {
  background: var(--et-warn-quiet);
  color: var(--et-warn);
}

.et-signal.is-warn .et-signal__glyph::before {
  width: 0;
  height: 0;
  background: none;
  border-left: 7px solid transparent;
  border-right: 7px solid transparent;
  border-bottom: 12px solid currentColor;
}

.et-signal.is-down {
  background: var(--et-danger-quiet);
  color: var(--et-danger);
}

.et-signal.is-down .et-signal__glyph::before {
  width: 12px;
  height: 3px;
  border-radius: 2px;
}

.et-signal.is-idle {
  background: var(--et-neutral-quiet);
  color: var(--et-neutral);
}

.et-signal.is-idle .et-signal__glyph::before {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: none;
  border: 2px solid currentColor;
}

@keyframes et-signal-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.35; }
}

.et-power-orb:active {
  transform: scale(0.985);
}

/* 只读状态球:不是控件,所以不给手型光标与按压缩放。 */
.et-power-orb.is-readonly {
  cursor: default;
}

.et-power-orb.is-readonly:active {
  transform: none;
}

@keyframes et-orb {
  0%, 100% { transform: scale(1); opacity: 1; }
  50% { transform: scale(1.04); opacity: 0.85; }
}

.et-hero-meta,
.et-hero-hint {
  z-index: var(--et-z-base);
  color: var(--et-text-2);
  font-size: var(--et-font-caption);
  margin-top: var(--et-space-1);
}

.et-hero-hint { opacity: 0.8; }

.speed-cards-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--et-gap-stack);
}

.speed-box {
  background: var(--et-surface-1);
  border-radius: var(--et-radius-md);
  padding: var(--et-space-4);
  border: 1px solid var(--et-border);
}

.speed-val {
  font-size: var(--et-font-headline);
  font-weight: var(--et-weight-semibold);
  letter-spacing: -0.03em;
  margin: var(--et-space-1) 0;
}

/* 输入控件边界用 --et-control-border(装饰性的 --et-border 没有对比度保证)。
 * 双写 .v-field 提升优先级,替代原来的 !important。 */
.et-search-field :deep(.v-field.v-field) {
  background: var(--et-surface-1);
  border-radius: var(--et-radius-md);
  border: 1px solid var(--et-control-border);
  min-height: var(--et-touch-min);
}

.et-filter-scroll {
  display: flex;
  gap: var(--et-touch-gap);
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
  padding-bottom: 2px;
}

.et-filter {
  flex: 0 0 auto;
  min-height: var(--et-touch-min);
  padding: 0 var(--et-space-4);
  border-radius: var(--et-radius-pill);
  border: 1px solid var(--et-control-border);
  background: var(--et-surface-1);
  color: var(--et-text-2);
  font-size: var(--et-font-body-sm);
  font-weight: var(--et-weight-semibold);
  cursor: pointer;
}

.et-filter.is-on {
  background: var(--et-accent-quiet);
  color: var(--et-accent);
  border-color: color-mix(in srgb, var(--et-accent) 45%, transparent);
}

/* ---------- PeerRow:状态点 / 虚拟 IP / 路径 / 延迟 ---------- */
.et-peer {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto auto;
  align-items: center;
  gap: var(--et-space-3);
  width: 100%;
  min-height: var(--et-row-h);
  padding: var(--et-space-2) var(--et-pad-card);
  border: 0;
  border-bottom: 1px solid var(--et-border);
  background: transparent;
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
  appearance: none;
  -webkit-appearance: none;
}

.et-peer:last-child { border-bottom: none; }

.et-peer__dot {
  width: var(--et-space-2);
  height: var(--et-space-2);
  box-sizing: border-box;
  border-radius: 50%;
  background: var(--et-neutral);
  flex: 0 0 auto;
}

.et-peer__dot.is-good { background: var(--et-accent); }
.et-peer__dot.is-mid,
.et-peer__dot.is-warn { background: var(--et-warn); }
.et-peer__dot.is-idle {
  background: transparent;
  border: 2px solid var(--et-neutral);
}

.et-peer__id {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 0;
}

.et-peer__head {
  display: flex;
  align-items: center;
  gap: var(--et-space-1);
  min-width: 0;
}

.et-peer__name {
  font-size: var(--et-font-body-sm);
  font-weight: var(--et-weight-medium);
  color: var(--et-text);
}

.et-peer__tag {
  flex: 0 0 auto;
  font-size: var(--et-font-micro);
  line-height: 1.4;
  padding: 0 var(--et-space-1);
  border-radius: var(--et-radius-pill);
  color: var(--et-info);
  border: 1px solid color-mix(in srgb, var(--et-info) 35%, transparent);
}

.et-peer__tag.is-warn {
  color: var(--et-warn);
  border-color: color-mix(in srgb, var(--et-warn) 35%, transparent);
}

.et-peer__ip {
  font-family: var(--et-font-data);
  font-variant-numeric: var(--et-numeric);
  font-size: var(--et-font-caption);
  color: var(--et-text-2);
}

.et-peer__path {
  max-width: 42%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--et-font-caption);
  color: var(--et-text-2);
}

.et-peer__rtt {
  min-width: var(--et-space-16);
  text-align: right;
  font-family: var(--et-font-data);
  font-variant-numeric: var(--et-numeric);
  font-size: var(--et-font-caption);
  color: var(--et-text);
}

.et-peer__rtt.is-good { color: var(--et-accent); }
.et-peer__rtt.is-mid,
.et-peer__rtt.is-warn { color: var(--et-warn); }
.et-peer__rtt.is-idle { color: var(--et-text-3); }

.et-peer.is-offline .et-peer__name { color: var(--et-text-2); }

/* TransitionGroup 容器:为 leave-active 的绝对定位提供包含块 */
.et-list-wrap {
  position: relative;
  display: block;
}

.device-squircle {
  width: 36px;
  height: 36px;
  border-radius: var(--et-radius-sm);
  display: flex;
  align-items: center;
  justify-content: center;
}

.device-squircle.is-direct {
  background: var(--et-accent-quiet);
  color: var(--et-accent);
}

.device-squircle.is-relay {
  background: var(--et-warn-quiet);
  color: var(--et-warn);
}

/* 双写类名提升优先级,替代原来的 !important */
.v-card.et-sheet,
.v-card.et-dialog-sheet {
  background: var(--et-surface-1);
}

.vpn-client-config {
  background: var(--et-surface-2);
  padding: var(--et-space-2);
  border-radius: var(--et-radius-sm);
  font-size: var(--et-font-caption);
  font-family: var(--et-font-data);
  overflow-x: auto;
}

.border-b {
  border-bottom: 1px solid var(--et-border);
}

.truncate {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.text-mono {
  font-family: var(--et-font-data);
}

/* ---------- 数字质感 ---------- */
.et-num {
  font-variant-numeric: tabular-nums;
}

/* ---------- 骨架 ---------- */
.et-skeleton.v-skeleton-loader {
  background: transparent;
  width: 100%;
}

.et-skeleton-stack {
  display: flex;
  flex-direction: column;
  gap: var(--et-gap-stack);
  padding: var(--et-space-1) var(--et-space-1) var(--et-space-4);
}

/* ---------- 空态 ---------- */
.et-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: var(--et-space-8) var(--et-space-5);
  color: var(--et-text-2);
}

.et-empty__icon {
  width: 64px;
  height: 64px;
  border-radius: var(--et-radius-lg);
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--et-accent-quiet);
  margin-bottom: var(--et-space-3);
  flex-shrink: 0;
}

.et-empty__title {
  font-size: var(--et-font-body);
  font-weight: var(--et-weight-semibold);
  color: var(--et-text);
}

.et-empty__hint {
  font-size: var(--et-font-body-sm);
  line-height: var(--et-leading-normal);
  max-width: 18rem;
  margin-top: var(--et-space-1);
}

/* ---------- 动效(仅在允许动效的设备上启用) ---------- */
@media (prefers-reduced-motion: no-preference) {
  /* 数值刷新柔和过渡:key 触发重挂载 → 60ms fade */
  .et-tick {
    animation: et-tick-in var(--et-dur-instant) var(--et-ease-standard);
  }

  .et-press-row,
  .speed-box {
    transition:
      transform var(--et-dur-fast) var(--et-ease-standard),
      background-color var(--et-dur-fast) var(--et-ease-standard),
      opacity var(--et-dur-fast) var(--et-ease-standard);
  }

  .et-press-row:active {
    transform: scale(0.985);
  }

  .et-power-orb {
    transition: transform var(--et-dur-fast) var(--et-ease-standard);
  }

  /* 列表进出场:12px 位移 + opacity,退出与进入同长(令牌已收敛) */
  .et-list-fade-enter-active,
  .et-list-fade-leave-active {
    transition:
      opacity var(--et-dur-base) var(--et-ease-standard),
      transform var(--et-dur-base) var(--et-ease-standard);
  }

  .et-list-fade-enter-from,
  .et-list-fade-leave-to {
    opacity: 0;
    transform: translateY(12px);
  }

  .et-list-fade-leave-active {
    position: absolute;
    width: 100%;
  }

  .et-list-fade-move {
    transition: transform var(--et-dur-base) var(--et-ease-standard);
  }

  .et-skeleton :deep(.v-skeleton-loader__bone::after) {
    background: linear-gradient(
      90deg,
      transparent,
      color-mix(in srgb, var(--et-accent) 10%, transparent),
      transparent
    );
  }
}

@keyframes et-tick-in {
  from { opacity: 0.35; }
  to { opacity: 1; }
}

@media (prefers-reduced-motion: reduce) {
  /* 呼吸动画是"连接中"的专属状态提示,reduced-motion 下必须停 */
  .et-power-orb.is-sync .et-orb-ring,
  .et-signal.is-sync .et-signal__glyph::before {
    animation: none;
  }
}
</style>
