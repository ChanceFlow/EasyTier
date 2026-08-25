<script setup lang="ts">
import { useTimeAgo } from '@vueuse/core'
import { NetworkInstance, VpnPortalClientState, type TunnelInfo, type NodeInfo, type PeerRoutePair, type VpnPortalClientInfo, type VpnPortalInfo } from '../types/network'
import type { RemoteClient } from '../modules/api'
import { useI18n } from 'vue-i18n';
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useDisplay } from 'vuetify';
import { ipv4InetToString, ipv4ToString, ipv6ToString } from '../modules/utils';
import { latencyMs, lossRate, numericValue, peerConns } from '../modules/statusDisplay';
import NetworkChart from './NetworkChart.vue';
import HumanEvent from './HumanEvent.vue';

const props = withDefaults(defineProps<{
  curNetworkInst: NetworkInstance | null,
  api: RemoteClient,
  activeTab?: string,
}>(), {
  activeTab: 'all',
})

defineEmits(['switch-tab', 'start-network', 'stop-network', 'toggle-network'])

const { t } = useI18n()
const { smAndDown } = useDisplay()

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

const filteredPeers = computed(() => {
  let list = peerRouteInfos.value
  if (peerFilter.value === 'direct') {
    list = list.filter(p => !p.route?.cost || p.route.cost === 1)
  } else if (peerFilter.value === 'relay') {
    list = list.filter(p => p.route?.cost && p.route.cost > 1)
  } else if (peerFilter.value === 'server') {
    list = list.filter(p => isPublicServerRoute(p))
  }

  if (peerSearch.value.trim()) {
    const q = peerSearch.value.trim().toLowerCase()
    list = list.filter(p => {
      const h = (p.route?.hostname || '').toLowerCase()
      const ip = ipFormat(p).toLowerCase()
      return h.includes(q) || ip.includes(q)
    })
  }

  return list
})

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
  if (hostname.includes('nas') || hostname.includes('server')) return 'mdi-server'
  if (hostname.includes('gw') || hostname.includes('router')) return 'mdi-router-wireless'
  return info.route.cost === 1 ? 'mdi-lightning-bolt' : 'mdi-transit-connection-variant'
}

function peerRouteCostColor(info: any): string {
  if (!info?.route?.cost) return 'primary'
  return info.route.cost === 1 ? 'success' : 'warning'
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
const peerSheetOpen = ref(false)

function inspectPeer(info: any) {
  selectedPeer.value = info
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
    setTimeout(() => { ipCopied.value = false }, 2000)
  } catch (e) {
    console.error('Failed to copy', e)
  }
}

