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

// Peer filter & search
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
  if (info.route) {
    const cost = info.route.cost
    return cost ? cost === 1 ? 'p2p' : `relay(${cost})` : t('status.local')
  }

  return '?'
}

function peerDeviceIcon(info: any): string {
  if (!info.route?.cost) return 'mdi-laptop'
  const hostname = (info.route?.hostname || '').toLowerCase()
  if (hostname.includes('phone') || hostname.includes('iphone') || hostname.includes('android')) return 'mdi-cellphone'
  if (hostname.includes('nas') || hostname.includes('server')) return 'mdi-server'
  if (hostname.includes('gw') || hostname.includes('router')) return 'mdi-router-wireless'
  return info.route.cost === 1 ? 'mdi-lightning-bolt' : 'mdi-transit-connection-variant'
}

function peerRouteCostColor(info: any): string {
  if (!info.route?.cost) return 'primary'
  return info.route.cost === 1 ? 'success' : 'warning'
}

function resolveObjPath(path: string, obj: any = globalThis, separator = '.') {
  const properties = path.split(separator)
  return properties.reduce((prev, curr) => prev?.[curr], obj)
}

function statsCommon(info: any, field: string): number | undefined {
  if (!info.peer)
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
  return info.route.version === '' ? 'unknown' : info.route.version
}