onMounted(() => {
  rateIntervalId = window.setInterval(() => {
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
  } catch (error) {
    console.error('Failed to copy VPN Portal client config', error)
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

const myHostname = computed(() => {
  return props.curNetworkInst?.detail?.my_node_info?.hostname || 'easytier-node'
})

</script>

<template>
  <div class="frontend-lib status-root">
    <v-dialog v-model="dialogVisible" max-width="500px" :fullscreen="smAndDown">
      <v-card :title="t(dialogHeader)" rounded="xl" class="et-dialog-sheet">
        <v-card-text class="pa-4">
          <div v-if="dialogHeader === 'vpn_portal_config'" class="vpn-dialog-body">
            <div v-if="vpnPortalLoading" class="pa-8 text-center text-medium-emphasis">
              <v-progress-circular indeterminate color="primary" class="mb-2" />
              <div>{{ t('web.device_management.loading_network_status') }}</div>
            </div>
            <div v-else-if="vpnPortalError" class="pa-4 text-error">
              {{ vpnPortalError }}
            </div>
            <div v-else-if="!vpnPortalInfo || ((!vpnPortalInfo.vpn_type || vpnPortalInfo.vpn_type === 'null') && vpnPortalClients.length === 0)"
              class="pa-6 text-center text-medium-emphasis">
              <v-icon size="40" class="mb-2 text-medium-emphasis">mdi-vpn</v-icon>
              <div>{{ t('vpn_portal_not_configured') }}</div>
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

              <div v-for="client in vpnPortalClients" :key="client.name" class="et-group pa-3 mb-2">
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
            </div>
          </div>

          <div v-else class="event-log-body">
            <v-timeline v-if="dialogContent.length" side="end" density="compact" class="pa-2">
              <v-timeline-item
                v-for="(item, i) in dialogContent"
                :key="i"
                dot-color="primary"
                size="small"
              >
                <small class="text-caption text-medium-emphasis d-block mb-1">{{ useTimeAgo(Date.parse(item.time)) }}</small>
                <HumanEvent :event="item.event" />
              </v-timeline-item>
            </v-timeline>
            <div v-else class="pa-8 text-center text-medium-emphasis">{{ t('no_events') }}</div>
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

    <template v-else>
      <div v-if="showHome" class="home-tab-content">
        <div class="et-hero">
          <div class="et-hero-mesh" aria-hidden="true" />
          <button
            type="button"
            class="et-power-orb"
            :class="{ 'is-on': isRunning }"
            :aria-pressed="isRunning"
            :aria-label="isRunning ? t('status.disconnect') : t('status.connect')"
            @click="$emit('toggle-network')"
          >
            <span class="et-orb-ring" />
            <v-icon size="40">{{ isRunning ? 'mdi-shield-check' : 'mdi-power' }}</v-icon>
          </button>

          <div class="et-hero-state" :class="isRunning ? 'is-on' : 'is-off'">
            {{ isRunning ? t('status.connected') : t('status.disconnected') }}
          </div>
          <div class="et-hero-meta">
            {{ myHostname }} · {{ otherPeerCount }} {{ t('status.devices_unit') }}
          </div>
          <div class="et-hero-hint">
            {{ isRunning ? t('status.tap_to_disconnect') : t('status.tap_to_connect') }}
          </div>
        </div>

        <div class="et-section">
          <div class="et-section-label">{{ t('status.network_identity') }}</div>
          <div class="et-group">
            <div v-if="myVirtualIp" class="et-row et-row-pressable" @click="copyText(myVirtualIp)">
              <div class="d-flex align-center ga-3 min-w-0">
                <div class="et-squircle" style="background: var(--et-accent);">
                  <v-icon size="18" color="onPrimary">mdi-ip-network-outline</v-icon>
                </div>
                <div class="min-w-0">
                  <div class="text-caption text-medium-emphasis">{{ t('status.virtual_ip') }}</div>
                  <div class="text-body-1 font-weight-bold text-mono et-selectable">{{ myVirtualIp }}</div>
                </div>
              </div>
              <v-btn
                :icon="ipCopied ? 'mdi-check' : 'mdi-content-copy'"
                :color="ipCopied ? 'success' : 'default'"
                variant="text"
                size="small"
                :aria-label="t('status.copy_ip')"
              />
            </div>

            <div class="et-row">
              <div class="d-flex align-center ga-3">
                <div class="et-squircle" style="background: var(--et-info);">
                  <v-icon size="18" color="white">mdi-router-wireless</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">{{ t('status.tun_interface') }}</span>
              </div>
              <span class="text-body-2 text-mono text-medium-emphasis">{{ myDevName }}</span>
            </div>

            <div class="et-row">
              <div class="d-flex align-center ga-3">
                <div class="et-squircle" style="background: var(--et-warning);">
                  <v-icon size="18" color="white">mdi-shield-outline</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">{{ t('nat_type') }}</span>
              </div>
              <span class="text-body-2 text-medium-emphasis">{{ myNatTypeStr }}</span>
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
              <div class="speed-val text-mono">{{ txRate }}/s</div>
              <div class="text-caption text-medium-emphasis text-mono">{{ totalTxFormatted }} {{ t('status.total') }}</div>
            </div>
            <div class="speed-box">
              <div class="d-flex align-center ga-1 text-caption font-weight-bold" style="color: var(--et-info);">
                <v-icon size="14" color="info">mdi-arrow-down</v-icon>
                <span>{{ t('download') }}</span>
              </div>
              <div class="speed-val text-mono">{{ rxRate }}/s</div>
              <div class="text-caption text-medium-emphasis text-mono">{{ totalRxFormatted }} {{ t('status.total') }}</div>
            </div>
          </div>
          <div class="et-group pa-2">
            <NetworkChart :upload-rate="txRate" :download-rate="rxRate" />
          </div>
        </div>

        <div class="et-section">
          <div class="et-section-label">{{ t('status.features') }}</div>
          <div class="et-group">
            <div class="et-row et-row-pressable" @click="showVpnPortalConfig">
              <div class="d-flex align-center ga-3">
                <div class="et-squircle" style="background: #7c5cbf;">
                  <v-icon size="18" color="white">mdi-vpn</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">{{ t('status.vpn_portal') }}</span>
              </div>
              <v-btn variant="text" size="small" color="primary" rounded="pill" @click.stop="showVpnPortalConfig">
                {{ t('show_vpn_portal_config') }}
              </v-btn>
            </div>

            <div class="et-row et-row-pressable" @click="showEventLogs">
              <div class="d-flex align-center ga-3">
                <div class="et-squircle" style="background: var(--et-warning);">
                  <v-icon size="18" color="white">mdi-pulse</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">{{ t('event_log') }}</span>
              </div>
              <v-btn variant="text" size="small" color="primary" rounded="pill" @click.stop="showEventLogs">
                {{ t('show_event_log') }}
              </v-btn>
            </div>

            <div class="et-row et-row-pressable" @click="showNodeDetails = !showNodeDetails">
              <div class="d-flex align-center ga-3">
                <div class="et-squircle" style="background: var(--et-info);">
                  <v-icon size="18" color="white">mdi-information-outline</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">{{ showNodeDetails ? t('hide_node_details') : t('show_node_details') }}</span>
              </div>
              <v-icon size="20" color="medium-emphasis">{{ showNodeDetails ? 'mdi-chevron-up' : 'mdi-chevron-down' }}</v-icon>
            </div>
          </div>

          <v-expand-transition>
            <div v-show="showNodeDetails" class="mt-2 px-1">
              <div class="d-flex flex-wrap ga-1">
                <v-chip v-for="(chip, i) in myNodeInfoChips" :key="i" size="x-small" variant="tonal" class="rounded-pill">
                  <v-icon v-if="chip.icon" start size="12">{{ chip.icon }}</v-icon>
                  {{ chip.label }}
                </v-chip>
              </div>
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

        <div class="et-filter-scroll mb-3" role="tablist">
          <button type="button" class="et-filter" :class="{ 'is-on': peerFilter === 'all' }" @click="peerFilter = 'all'">
            {{ t('status.filter_all') }} {{ peerRouteInfos.length }}
          </button>
          <button type="button" class="et-filter" :class="{ 'is-on': peerFilter === 'direct' }" @click="peerFilter = 'direct'">
            {{ t('status.filter_direct') }}
          </button>
          <button type="button" class="et-filter" :class="{ 'is-on': peerFilter === 'relay' }" @click="peerFilter = 'relay'">
            {{ t('status.filter_relay') }}
          </button>
          <button type="button" class="et-filter" :class="{ 'is-on': peerFilter === 'server' }" @click="peerFilter = 'server'">
            {{ t('status.filter_server') }}
          </button>
        </div>

        <div class="et-section">
          <div class="et-section-label">{{ t('status.mesh_devices') }} ({{ filteredPeers.length }})</div>
          <div class="et-group">
            <div
              v-for="(info, i) in filteredPeers"
              :key="i"
              class="et-device-cell et-row-pressable"
              @click="inspectPeer(info)"
            >
              <div class="d-flex align-center ga-3 min-w-0">
                <div class="device-icon-wrap">
                  <div class="device-squircle" :class="routeCost(info) === 'p2p' || !info.route?.cost ? 'is-direct' : 'is-relay'">
                    <v-icon size="18" color="white">{{ peerDeviceIcon(info) }}</v-icon>
                  </div>
                  <div class="ping-dot" :class="routeCost(info) === 'p2p' || !info.route?.cost ? 'is-direct' : 'is-relay'" />
                </div>
                <div class="min-w-0">
                  <div class="d-flex align-center ga-1">
                    <span class="device-name truncate font-weight-bold">{{ info.route.hostname }}</span>
                    <v-chip v-if="isPublicServerRoute(info)" size="x-small" color="info" variant="tonal">{{ t('status.server') }}</v-chip>
                    <v-chip v-if="shouldAvoidRelayData(info)" size="x-small" color="warning" variant="tonal">{{ t('status.relay') }}</v-chip>
                  </div>
                  <div class="text-caption text-mono text-medium-emphasis et-selectable">{{ ipFormat(info) }}</div>
                </div>
              </div>
              <div class="d-flex align-center ga-2 flex-shrink-0">
                <div class="text-end">
                  <div class="text-mono text-caption font-weight-bold" style="color: var(--et-accent);">{{ dash(latencyMs(info)) }}</div>
                  <v-chip :color="peerRouteCostColor(info)" size="x-small" variant="tonal" class="rounded-pill">
                    {{ routeCost(info) }}
                  </v-chip>
                </div>
                <v-icon size="18" color="medium-emphasis">mdi-chevron-right</v-icon>
              </div>
            </div>

            <div v-if="filteredPeers.length === 0" class="text-center py-10 text-medium-emphasis">
              <v-icon size="36" class="mb-2">mdi-devices</v-icon>
              <div>{{ t('status.no_devices') }}</div>
            </div>
          </div>
        </div>
      </div>
    </template>

    <v-bottom-sheet v-model="peerSheetOpen" scrollable>
      <v-card rounded="t-xl" class="et-sheet">
        <div class="sheet-grabber" @click="peerSheetOpen = false" />
        <v-card-title class="d-flex align-center ga-3 pt-2">
          <div class="device-squircle is-direct">
            <v-icon size="20" color="white">{{ peerDeviceIcon(selectedPeer) }}</v-icon>
          </div>
          <div class="min-w-0">
            <div class="text-subtitle-1 font-weight-bold truncate">{{ selectedPeer?.route?.hostname }}</div>
            <div class="text-caption text-mono text-medium-emphasis et-selectable">{{ ipFormat(selectedPeer) }}</div>
          </div>
        </v-card-title>
        <v-card-text class="pa-4 pt-0">
          <div class="et-section mb-3">
            <div class="et-section-label">{{ t('status.connectivity') }}</div>
            <div class="et-group">
              <div class="et-row">
                <span>{{ t('status.route_cost') }}</span>
                <span class="font-weight-medium">{{ routeCost(selectedPeer) }}</span>
              </div>
              <div class="et-row">
                <span>{{ t('status.ping') }}</span>
                <span class="text-mono font-weight-bold" style="color: var(--et-accent);">{{ selectedPeer ? dash(latencyMs(selectedPeer)) : '—' }}</span>
              </div>
              <div class="et-row">
                <span>{{ t('status.packet_loss') }}</span>
                <span class="text-mono">{{ selectedPeer ? dash(lossRate(selectedPeer)) : '—' }}</span>
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

.et-hero {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 1.25rem 0 1.5rem;
  overflow: hidden;
}

.et-hero-mesh {
  position: absolute;
  inset: -20% -10% 20%;
  background:
    radial-gradient(circle at 50% 40%, var(--et-accent-dim), transparent 58%),
    repeating-radial-gradient(circle at 50% 42%, transparent 0 18px, rgba(30, 200, 163, 0.05) 19px 20px);
  pointer-events: none;
  mask-image: linear-gradient(to bottom, #000 40%, transparent);
}

.et-power-orb {
  position: relative;
  width: 112px;
  height: 112px;
  border-radius: 50%;
  border: none;
  background: var(--et-surface);
  color: var(--et-text-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 8px 28px rgba(0, 0, 0, 0.28);
  z-index: 1;
  -webkit-tap-highlight-color: transparent;
}

.et-orb-ring {
  position: absolute;
  inset: -6px;
  border-radius: 50%;
  border: 2px solid var(--et-border);
}

.et-power-orb.is-on {
  color: var(--et-accent);
  background: color-mix(in srgb, var(--et-accent) 14%, var(--et-surface));
}

.et-power-orb.is-on .et-orb-ring {
  border-color: color-mix(in srgb, var(--et-accent) 55%, transparent);
  box-shadow: 0 0 28px var(--et-glow);
  animation: et-orb 2.8s ease-in-out infinite;
}

.et-power-orb:active {
  transform: scale(0.94);
}

@keyframes et-orb {
  0%, 100% { transform: scale(1); opacity: 1; }
  50% { transform: scale(1.04); opacity: 0.85; }
}

.et-hero-state {
  margin-top: 0.85rem;
  font-size: 1.35rem;
  font-weight: 750;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  z-index: 1;
}

.et-hero-state.is-on { color: var(--et-accent); }
.et-hero-state.is-off { color: var(--et-text-secondary); }

.et-hero-meta,
.et-hero-hint {
  z-index: 1;
  color: var(--et-text-secondary);
  font-size: 0.78rem;
  margin-top: 0.25rem;
}

.et-hero-hint { opacity: 0.8; }

.speed-cards-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.75rem;
}

.speed-box {
  background: var(--et-surface);
  border-radius: 14px;
  padding: 0.85rem 1rem;
  border: 1px solid var(--et-border);
}

.speed-val {
  font-size: 1.2rem;
  font-weight: 700;
  letter-spacing: -0.03em;
  margin: 4px 0 2px;
}

.et-search-field :deep(.v-field) {
  background: var(--et-surface) !important;
  border-radius: 14px !important;
  border: 1px solid var(--et-border);
  min-height: 44px;
}

.et-filter-scroll {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
  padding-bottom: 2px;
}

.et-filter {
  flex: 0 0 auto;
  min-height: 36px;
  padding: 0 14px;
  border-radius: 999px;
  border: 1px solid var(--et-border);
  background: var(--et-surface);
  color: var(--et-text-secondary);
  font-size: 0.8125rem;
  font-weight: 600;
}

.et-filter.is-on {
  background: var(--et-accent-dim);
  color: var(--et-accent);
  border-color: transparent;
}

.et-device-cell {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.8rem 1rem;
  min-height: 56px;
  cursor: pointer;
  border-bottom: 1px solid var(--et-border-hairline);
}

.et-device-cell:last-child { border-bottom: none; }

.device-icon-wrap {
  position: relative;
  flex-shrink: 0;
}

.device-squircle {
  width: 36px;
  height: 36px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.device-squircle.is-direct {
  background: linear-gradient(135deg, #1ec8a3, #0f9d7e);
}

.device-squircle.is-relay {
  background: linear-gradient(135deg, #f5b942, #c98500);
}

.ping-dot {
  position: absolute;
  bottom: -2px;
  right: -2px;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  border: 2px solid var(--et-surface);
}

.ping-dot.is-direct { background: var(--et-accent); }
.ping-dot.is-relay { background: var(--et-warning); }

.device-name {
  font-size: 0.9375rem;
  letter-spacing: -0.01em;
}

.et-sheet, .et-dialog-sheet {
  background: var(--et-surface) !important;
}

.vpn-client-config {
  background: var(--et-surface-2);
  padding: 0.625rem;
  border-radius: 8px;
  font-size: 0.75rem;
  font-family: var(--font-mono);
  overflow-x: auto;
}

.border-b {
  border-bottom: 1px solid var(--et-border-hairline);
}

.truncate {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.text-mono {
  font-family: var(--font-mono);
}

@media (prefers-reduced-motion: reduce) {
  .et-power-orb.is-on .et-orb-ring { animation: none; }
}
</style>