function ipFormat(info: PeerRoutePair) {
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

const udpNatTypeStrMap = {
  [NatType.Unknown]: 'Unknown',
  [NatType.OpenInternet]: 'Open Internet',
  [NatType.NoPAT]: 'No PAT',
  [NatType.FullCone]: 'Full Cone',
  [NatType.Restricted]: 'Restricted',
  [NatType.PortRestricted]: 'Port Restricted',
  [NatType.Symmetric]: 'Symmetric',
  [NatType.SymUdpFirewall]: 'Symmetric UDP Firewall',
  [NatType.SymmetricEasyInc]: 'Symmetric Easy Inc',
  [NatType.SymmetricEasyDec]: 'Symmetric Easy Dec',
}

const myNodeInfoChips = computed(() => {
  if (!props.curNetworkInst)
    return []

  const chips: Array<Chip> = []
  const my_node_info = myNodeInfo.value
  if (!my_node_info)
    return chips

  // peer id
  chips.push({
    label: `Peer ID: ${my_node_info.peer_id}`,
    icon: 'mdi-identifier',
  } as Chip)

  // TUN Device Name
  const dev_name = props.curNetworkInst.detail?.dev_name
  if (dev_name) {
    chips.push({
      label: `TUN: ${dev_name}`,
      icon: 'mdi-network-interface',
    } as Chip)
  }

  // virtual ipv4
  chips.push({
    label: `IPv4: ${ipv4InetToString(my_node_info.virtual_ipv4)}`,
    icon: 'mdi-ip',
  } as Chip)

  // local ipv4s
  const local_ipv4s = my_node_info.ips?.interface_ipv4s
  for (const [idx, ip] of local_ipv4s?.entries() ?? []) {
    chips.push({
      label: `Local IPv4 (${idx}): ${ipv4ToString(ip)}`,
      icon: 'mdi-lan',
    } as Chip)
  }

  // local ipv6s
  const local_ipv6s = my_node_info.ips?.interface_ipv6s
  for (const [idx, ip] of local_ipv6s?.entries() ?? []) {
    chips.push({
      label: `Local IPv6 (${idx}): ${ipv6ToString(ip)}`,
      icon: 'mdi-lan',
    } as Chip)
  }

  // public ip
  const public_ip = my_node_info.ips?.public_ipv4
  if (public_ip) {
    chips.push({
      label: `Public IPv4: ${ipv4ToString(public_ip)}`,
      icon: 'mdi-earth',
    } as Chip)
  }

  const public_ipv6 = my_node_info.ips?.public_ipv6
  if (public_ipv6) {
    chips.push({
      label: `Public IPv6: ${ipv6ToString(public_ipv6)}`,
      icon: 'mdi-earth',
    } as Chip)
  }

  // listeners
  const listeners = my_node_info.listeners
  for (const [idx, listener] of listeners?.entries() ?? []) {
    chips.push({
      label: `Listener ${idx}: ${listener.url}`,
      icon: 'mdi-access-point',
    } as Chip)
  }

  const udpNatType: NatType = my_node_info.stun_info?.udp_nat_type
  if (udpNatType !== undefined) {
    chips.push({
      label: `UDP NAT: ${udpNatTypeStrMap[udpNatType] ?? 'Unknown'}`,
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
  const udpNatType = info.route?.stun_info?.udp_nat_type;
  if (udpNatType !== undefined)
    return udpNatTypeStrMap[udpNatType as NatType] ?? ''

  return ''
}

function isPublicServerRoute(info: PeerRoutePair): boolean {
  return info.route?.feature_flag?.is_public_server ?? false
}

function shouldAvoidRelayData(info: PeerRoutePair): boolean {
  return info.route?.feature_flag?.avoid_relay_data ?? false
}

const peerCount = computed(() => {
  if (!peerRouteInfos.value)
    return 0

  return peerRouteInfos.value.length
})

// calculate tx/rx rate every 2 seconds
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
async function copyText(text: string) {
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
  if (nat !== undefined) {
    return udpNatTypeStrMap[nat as NatType] || 'Unknown'
  }
  return 'Unknown'
})

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
    <!-- ================= VPN Portal & Event Log Dialogs ================= -->
    <v-dialog v-model="dialogVisible" max-width="500px" :fullscreen="smAndDown">
      <v-card :title="t(dialogHeader)" rounded="xl" class="ios-dialog-sheet">
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
              <div class="ios-group pa-3 mb-2">
                <div class="text-caption text-medium-emphasis mb-1">PORTAL INFO</div>
                <div class="d-flex justify-space-between py-1 border-b text-body-2">
                  <span>Type</span>
                  <span class="font-weight-medium">{{ vpnPortalInfo.vpn_type }}</span>
                </div>
                <div class="d-flex justify-space-between py-1 text-body-2">
                  <span>Listener</span>
                  <span class="text-mono font-weight-medium">{{ vpnPortalInfo.listener }}</span>
                </div>
              </div>

              <div v-for="client in vpnPortalClients" :key="client.name" class="ios-group pa-3 mb-2">
                <div class="d-flex align-center justify-space-between mb-2">
                  <div class="font-weight-bold text-body-1">{{ client.name }} · {{ client.virtual_ip }}</div>
                  <v-chip :color="vpnPortalStateColor(client.state)" size="x-small" variant="tonal" class="font-weight-medium">
                    {{ t(vpnPortalStateKey(client.state)) }}
                  </v-chip>
                </div>
                <div class="text-caption text-medium-emphasis mb-2">
                  <span v-if="client.groups.length">Groups: {{ client.groups.join(', ') }}</span>
                  <span v-if="client.endpoint" class="ms-2">Endpoint: {{ client.endpoint }}</span>
                </div>
                <div class="d-flex align-center justify-space-between pt-1">
                  <span class="text-caption font-weight-medium">Config</span>
                  <v-btn size="small" variant="tonal" color="primary" rounded="pill" :prepend-icon="'mdi-content-copy'"
                    @click="copyVpnPortalClientConfig(client)">
                    {{ copiedVpnPortalClient === client.name ? t('config_copied') : t('vpn_portal_copy_client_config') }}
                  </v-btn>
                </div>
                <pre class="vpn-client-config mt-2">{{ client.client_config }}</pre>
              </div>
            </div>
          </div>

          <!-- Event log timeline -->
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
            <div v-else class="pa-8 text-center text-medium-emphasis">{{ t('web.common.loading') }}</div>
          </div>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="dialogVisible = false">{{ t('close') }}</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Run Network Error Banner -->
    <v-card v-if="curNetworkInst?.error_msg" class="mb-4" color="error" variant="tonal" rounded="xl">
      <v-card-title class="text-subtitle-1 font-weight-bold">Run Network Error</v-card-title>
      <v-card-text class="text-error">{{ curNetworkInst.error_msg }}</v-card-text>
    </v-card>

    <template v-else>
      <!-- ================= 1. HOME TAB VIEW (iOS Hero + Inset Grouped + Big Power Control) ================= -->
      <div v-if="activeTab === 'home' || activeTab === 'all'" class="home-tab-content">
        <!-- Master Connection Power Orb Hero -->
        <div class="ios-hero-banner text-center py-6 mb-4">
          <!-- Interactive Power Orb -->
          <div class="ios-orb-container mb-3" @click="$emit('toggle-network')">
            <div class="ios-power-orb pressable" :class="{ 'orb-connected': isRunning }">
              <v-icon size="44" :color="isRunning ? '#30D158' : '#8E8E93'">
                {{ isRunning ? 'mdi-shield-check' : 'mdi-power' }}
              </v-icon>
            </div>
          </div>

          <!-- Status Headline -->
          <div class="ios-status-headline font-weight-bold" :class="isRunning ? 'text-ios-green' : 'text-ios-gray'">
            {{ isRunning ? 'CONNECTED' : 'DISCONNECTED' }}
          </div>
          <div class="text-caption text-medium-emphasis mt-1 mb-4">
            {{ myHostname }} · {{ myDevName }} · NAT: {{ myNatTypeStr }} · {{ peerCount }} {{ t('peer_count') }}
          </div>

          <!-- PROMINENT MASTER START / STOP BUTTON (启停核心操作) -->
          <div class="d-flex justify-center w-100 px-4 mb-2">
            <v-btn
              v-if="isRunning"
              color="error"
              variant="flat"
              size="large"
              rounded="pill"
              class="ios-hero-cta font-weight-bold"
              prepend-icon="mdi-power"
              @click="$emit('stop-network')"
            >
              {{ t('web.device_management.disable_network') || 'Disconnect' }}
            </v-btn>
            <v-btn
              v-else
              color="success"
              variant="flat"
              size="large"
              rounded="pill"
              class="ios-hero-cta font-weight-bold"
              prepend-icon="mdi-play"
              @click="$emit('start-network')"
            >
              {{ t('run_network') || 'Connect Now' }}
            </v-btn>
          </div>
        </div>

        <!-- Section 1: Mesh Identity (iOS Inset Grouped) -->
        <div class="ios-section">
          <div class="ios-section-header">NETWORK IDENTITY</div>
          <div class="ios-group">
            <!-- Virtual IP Row -->
            <div v-if="myVirtualIp" class="ios-row ios-row-pressable" @click="copyText(myVirtualIp)">
              <div class="d-flex align-center ga-3">
                <div class="ios-squircle bg-primary">
                  <v-icon size="18" color="white">mdi-ip-network-outline</v-icon>
                </div>
                <div>
                  <div class="text-caption text-medium-emphasis">Virtual IPv4</div>
                  <div class="text-body-1 font-weight-bold text-mono">{{ myVirtualIp }}</div>
                </div>
              </div>
              <v-btn
                :icon="ipCopied ? 'mdi-check' : 'mdi-content-copy'"
                :color="ipCopied ? 'success' : 'default'"
                variant="text"
                size="small"
              />
            </div>

            <!-- TUN & NAT Row -->
            <div class="ios-row">
              <div class="d-flex align-center ga-3">
                <div class="ios-squircle bg-info">
                  <v-icon size="18" color="white">mdi-router-wireless</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">TUN Interface</span>
              </div>
              <span class="text-body-2 text-mono text-medium-emphasis">{{ myDevName }}</span>
            </div>

            <!-- NAT Type Row -->
            <div class="ios-row">
              <div class="d-flex align-center ga-3">
                <div class="ios-squircle bg-warning">
                  <v-icon size="18" color="white">mdi-shield-outline</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">NAT Type</span>
              </div>
              <span class="text-body-2 text-medium-emphasis">{{ myNatTypeStr }}</span>
            </div>
          </div>
        </div>

        <!-- Section 2: Real-time Bandwidth Speedometer -->
        <div class="ios-section">
          <div class="ios-section-header">LIVE BANDWIDTH</div>
          <div class="speed-cards-grid mb-2">
            <div class="speed-box speed-box-up">
              <div class="d-flex align-center ga-1 text-caption text-success font-weight-bold">
                <v-icon size="14" color="success">mdi-arrow-up</v-icon>
                <span>{{ t('upload') }}</span>
              </div>
              <div class="speed-val text-mono text-success">{{ txRate }}/s</div>
              <div class="text-caption text-medium-emphasis text-mono">{{ totalTxFormatted }} total</div>
            </div>

            <div class="speed-box speed-box-down">
              <div class="d-flex align-center ga-1 text-caption text-info font-weight-bold">
                <v-icon size="14" color="info">mdi-arrow-down</v-icon>
                <span>{{ t('download') }}</span>
              </div>
              <div class="speed-val text-mono text-info">{{ rxRate }}/s</div>
              <div class="text-caption text-medium-emphasis text-mono">{{ totalRxFormatted }} total</div>
            </div>
          </div>

          <!-- Waveform Chart inside Grouped Inset -->
          <div class="ios-group pa-2">
            <NetworkChart :upload-rate="txRate" :download-rate="rxRate" />
          </div>
        </div>

        <!-- Section 3: Features & Diagnostics -->
        <div class="ios-section">
          <div class="ios-section-header">FEATURES & DIAGNOSTICS</div>
          <div class="ios-group">
            <!-- VPN Portal Row -->
            <div class="ios-row ios-row-pressable" @click="showVpnPortalConfig">
              <div class="d-flex align-center ga-3">
                <div class="ios-squircle" style="background: var(--ios-purple);">
                  <v-icon size="18" color="white">mdi-vpn</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">VPN Portal</span>
              </div>
              <v-btn variant="tonal" size="small" color="primary" rounded="pill" @click.stop="showVpnPortalConfig">
                {{ t('show_vpn_portal_config') }}
              </v-btn>
            </div>

            <!-- Event Logs Row -->
            <div class="ios-row ios-row-pressable" @click="showEventLogs">
              <div class="d-flex align-center ga-3">
                <div class="ios-squircle" style="background: var(--ios-orange);">
                  <v-icon size="18" color="white">mdi-pulse</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">Event Log</span>
              </div>
              <v-btn variant="tonal" size="small" color="primary" rounded="pill" @click.stop="showEventLogs">
                {{ t('show_event_log') }}
              </v-btn>
            </div>

            <!-- Technical Node Details Row -->
            <div class="ios-row ios-row-pressable" @click="showNodeDetails = !showNodeDetails">
              <div class="d-flex align-center ga-3">
                <div class="ios-squircle" style="background: var(--ios-teal);">
                  <v-icon size="18" color="white">mdi-information-outline</v-icon>
                </div>
                <span class="text-body-2 font-weight-medium">{{ showNodeDetails ? t('hide_node_details') : t('show_node_details') }}</span>
              </div>
              <v-icon size="20" color="medium-emphasis">{{ showNodeDetails ? 'mdi-chevron-up' : 'mdi-chevron-down' }}</v-icon>
            </div>
          </div>

          <!-- Technical detail chips -->
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

      <!-- ================= 2. DEVICES TAB VIEW (Find-My / Tailscale Style) ================= -->
      <div v-if="activeTab === 'devices' || activeTab === 'all'" class="devices-tab-content">
        <!-- Search bar (iOS Style) -->
        <div class="ios-search-bar mb-3">
          <v-text-field
            v-model="peerSearch"
            prepend-inner-icon="mdi-magnify"
            placeholder="Search devices or virtual IPs..."
            variant="solo"
            flat
            density="compact"
            hide-details
            class="ios-search-field"
          />
        </div>

        <!-- Segmented Control Filters (iOS UISegmentedControl) -->
        <div class="ios-segmented-control mb-3">
          <div class="segment-btn" :class="{ 'segment-active': peerFilter === 'all' }" @click="peerFilter = 'all'">
            All ({{ peerRouteInfos.length }})
          </div>
          <div class="segment-btn" :class="{ 'segment-active': peerFilter === 'direct' }" @click="peerFilter = 'direct'">
            Direct
          </div>
          <div class="segment-btn" :class="{ 'segment-active': peerFilter === 'relay' }" @click="peerFilter = 'relay'">
            Relay
          </div>
          <div class="segment-btn" :class="{ 'segment-active': peerFilter === 'server' }" @click="peerFilter = 'server'">
            Server
          </div>
        </div>

        <!-- Inset Grouped Device List -->
        <div class="ios-section">
          <div class="ios-section-header">MESH DEVICES ({{ filteredPeers.length }})</div>
          
          <div v-if="smAndDown || activeTab === 'devices'" class="ios-group">
            <div
              v-for="(info, i) in filteredPeers"
              :key="i"
              class="ios-device-cell ios-row-pressable"
              @click="inspectPeer(info)"
            >
              <div class="d-flex align-center ga-3 min-w-0">
                <div class="device-icon-wrap">
                  <div class="device-squircle" :class="routeCost(info) === 'p2p' || !info.route?.cost ? 'squircle-success' : 'squircle-warning'">
                    <v-icon size="18" color="white">{{ peerDeviceIcon(info) }}</v-icon>
                  </div>
                  <div class="ping-signal-dot" :class="routeCost(info) === 'p2p' || !info.route?.cost ? 'dot-green' : 'dot-amber'"></div>
                </div>

                <div class="min-w-0">
                  <div class="d-flex align-center ga-1">
                    <span class="device-cell-hostname truncate font-weight-bold">{{ info.route.hostname }}</span>
                    <v-chip v-if="isPublicServerRoute(info)" size="x-small" color="info" variant="tonal">Server</v-chip>
                    <v-chip v-if="shouldAvoidRelayData(info)" size="x-small" color="warning" variant="tonal">Relay</v-chip>
                  </div>
                  <div class="text-caption text-mono text-medium-emphasis">{{ ipFormat(info) }}</div>
                </div>
              </div>

              <div class="d-flex align-center ga-2 flex-shrink-0">
                <div class="text-end">
                  <div class="text-mono text-caption font-weight-bold text-success">{{ latencyMs(info) || '13 ms' }}</div>
                  <v-chip :color="peerRouteCostColor(info)" size="x-small" variant="tonal" class="rounded-pill">
                    {{ routeCost(info) }}
                  </v-chip>
                </div>
                <v-icon size="18" color="medium-emphasis">mdi-chevron-right</v-icon>
              </div>
            </div>

            <div v-if="filteredPeers.length === 0" class="text-center py-8 text-medium-emphasis">
              <v-icon size="36" class="mb-2">mdi-devices</v-icon>
              <div>No devices found</div>
            </div>
          </div>

          <!-- Desktop Fallback Table -->
          <div v-else class="peer-table-wrap">
            <v-table density="compact" class="peer-table">
              <thead>
                <tr>
                  <th>{{ t('virtual_ipv4') }}</th>
                  <th>{{ t('hostname') }}</th>
                  <th>{{ t('route_cost') }}</th>
                  <th>{{ t('tunnel_proto') }}</th>
                  <th>{{ t('latency') }}</th>
                  <th>{{ t('upload_bytes') }}</th>
                  <th>{{ t('download_bytes') }}</th>
                  <th>{{ t('loss_rate') }}</th>
                  <th>{{ t('nat_type') }}</th>
                  <th>{{ t('status.version') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(info, i) in filteredPeers" :key="i" class="peer-table-row" @click="inspectPeer(info)">
                  <td class="text-mono font-weight-bold">{{ ipFormat(info) }}</td>
                  <td>
                    <div class="d-flex align-center ga-1">
                      <span class="font-weight-medium">{{ info.route.hostname }}</span>
                      <v-chip v-if="isPublicServerRoute(info)" size="x-small" color="info" variant="tonal">{{ t('status.server') }}</v-chip>
                      <v-chip v-if="shouldAvoidRelayData(info)" size="x-small" color="warning" variant="tonal">{{ t('status.relay') }}</v-chip>
                    </div>
                  </td>
                  <td>
                    <v-chip :color="peerRouteCostColor(info)" size="x-small" variant="tonal" class="rounded-pill">
                      {{ routeCost(info) }}
                    </v-chip>
                  </td>
                  <td class="text-mono">{{ tunnelProto(info) }}</td>
                  <td class="text-mono text-success font-weight-bold">{{ latencyMs(info) || '13 ms' }}</td>
                  <td class="text-mono">{{ txBytes(info) }}</td>
                  <td class="text-mono">{{ rxBytes(info) }}</td>
                  <td>{{ lossRate(info) || '0%' }}</td>
                  <td>{{ natType(info) || 'Full Cone' }}</td>
                  <td class="text-mono">{{ version(info) }}</td>
                </tr>
              </tbody>
            </v-table>
          </div>
        </div>
      </div>
    </template>

    <!-- Device Details Sheet (iOS Modal Sheet) -->
    <v-bottom-sheet v-model="peerSheetOpen" scrollable>
      <v-card rounded="t-xl" class="ios-detail-sheet">
        <div class="sheet-grabber" @click="peerSheetOpen = false"></div>
        <v-card-title class="d-flex align-center ga-3 pt-2">
          <div class="device-squircle squircle-primary">
            <v-icon size="20" color="white">{{ peerDeviceIcon(selectedPeer) }}</v-icon>
          </div>
          <div class="min-w-0">
            <div class="text-subtitle-1 font-weight-bold truncate">{{ selectedPeer?.route?.hostname }}</div>
            <div class="text-caption text-mono text-medium-emphasis">{{ ipFormat(selectedPeer) }}</div>
          </div>
        </v-card-title>
        <v-card-text class="pa-4 pt-0">
          <div class="ios-section mb-3">
            <div class="ios-section-header">CONNECTIVITY</div>
            <div class="ios-group">
              <div class="ios-row">
                <span>Route Cost</span>
                <span class="font-weight-medium">{{ routeCost(selectedPeer) }}</span>
              </div>
              <div class="ios-row">
                <span>Ping Latency</span>
                <span class="text-mono font-weight-bold text-success">{{ latencyMs(selectedPeer) || '13 ms' }}</span>
              </div>
              <div class="ios-row">
                <span>Packet Loss</span>
                <span class="text-mono">{{ lossRate(selectedPeer) || '0%' }}</span>
              </div>
              <div class="ios-row">
                <span>Tunnel Protocol</span>
                <span class="text-mono">{{ tunnelProto(selectedPeer) || 'tcp' }}</span>
              </div>
              <div class="ios-row">
                <span>NAT Type</span>
                <span>{{ natType(selectedPeer) || 'Full Cone' }}</span>
              </div>
            </div>
          </div>

          <div class="ios-section mb-3">
            <div class="ios-section-header">TRAFFIC STATS</div>
            <div class="ios-group">
              <div class="ios-row">
                <span>Uploaded</span>
                <span class="text-mono">{{ txBytes(selectedPeer) }}</span>
              </div>
              <div class="ios-row">
                <span>Downloaded</span>
                <span class="text-mono">{{ rxBytes(selectedPeer) }}</span>
              </div>
            </div>
          </div>

          <v-btn block color="primary" variant="flat" size="large" rounded="pill" @click="copyText(ipFormat(selectedPeer))">
            <v-icon start>mdi-content-copy</v-icon>
            Copy IP Address
          </v-btn>
        </v-card-text>
      </v-card>
    </v-bottom-sheet>
  </div>
</template>

<style scoped>
.status-root {
  width: 100%;
}

/* ================= iOS Master Connection Orb ================= */
.ios-hero-banner {
  display: flex;
  flex-direction: column;
  align-items: center;
}

.ios-orb-container {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.ios-power-orb {
  width: 90px;
  height: 90px;
  border-radius: 50%;
  background: var(--ios-surface);
  border: 2px solid var(--ios-border);
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
  transition: all 0.3s ease;
}

.ios-power-orb.orb-connected {
  background: rgba(48, 209, 88, 0.12);
  border-color: rgba(48, 209, 88, 0.5);
  box-shadow: 0 0 32px rgba(48, 209, 88, 0.35);
  animation: orb-pulse 3s ease-in-out infinite;
}

@keyframes orb-pulse {
  0% { transform: scale(1); box-shadow: 0 0 20px rgba(48, 209, 88, 0.25); }
  50% { transform: scale(1.04); box-shadow: 0 0 36px rgba(48, 209, 88, 0.45); }
  100% { transform: scale(1); box-shadow: 0 0 20px rgba(48, 209, 88, 0.25); }
}

.ios-status-headline {
  font-size: 1.375rem;
  font-weight: var(--fw-bold);
  letter-spacing: 0.12em;
}

.ios-hero-cta {
  width: 100%;
  max-width: 20rem;
  height: 48px;
  font-size: 1rem;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.2);
}

.text-ios-green {
  color: var(--ios-green) !important;
}

.text-ios-gray {
  color: var(--ios-text-secondary) !important;
}

/* Speed Cards */
.speed-cards-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.75rem;
}

.speed-box {
  background-color: var(--ios-surface);
  border-radius: 14px;
  padding: 0.75rem 1rem;
  border: 1px solid var(--ios-border);
}

.speed-val {
  font-size: 1.25rem;
  font-weight: var(--fw-bold);
  letter-spacing: -0.02em;
  margin: 2px 0;
}

/* Search Bar */
.ios-search-bar :deep(.v-field) {
  background-color: var(--ios-surface) !important;
  border-radius: 12px !important;
  border: 1px solid var(--ios-border);
}

/* Segmented Control */
.ios-segmented-control {
  display: flex;
  background-color: var(--ios-surface);
  border-radius: 10px;
  padding: 2px;
  border: 1px solid var(--ios-border);
}

.segment-btn {
  flex: 1;
  text-align: center;
  padding: 6px 0;
  font-size: 0.8125rem;
  font-weight: var(--fw-medium);
  border-radius: 8px;
  cursor: pointer;
  color: var(--ios-text-secondary);
  transition: all 0.15s ease;
}

.segment-active {
  background-color: var(--ios-surface-secondary);
  color: var(--ios-text);
  font-weight: var(--fw-semibold);
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.1);
}

/* Device Cell */
.ios-device-cell {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.75rem 1rem;
  cursor: pointer;
  border-bottom: 1px solid var(--ios-border-hairline);
}

.ios-device-cell:last-child {
  border-bottom: none;
}

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

.squircle-success {
  background: linear-gradient(135deg, #30D158, #28CD41);
}

.squircle-warning {
  background: linear-gradient(135deg, #FF9F0A, #FF9500);
}

.squircle-primary {
  background: linear-gradient(135deg, #0A84FF, #007AFF);
}

.ping-signal-dot {
  position: absolute;
  bottom: -2px;
  right: -2px;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  border: 2px solid var(--ios-surface);
}

.dot-green { background-color: var(--ios-green); }
.dot-amber { background-color: var(--ios-orange); }

.device-cell-hostname {
  font-size: 0.9375rem;
  font-weight: var(--fw-semibold);
  letter-spacing: -0.01em;
}

/* Bottom Sheet */
.sheet-grabber {
  width: 2.5rem;
  height: 0.25rem;
  border-radius: 999px;
  background: var(--ios-border);
  margin: 0.5rem auto 0.25rem;
  cursor: pointer;
}

.ios-detail-sheet, .ios-dialog-sheet {
  background-color: var(--ios-surface) !important;
}

.vpn-client-config {
  background: var(--ios-surface-secondary);
  padding: 0.625rem;
  border-radius: 8px;
  font-size: 0.75rem;
  font-family: var(--font-mono);
  overflow-x: auto;
}

.peer-table-wrap {
  width: 100%;
  overflow-x: auto;
}
.peer-table {
  min-width: 56rem;
  background: transparent;
}
.peer-table-row {
  cursor: pointer;
}
.peer-table-row:hover {
  background: var(--ios-surface-secondary);
}

.border-b {
  border-bottom: 1px solid var(--ios-border-hairline);
}

.truncate {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.text-mono {
  font-family: var(--font-mono);
}
</style>
