<script setup lang="ts">
import { writeText } from '@tauri-apps/plugin-clipboard-manager'
import { useId } from 'vue'
import { collectNetworkInfo } from '~/composables/backend'
import { usePhoneText } from '~/composables/hero_text'
import { mobileStats } from '~/composables/mobile_vpn'

const props = defineProps<{
  /** RPC client reachable (backend alive). Drives retry vs start semantics. */
  clientRunning: boolean
  /** Currently selected network instance id (state machine lives in index.vue). */
  instanceId?: string
  /** A connect/disconnect round-trip is in flight. */
  busy?: boolean
  /** Transition state: 'idle' | 'connecting' | 'disconnecting' */
  desired?: 'idle' | 'connecting' | 'disconnecting'
  /** First isClientRunning() probe has resolved (prevents boot-time flash). */
  booted?: boolean
  isAndroid?: boolean
  /** System notifications blocked -> shows the tap-to-fix warning card. */
  notifBlocked?: boolean
}>()

const emit = defineEmits<{
  (e: 'connect'): void
  (e: 'disconnect'): void
  (e: 'grant'): void
  (e: 'retry'): void
  (e: 'create'): void
  (e: 'openNotifSettings'): void
}>()

const { pt } = usePhoneText()
const { t } = useI18n()
const uid = useId().replace(/[^\w-]/g, '')

const ipCopied = ref(false)
async function copyIp() {
  if (!mobileStats.virtualIp)
    return
  try {
    await writeText(mobileStats.virtualIp)
    ipCopied.value = true
    setTimeout(() => {
      ipCopied.value = false
    }, 1800)
  }
  catch {
    // ignore
  }
}

// ---- derived state -------------------------------------------------------
const running = computed(() => mobileStats.connected)
const skeleton = computed(() => !props.booted || (props.clientRunning && !mobileStats.ready))
const notFound = computed(() => !props.clientRunning)

// a denied VPN permission outranks the live hero: the instance may look
// "connected" over RPC while no tunnel actually carries traffic
const permissionState = computed(() => !!props.isAndroid && mobileStats.permissionDenied)
const failedState = computed(() =>
  !running.value && !notFound.value && !!mobileStats.lastError,
)
// client is up but nothing is running yet — the classic "未运行" empty state
const stoppedState = computed(() => !running.value && !notFound.value && !permissionState.value && !failedState.value)
const stoppedStateNoConfig = computed(() => stoppedState.value && !props.instanceId)
const emptyState = computed(() => notFound.value || permissionState.value || failedState.value || stoppedState.value)

const isConnecting = computed(() => props.desired === 'connecting')
const isDisconnecting = computed(() => props.desired === 'disconnecting')
const isTransitioning = computed(() => isConnecting.value || isDisconnecting.value)

const title = computed(() => {
  if (notFound.value)
    return t('client.not_running')
  if (permissionState.value)
    return pt('hero.permission_title', '需要 VPN 权限', 'VPN permission required')
  if (failedState.value)
    return pt('hero.failed_title', '连接失败', 'Connection failed')
  if (isConnecting.value)
    return pt('hero.connecting_title', '正在建立隧道…', 'Establishing tunnel…')
  if (isDisconnecting.value)
    return pt('hero.disconnecting_title', '正在断开连接…', 'Disconnecting…')
  if (stoppedState.value)
    return pt('hero.stopped_title', '网络未运行', 'Network is stopped')
  return mobileStats.networkName || 'EasyTier'
})

const subtitle = computed(() => {
  if (notFound.value)
    return pt('hero.notfound_sub', '无法连接本地服务，点重试重新接入。', 'The local service is unreachable. Tap retry to reconnect.')
  if (permissionState.value)
    return pt('hero.permission_sub', 'Android 需要授权后才能建立 VPN 通道，重试并在系统弹窗中点“允许”。', 'Android needs your approval before the tunnel can start. Tap retry and allow the system prompt.')
  if (failedState.value)
    return mobileStats.lastError
  if (isConnecting.value)
    return pt('hero.connecting_sub', '正在与节点建立安全隧道，请稍候…', 'Establishing secure tunnel with peers, please wait…')
  if (isDisconnecting.value)
    return pt('hero.disconnecting_sub', '正在断开虚拟网络连接…', 'Closing virtual network tunnel…')
  if (stoppedState.value) {
    return props.instanceId
      ? pt('hero.stopped_sub', '配置已就绪，点“连接”即可接入组网。', 'Your config is ready. Tap Connect to join the mesh.')
      : pt('hero.noconfig_sub', '还没有网络配置——点击下方按钮即可快速创建。', 'No network config yet — tap below to create one quickly.')
  }
  return ''
})

// ---- state as colour + shape + text (v2 Signal contract) ------------------
// up = connected (circle) · sync = connecting (square, breathing) ·
// degraded = needs attention (triangle) · down = failed (bar) · idle = not started (ring)
type SignalState = 'up' | 'sync' | 'degraded' | 'down' | 'idle'

const signalState = computed<SignalState>(() => {
  if (isTransitioning.value)
    return 'sync'
  if (running.value)
    return 'up'
  if (permissionState.value)
    return 'degraded'
  if (notFound.value || failedState.value)
    return 'down'
  return 'idle'
})

const signalText = computed(() => {
  if (isConnecting.value)
    return pt('hero.connecting_pill', '建立中…', 'Connecting…')
  if (isDisconnecting.value)
    return pt('hero.disconnecting_pill', '断开中…', 'Disconnecting…')
  if (running.value)
    return t('status.connected')
  if (permissionState.value)
    return pt('hero.permission_pill', '待授权', 'Permission needed')
  if (notFound.value)
    return t('client.not_running')
  if (failedState.value)
    return pt('hero.failed_pill', '已断开', 'Disconnected')
  return pt('hero.stopped_pill', '未启动', 'Not started')
})

// the orb mirrors the signal with the same colour, one size up
const orbTone = computed(() => `is-${signalState.value}`)
const orbLabel = computed(() => pt('hero.orb_label', `连接状态：${signalText.value}`, `Connection status: ${signalText.value}`))
const orbIcon = computed(() => {
  if (signalState.value === 'up')
    return 'mdi-check'
  if (signalState.value === 'degraded')
    return 'mdi-shield-key-outline'
  if (signalState.value === 'down')
    return notFound.value ? 'mdi-server-network-off' : 'mdi-lan-disconnect'
  return 'mdi-power'
})

// ---- rates ---------------------------------------------------------------
const RX_UNITS = ['B/s', 'KB/s', 'MB/s', 'GB/s']

function fmtRate(bps: number): string {
  if (!Number.isFinite(bps) || bps <= 0)
    return `0 ${RX_UNITS[0]}`
  let v = bps
  let i = 0
  while (v >= 1000 && i < RX_UNITS.length - 1) {
    v /= 1000
    i += 1
  }
  return `${v >= 100 ? Math.round(v) : v.toFixed(1)} ${RX_UNITS[i]}`
}

const rxText = computed(() => fmtRate(mobileStats.rxRate))
const txText = computed(() => fmtRate(mobileStats.txRate))

// ---- sparkline (hand-rolled, dependency-free) -----------------------------
const SPARK_W = 240
const SPARK_H = 64
const SPARK_PAD = 4

function linePoints(scale: (p: { rx: number, tx: number }) => number): string {
  const h = mobileStats.history
  const max = Math.max(1024, ...h.map(p => Math.max(p.rx, p.tx)))
  const n = h.length
  return h
    .map((p, i) => {
      const x = n === 1 ? SPARK_W : (i / (n - 1)) * SPARK_W
      const y = SPARK_H - SPARK_PAD - Math.min(1, scale(p) / max) * (SPARK_H - 2 * SPARK_PAD)
      return `${x.toFixed(1)},${y.toFixed(1)}`
    })
    .join(' ')
}

const rxLine = computed(() => linePoints(p => p.rx))
const txLine = computed(() => linePoints(p => p.tx))
const hasSpark = computed(() => mobileStats.history.length >= 2)
const sparkEmpty = computed(() =>
  mobileStats.history.every(p => p.rx < 1 && p.tx < 1),
)

function areaOf(line: string): string {
  return `0,${SPARK_H} ${line} ${SPARK_W},${SPARK_H}`
}
const rxArea = computed(() => areaOf(rxLine.value))
const txArea = computed(() => areaOf(txLine.value))

// ---- peer rows + the single primary number --------------------------------
// mobileStats carries rates/counts but no latency, so the hero reads the same
// collectNetworkInfo payload the ticker uses (read-only; the composables stay
// untouched). Latency is the home screen's one primary number.
interface HeroPeer {
  key: string
  ip: string
  hostname: string
  latencyMs?: number
  path: 'direct' | 'relay' | 'public'
  online: boolean
  offlineSince?: number
}

const PEER_POLL_MS = 2000
/** an offline peer stays visible for this long before it is forgotten */
const OFFLINE_MEMORY_MS = 6 * 60 * 60 * 1000
const PEER_ROWS_MAX = 6
const RTT_GOOD_MS = 80
const RTT_MID_MS = 200

const peerRows = ref<HeroPeer[]>([])
const peerSampleOk = ref(false)
const offlineMemory = new Map<string, HeroPeer>()
const lastOnlineAt = new Map<string, number>()

function numeric(value: unknown): number | undefined {
  if (typeof value === 'number')
    return Number.isFinite(value) ? value : undefined
  if (typeof value !== 'string' || value.trim() === '')
    return undefined
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : undefined
}

function ipOf(route: any): string {
  const addr = route?.ipv4_addr
  if (typeof addr === 'string')
    return addr
  const raw = addr?.address?.addr ?? addr?.addr
  const n = numeric(raw)
  if (n === undefined)
    return ''
  return [24, 16, 8, 0].map(shift => (n >>> shift) & 255).join('.')
}

function readSample(info: any): HeroPeer[] {
  const pairs = Array.isArray(info?.peer_route_pairs) ? info.peer_route_pairs : []
  const rows: HeroPeer[] = []
  for (const pair of pairs) {
    const route = pair?.route ?? {}
    const peer = pair?.peer ?? {}
    const conns: any[] = Array.isArray(peer?.conns) ? peer.conns : []
    const openConns = conns.filter(c => !(c?.is_closed ?? c?.isClosed))
    let latencyUs: number | undefined
    for (const conn of openConns) {
      const value = numeric(conn?.stats?.latency_us)
      if (value !== undefined)
        latencyUs = Math.min(latencyUs ?? value, value)
    }
    const cost = numeric(route?.cost)
    const nextHop = numeric(route?.next_hop_peer_id)
    const peerId = numeric(route?.peer_id)
    const isPublic = !!route?.feature_flag?.is_public_server
    // direct when the route points at the peer itself (cost 1 / next hop == peer)
    const direct = cost !== undefined ? cost <= 1 : (nextHop !== undefined && nextHop === peerId)
    const ip = ipOf(route)
    const hostname = String(route?.hostname ?? '')
    const key = `p${peerId ?? (ip || hostname || rows.length)}`
    // a route we still hold without any live conn is either relayed (reached
    // through the next hop, no direct conn) or actually gone
    const online = openConns.length > 0 || (conns.length === 0 && !direct)
    rows.push({
      key,
      ip,
      hostname,
      latencyMs: latencyUs === undefined ? undefined : Math.ceil(latencyUs / 100) / 10,
      path: isPublic ? 'public' : (direct ? 'direct' : 'relay'),
      online,
    })
  }
  return rows
}

function mergeSample(rows: HeroPeer[], now: number) {
  const seen = new Set<string>()
  for (const row of rows) {
    seen.add(row.key)
    if (row.online) {
      lastOnlineAt.set(row.key, now)
      offlineMemory.delete(row.key)
      continue
    }
    if (!offlineMemory.has(row.key)) {
      // first offline sighting: count from the last time it answered
      offlineMemory.set(row.key, { ...row, offlineSince: lastOnlineAt.get(row.key) ?? now })
    }
  }
  for (const [key, entry] of offlineMemory) {
    const offlineFor = now - (entry.offlineSince ?? now)
    // a peer that answered again was already dropped above; one that never
    // came back is forgotten after OFFLINE_MEMORY_MS so the summary cannot
    // grow without bound
    if (offlineFor > OFFLINE_MEMORY_MS)
      offlineMemory.delete(key)
  }
  const offline = [...offlineMemory.values()]
    .filter(entry => !seen.has(entry.key))
    .sort((a, b) => (b.offlineSince ?? 0) - (a.offlineSince ?? 0))
  const online = rows
    .filter(row => row.online)
    .sort((a, b) => (a.latencyMs ?? Number.POSITIVE_INFINITY) - (b.latencyMs ?? Number.POSITIVE_INFINITY))
  peerRows.value = [...online, ...offline]
}

let peerTimer: ReturnType<typeof setTimeout> | null = null
let peerPolling = false

async function pollPeers() {
  if (peerPolling)
    return
  const targetId = props.instanceId || mobileStats.instanceId
  if (!running.value || !targetId) {
    peerRows.value = []
    peerSampleOk.value = running.value && !targetId
    offlineMemory.clear()
    return
  }
  peerPolling = true
  try {
    const info = (await collectNetworkInfo(targetId))?.info?.map?.[targetId]
    if (info) {
      mergeSample(readSample(info), Date.now())
      peerSampleOk.value = true
    }
  }
  catch {
    // leave the previous sample on screen; the signal already reports the link
  }
  finally {
    peerPolling = false
  }
}

function schedulePeerPoll() {
  if (peerTimer)
    clearTimeout(peerTimer)
  peerTimer = setTimeout(async () => {
    peerTimer = null
    if (typeof document !== 'undefined' && document.hidden) {
      schedulePeerPoll()
      return
    }
    await pollPeers()
    schedulePeerPoll()
  }, PEER_POLL_MS)
}

watch([running, () => props.instanceId, () => mobileStats.instanceId], () => {
  void pollPeers()
})

onMounted(() => {
  schedulePeerPoll()
})

onUnmounted(() => {
  if (peerTimer) {
    clearTimeout(peerTimer)
    peerTimer = null
  }
})

const onlinePeerCount = computed(() => {
  if (!peerSampleOk.value)
    return running.value ? mobileStats.peerCount : 0
  return peerRows.value.filter(row => row.online).length
})
const directPeerCount = computed(() => peerRows.value.filter(row => row.online && row.path === 'direct').length)
const visiblePeerRows = computed(() => peerRows.value.slice(0, PEER_ROWS_MAX))
const hiddenPeerCount = computed(() => Math.max(0, peerRows.value.length - PEER_ROWS_MAX))
const waitingPeers = computed(() => running.value && peerRows.value.length === 0)

// the one primary number: the best (lowest) latency across live peers
const bestLatencyMs = computed(() => {
  const values = peerRows.value
    .filter(row => row.online && row.latencyMs !== undefined)
    .map(row => row.latencyMs as number)
  return values.length ? Math.min(...values) : undefined
})
const latencyText = computed(() =>
  bestLatencyMs.value === undefined ? '—' : bestLatencyMs.value.toFixed(1),
)
const focusCaption = computed(() => {
  if (isConnecting.value)
    return pt('hero.metric_connecting', '正在测量到节点的延迟…', 'Measuring latency to peers…')
  if (bestLatencyMs.value === undefined)
    return pt('hero.metric_none', '还没有可测量的节点', 'No peer to measure yet')
  return pt(
    'hero.metric_caption',
    `${onlinePeerCount.value} 个节点在线 · ${directPeerCount.value} 条直连`,
    `${onlinePeerCount.value} nodes online · ${directPeerCount.value} direct`,
  )
})

function pathLabel(row: HeroPeer): string {
  if (row.path === 'public')
    return pt('hero.path_public', '公网', 'Public')
  if (row.path === 'relay')
    return pt('hero.path_relay', '中继', 'Relay')
  return pt('hero.path_direct', '直连', 'Direct')
}

function rttText(row: HeroPeer): string {
  return row.latencyMs === undefined ? '—' : row.latencyMs.toFixed(1)
}

function rttTone(row: HeroPeer): string {
  if (row.latencyMs === undefined)
    return ''
  if (row.latencyMs <= RTT_GOOD_MS)
    return 'is-good'
  if (row.latencyMs <= RTT_MID_MS)
    return 'is-mid'
  return 'is-bad'
}

function offlineLabel(row: HeroPeer): string {
  const offlineFor = Math.max(0, Date.now() - (row.offlineSince ?? Date.now()))
  const minutes = Math.floor(offlineFor / 60000)
  if (minutes < 1)
    return pt('hero.peer_offline_just', '离线 刚刚', 'Offline just now')
  if (minutes < 60)
    return pt('hero.peer_offline_min', `离线 ${minutes}m`, `Offline ${minutes}m`)
  const hours = Math.floor(minutes / 60)
  if (hours < 24)
    return pt('hero.peer_offline_hour', `离线 ${hours}h`, `Offline ${hours}h`)
  return pt('hero.peer_offline_day', `离线 ${Math.floor(hours / 24)}d`, `Offline ${Math.floor(hours / 24)}d`)
}

// ---- main action -----------------------------------------------------------
const actionIsDisconnect = computed(() => running.value)
const actionLabel = computed(() => {
  if (notFound.value)
    return t('client.retry')
  if (permissionState.value)
    return pt('hero.action_grant', '重新授权', 'Grant permission')
  if (isConnecting.value)
    return pt('hero.action_connecting', '正在连接…', 'Connecting…')
  if (isDisconnecting.value)
    return pt('hero.action_disconnecting', '正在断开…', 'Disconnecting…')
  if (actionIsDisconnect.value)
    return t('status.disconnect')
  if (stoppedStateNoConfig.value)
    return pt('hero.action_create', '创建网络', 'Create Network')
  return pt('hero.action_connect', '连接', 'Connect')
})

const ctaBusy = computed(() => !!props.busy || isTransitioning.value)
const ctaIcon = computed(() => {
  if (notFound.value)
    return 'mdi-replay'
  if (permissionState.value)
    return 'mdi-shield-key-outline'
  if (actionIsDisconnect.value)
    return 'mdi-lan-disconnect'
  if (stoppedStateNoConfig.value)
    return 'mdi-plus'
  return 'mdi-lan-connect'
})

function onAction() {
  // disabled while a round-trip is in flight, so a second tap cannot re-enter
  if (ctaBusy.value)
    return
  if (notFound.value) {
    emit('retry')
    return
  }
  if (permissionState.value) {
    emit('grant')
    return
  }
  if (actionIsDisconnect.value) {
    emit('disconnect')
    return
  }
  if (stoppedStateNoConfig.value) {
    emit('create')
    return
  }
  emit('connect')
}
</script>

<template>
  <section class="et-hero" :aria-busy="skeleton">
    <!-- ============ skeleton: first collectNetworkInfo round-trip ============ -->
    <template v-if="skeleton">
      <div class="et-hero-card">
        <div class="et-skeleton" style="width: 44%; height: 26px; border-radius: 8px" />
        <div class="et-skeleton mt-3" style="width: 62%; height: 14px; border-radius: 7px" />
        <div class="et-skeleton mt-5" style="width: 100%; height: 64px; border-radius: var(--et-radius-sm)" />
      </div>
      <div class="et-hero-card">
        <div class="et-skeleton" style="width: 100%; height: 56px; border-radius: var(--et-radius-pill)" />
      </div>
    </template>

    <template v-else>
      <!-- ========================= empty / error states ======================== -->
      <div v-if="emptyState" class="et-hero-card">
        <div class="et-hero-empty" role="status" aria-live="polite">
          <div class="et-orb" :class="orbTone" role="img" :aria-label="orbLabel">
            <div class="et-orb-core">
              <v-progress-circular
                v-if="isTransitioning"
                indeterminate
                size="32"
                width="3"
              />
              <v-icon v-else size="34" aria-hidden="true">
                {{ orbIcon }}
              </v-icon>
            </div>
          </div>
          <div class="et-hero-empty-title">
            {{ title }}
          </div>
          <div class="et-hero-empty-sub" :class="{ 'et-selectable': failedState }">
            {{ subtitle }}
          </div>
        </div>
      </div>

      <!-- ============================== live hero ============================== -->
      <template v-else>
        <!-- identity: network name + virtual IP + the signal (colour/shape/text) -->
        <div class="et-hero-card et-hero-head">
          <div class="et-hero-id">
            <div class="et-hero-name truncate">
              {{ mobileStats.networkName || 'EasyTier' }}
            </div>
            <button
              type="button"
              class="et-hero-ip mono d-flex align-center ga-1"
              :class="{ 'is-live': running, 'is-copyable': running && !!mobileStats.virtualIp }"
              :aria-label="t('status.copy_ip')"
              :disabled="!running || !mobileStats.virtualIp"
              @click.stop="copyIp()"
            >
              <span>{{ mobileStats.virtualIp || '—.—.—.—' }}</span>
              <v-icon v-if="running && mobileStats.virtualIp" size="14" :color="ipCopied ? 'success' : 'medium-emphasis'" aria-hidden="true">
                {{ ipCopied ? 'mdi-check' : 'mdi-content-copy' }}
              </v-icon>
            </button>
          </div>
          <span class="et-signal" :class="`sig-${signalState}`" role="status" aria-live="polite">
            <span class="et-signal-glyph" aria-hidden="true" />
            <span>{{ signalText }}</span>
          </span>
        </div>

        <!-- the one number this screen answers with: latency to the mesh -->
        <div class="et-hero-focus">
          <div class="et-orb" :class="orbTone" role="img" :aria-label="orbLabel">
            <div class="et-orb-core">
              <v-progress-circular
                v-if="isTransitioning"
                indeterminate
                size="32"
                width="3"
              />
              <v-icon v-else size="34" aria-hidden="true">
                {{ orbIcon }}
              </v-icon>
            </div>
          </div>
          <div class="et-hero-metric">
            <span class="et-hero-metric-value mono">{{ latencyText }}</span>
            <span class="et-hero-metric-unit mono">ms</span>
          </div>
          <div class="et-hero-metric-caption">
            {{ focusCaption }}
          </div>
        </div>

        <!-- traffic: both directions, mono + tabular-nums, 60s trend -->
        <div class="et-hero-card">
          <div class="et-hero-traffic">
            <div class="et-tr">
              <div class="et-tr-k">
                <v-icon size="12" aria-hidden="true">
                  mdi-arrow-up-bold
                </v-icon>
                <span>{{ pt('hero.upload', '上传', 'Upload') }}</span>
              </div>
              <div class="et-tr-v mono">
                {{ txText }}
              </div>
            </div>
            <div class="et-tr">
              <div class="et-tr-k">
                <v-icon size="12" aria-hidden="true">
                  mdi-arrow-down-bold
                </v-icon>
                <span>{{ pt('hero.download', '下载', 'Download') }}</span>
              </div>
              <div class="et-tr-v mono">
                {{ rxText }}
              </div>
            </div>
          </div>
          <div class="et-hero-spark" :class="{ 'is-flat': sparkEmpty }">
            <svg :viewBox="`0 0 ${SPARK_W} ${SPARK_H}`" preserveAspectRatio="none" aria-hidden="true">
              <defs>
                <linearGradient :id="`${uid}-rx`" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0" :style="{ stopColor: 'var(--et-accent)', stopOpacity: 0.30 }" />
                  <stop offset="1" :style="{ stopColor: 'var(--et-accent-quiet)', stopOpacity: 0.04 }" />
                </linearGradient>
                <linearGradient :id="`${uid}-tx`" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0" :style="{ stopColor: 'var(--et-info)', stopOpacity: 0.20 }" />
                  <stop offset="1" :style="{ stopColor: 'var(--et-info)', stopOpacity: 0.02 }" />
                </linearGradient>
              </defs>
              <line x1="0" :y1="SPARK_H - SPARK_PAD" :x2="SPARK_W" :y2="SPARK_H - SPARK_PAD" :style="{ stroke: 'var(--et-border)' }" stroke-width="1" />
              <template v-if="hasSpark">
                <polygon :points="txArea" :fill="`url(#${uid}-tx)`" />
                <polyline :points="txLine" fill="none" :style="{ stroke: 'var(--et-info)' }" stroke-width="1.4" stroke-opacity="0.55" stroke-linejoin="round" />
                <polygon :points="rxArea" :fill="`url(#${uid}-rx)`" />
                <polyline :points="rxLine" fill="none" :style="{ stroke: 'var(--et-accent)' }" stroke-width="1.6" stroke-linejoin="round" />
              </template>
            </svg>
            <span v-if="sparkEmpty" class="et-hero-spark-hint">{{ pt('hero.spark_idle', '暂无流量 · 60 秒趋势', 'No traffic yet · last 60s') }}</span>
          </div>
        </div>

        <!-- node summary: online first, offline peers stay visible (neutral) -->
        <div class="et-hero-card et-hero-peers">
          <div class="et-hero-sec-t">
            <span>{{ pt('hero.peers_title', '节点', 'Nodes') }}</span>
            <!-- 只有计数用等宽:ET Mono 没有 CJK 切片,中文标签必须留在 UI 字体里,
                 否则会掉进无 CJK 的 monospace 回退链而整段不可见。 -->
            <span class="et-hero-sec-count"><span class="mono">{{ onlinePeerCount }}</span> {{ pt('hero.online', '在线', 'online') }}</span>
          </div>
          <ul v-if="peerRows.length" class="et-peer-list">
            <li
              v-for="row in visiblePeerRows"
              :key="row.key"
              class="et-peer"
              :class="{ 'is-offline': !row.online }"
            >
              <span class="et-peer-dot" aria-hidden="true" />
              <span class="et-peer-ip mono truncate">{{ row.ip || row.hostname || '—' }}</span>
              <span class="et-peer-path">
                {{ row.online ? pathLabel(row) : offlineLabel(row) }}
              </span>
              <span class="et-peer-rtt mono" :class="row.online ? rttTone(row) : ''">
                <template v-if="row.online">{{ rttText(row) }}<span class="et-peer-rtt-unit"> ms</span></template>
                <template v-else>—</template>
              </span>
            </li>
          </ul>
          <p v-else class="et-hero-peers-empty" role="status">
            <template v-if="waitingPeers">
              {{ pt('hero.waiting_peers', '已加入网络，正在等待对端接入…', 'Joined the network — waiting for peers…') }}
            </template>
            <template v-else>
              {{ pt('hero.no_peers', '还没有发现其他节点。让对方加入同一网络名与密码即可。', 'No peers yet — ask another device to join with the same network name and secret.') }}
            </template>
          </p>
          <p v-if="hiddenPeerCount" class="et-hero-peers-more">
            {{ pt('hero.peers_more', `另有 ${hiddenPeerCount} 个节点，见「设备」`, `${hiddenPeerCount} more in Devices`) }}
          </p>
        </div>
      </template>

      <!-- ============ the only primary action: full-width, pinned low ============ -->
      <div class="et-hero-cta">
        <button
          type="button"
          class="et-cta"
          :class="actionIsDisconnect ? 'is-danger' : 'is-primary'"
          :disabled="ctaBusy"
          :aria-busy="ctaBusy"
          @click="onAction"
        >
          <span v-if="ctaBusy" class="et-cta-spinner" aria-hidden="true" />
          <v-icon v-else size="18" aria-hidden="true">
            {{ ctaIcon }}
          </v-icon>
          <span>{{ actionLabel }}</span>
        </button>
      </div>

      <!-- notifications blocked: one tap to the system settings, self-clears on return -->
      <button
        v-if="props.notifBlocked"
        type="button"
        class="et-hero-notif"
        :aria-label="pt('hero.notif_off_aria', '通知被禁用，点击去系统设置开启常驻通知', 'Notifications are off — open system settings to enable the ongoing notification')"
        @click="emit('openNotifSettings')"
      >
        <v-icon size="18" class="et-hero-notif-icon" aria-hidden="true">
          mdi-bell-off-outline
        </v-icon>
        <span class="et-hero-notif-text">
          <span class="et-hero-notif-title">{{ pt('hero.notif_off', '通知被禁用', 'Notifications are off') }}</span>
          <span class="et-hero-notif-sub">{{ pt('hero.notif_off_sub', '看不到实时速率常驻通知 · 点击去开启', 'The live-speed notification stays hidden · tap to enable') }}</span>
        </span>
        <v-icon size="16" class="et-hero-notif-chevron" aria-hidden="true">
          mdi-chevron-right
        </v-icon>
      </button>
    </template>
  </section>
</template>

<style scoped>
.et-hero {
  padding: var(--et-space-4) var(--et-space-4) var(--et-space-2);
  display: flex;
  flex-direction: column;
  gap: var(--et-gap-stack);
}

.et-hero-card {
  background: var(--et-surface-1);
  border: 1px solid var(--et-border);
  border-radius: var(--et-radius-md);
  padding: var(--et-pad-card);
}

/* ---- identity row ---- */
.et-hero-head {
  display: flex;
  align-items: center;
  gap: var(--et-space-3);
}

.et-hero-id {
  min-width: 0;
  flex: 1;
}

.et-hero-name {
  font-size: var(--et-font-title);
  font-weight: var(--et-weight-semibold);
  letter-spacing: -0.02em;
  line-height: var(--et-leading-tight);
}

.et-hero-ip {
  font-size: var(--et-font-body-sm);
  color: var(--et-text-2);
  margin-top: var(--et-space-1);
  /* real button: reset the UA chrome and keep the platform touch floor */
  min-height: var(--et-touch);
  padding: 0;
  border: 0;
  background: transparent;
  appearance: none;
  font-family: var(--et-font-data);
  font-variant-numeric: var(--et-numeric);
  line-height: var(--et-leading-tight);
  text-align: start;
}

.et-hero-ip.is-copyable {
  cursor: pointer;
}

.et-hero-ip:disabled {
  opacity: 1;
  cursor: default;
}

.et-hero-ip.is-live {
  color: var(--et-accent);
}

.et-hero-ip:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: 2px;
  border-radius: var(--et-radius-xs);
}

/* ---- signal: colour + shape + text, five states ---- */
.et-signal {
  display: inline-flex;
  align-items: center;
  gap: var(--et-space-2);
  padding: var(--et-space-1) var(--et-space-3) var(--et-space-1) var(--et-space-2);
  border-radius: var(--et-radius-pill);
  font-size: var(--et-font-caption);
  font-weight: var(--et-weight-medium);
  flex: 0 0 auto;
}

.et-signal-glyph {
  width: var(--et-space-3);
  height: var(--et-space-3);
  flex: 0 0 auto;
  display: grid;
  place-items: center;
}

.et-signal-glyph::before {
  content: '';
  display: block;
  background: currentColor;
}

.sig-up {
  background: var(--et-accent-quiet);
  color: var(--et-accent);
}
.sig-up .et-signal-glyph::before {
  width: var(--et-space-3);
  height: var(--et-space-3);
  border-radius: 50%;
}

.sig-sync {
  background: var(--et-info-quiet);
  color: var(--et-info);
}
.sig-sync .et-signal-glyph::before {
  width: var(--et-space-3);
  height: var(--et-space-3);
  border-radius: var(--et-radius-xs);
  animation: et-signal-breathe 1.4s var(--et-ease-standard) infinite;
}

.sig-degraded {
  background: var(--et-warn-quiet);
  color: var(--et-warn);
}
.sig-degraded .et-signal-glyph::before {
  width: 0;
  height: 0;
  border-left: 7px solid transparent;
  border-right: 7px solid transparent;
  border-bottom: 12px solid currentColor;
  background: none;
}

.sig-down {
  background: var(--et-danger-quiet);
  color: var(--et-danger);
}
.sig-down .et-signal-glyph::before {
  width: var(--et-space-3);
  height: 3px;
  border-radius: 2px;
}

.sig-idle {
  background: var(--et-neutral-quiet);
  color: var(--et-neutral);
}
.sig-idle .et-signal-glyph::before {
  width: var(--et-space-3);
  height: var(--et-space-3);
  border-radius: 50%;
  background: none;
  border: 2px solid currentColor;
}

@keyframes et-signal-breathe {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.35;
  }
}

/* ---- orb + the one primary number ---- */
.et-hero-focus {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: var(--et-space-3) 0 var(--et-space-2);
}

.et-orb {
  width: 132px;
  height: 132px;
  margin: 0 auto var(--et-space-4);
  border-radius: 50%;
  display: grid;
  place-items: center;
  background: radial-gradient(circle at 50% 42%, var(--et-accent-quiet), transparent 68%);
  border: 1px solid var(--et-accent);
  transition: border-color var(--et-dur-slow) var(--et-ease-standard);
}

.et-orb-core {
  width: 74px;
  height: 74px;
  border-radius: 50%;
  background: var(--et-accent);
  color: var(--et-on-accent);
  display: grid;
  place-items: center;
  transition: background var(--et-dur-slow) var(--et-ease-standard);
}

/* the indeterminate spinner inherits the orb's own on-colour instead of the
   theme's primary (which would vanish on an accent-filled core) */
.et-orb-core :deep(.v-progress-circular) {
  color: currentColor;
}

.et-orb.is-sync {
  background: radial-gradient(circle at 50% 42%, var(--et-info-quiet), transparent 68%);
  border-color: var(--et-info);
}
.et-orb.is-sync .et-orb-core {
  background: var(--et-info);
  color: var(--et-on-info);
}

.et-orb.is-degraded {
  background: radial-gradient(circle at 50% 42%, var(--et-warn-quiet), transparent 68%);
  border-color: var(--et-warn);
}
.et-orb.is-degraded .et-orb-core {
  background: var(--et-warn);
  color: var(--et-on-warn);
}

.et-orb.is-down {
  background: radial-gradient(circle at 50% 42%, var(--et-danger-quiet), transparent 68%);
  border-color: var(--et-danger);
}
.et-orb.is-down .et-orb-core {
  background: var(--et-surface-3);
  color: var(--et-danger);
}

.et-orb.is-idle {
  background: none;
  border-color: var(--et-border-strong);
}
.et-orb.is-idle .et-orb-core {
  background: var(--et-surface-3);
  color: var(--et-text-3);
}

/* the screen's single hero number: mono + tabular-nums, never proportional */
.et-hero-metric {
  display: inline-flex;
  align-items: baseline;
  gap: var(--et-space-1);
  font-variant-numeric: var(--et-numeric);
}

.et-hero-metric-value {
  font-size: var(--et-font-hero-fluid);
  font-weight: var(--et-weight-semibold);
  letter-spacing: -0.02em;
  line-height: var(--et-leading-tight);
}

.et-hero-metric-unit {
  font-size: var(--et-font-body-sm);
  color: var(--et-text-2);
}

.et-hero-metric-caption {
  font-size: var(--et-font-caption);
  color: var(--et-text-2);
  margin-top: var(--et-space-1);
  font-variant-numeric: var(--et-numeric);
}

/* ---- traffic ---- */
.et-hero-traffic {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--et-space-3);
}

.et-tr-k {
  font-size: var(--et-font-micro);
  color: var(--et-text-3);
  display: flex;
  align-items: center;
  gap: var(--et-space-1);
}

.et-tr-v {
  font-size: var(--et-font-title);
  font-weight: var(--et-weight-semibold);
  margin-top: var(--et-space-1);
  font-variant-numeric: var(--et-numeric);
  white-space: nowrap;
}

/* 64px trend strip — the container height is deliberate (no text is clipped
   inside it; the value lives above, in .et-tr-v) */
.et-hero-spark {
  position: relative;
  height: 64px;
  margin-top: var(--et-space-3);
  border-radius: var(--et-radius-sm);
  overflow: hidden;
  background: var(--et-surface-2);
  border: 1px solid var(--et-border);
}

.et-hero-spark svg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  display: block;
}

.et-hero-spark.is-flat {
  opacity: 0.75;
}

.et-hero-spark-hint {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  font-size: var(--et-font-micro);
  letter-spacing: 0.04em;
  color: var(--et-text-3);
}

/* ---- peer summary ---- */
.et-hero-sec-t {
  font-size: var(--et-font-caption);
  color: var(--et-text-3);
  font-weight: var(--et-weight-medium);
  margin-bottom: var(--et-space-2);
  display: flex;
  justify-content: space-between;
  gap: var(--et-space-3);
}

.et-peer-list {
  list-style: none;
  margin: 0;
  padding: 0;
}

/* PeerRow contract: dot / virtual IP / path / latency (right aligned, mono) */
.et-peer {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto auto;
  align-items: center;
  gap: var(--et-space-3);
  min-height: var(--et-row-h);
  font-size: var(--et-font-body-sm);
  border-top: 1px solid var(--et-border);
}

.et-peer:first-child {
  border-top: 0;
}

.et-peer-dot {
  width: var(--et-space-2);
  height: var(--et-space-2);
  border-radius: 50%;
  background: var(--et-accent);
  flex: 0 0 auto;
}

.et-peer.is-offline .et-peer-dot {
  background: var(--et-neutral);
}

.et-peer-ip {
  color: var(--et-text-2);
  font-size: var(--et-font-body-sm);
}

.et-peer.is-offline .et-peer-ip {
  color: var(--et-text-3);
}

.et-peer-path {
  color: var(--et-text-3);
  font-size: var(--et-font-caption);
  white-space: nowrap;
}

.et-peer-rtt {
  min-width: 62px;
  text-align: right;
  font-variant-numeric: var(--et-numeric);
  color: var(--et-text-2);
}

.et-peer-rtt.is-good {
  color: var(--et-accent);
}
.et-peer-rtt.is-mid {
  color: var(--et-warn);
}
.et-peer-rtt.is-bad {
  color: var(--et-danger);
}

.et-peer-rtt-unit {
  font-size: var(--et-font-micro);
  color: var(--et-text-3);
}

.et-peer.is-offline .et-peer-path {
  color: var(--et-neutral);
}

.et-hero-peers-empty {
  margin: 0;
  font-size: var(--et-font-caption);
  line-height: var(--et-leading-normal);
  color: var(--et-text-2);
  padding: var(--et-space-2) 0;
}

.et-hero-peers-more {
  margin: var(--et-space-2) 0 0;
  font-size: var(--et-font-micro);
  color: var(--et-text-3);
}

/* ---- the single primary action ---- */
.et-hero-cta {
  position: sticky;
  bottom: 0;
  z-index: var(--et-z-sticky);
  /* full-bleed over the scrolling hero, and it must clear the gesture bar */
  margin: var(--et-space-1) calc(var(--et-space-4) * -1) 0;
  padding: var(--et-space-3) var(--et-space-4) calc(var(--et-space-3) + var(--et-safe-bottom));
  background: linear-gradient(to top, var(--et-bg) 72%, transparent);
}

.et-cta {
  width: 100%;
  min-height: var(--et-touch);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--et-space-2);
  padding: 0 var(--et-space-5);
  border: 0;
  border-radius: var(--et-radius-sm);
  font-family: var(--et-font-ui);
  font-size: var(--et-font-body);
  font-weight: var(--et-weight-semibold);
  cursor: pointer;
  appearance: none;
  transition:
    filter var(--et-dur-fast) var(--et-ease-standard),
    transform var(--et-dur-instant) var(--et-ease-standard);
}

.et-cta.is-primary {
  background: var(--et-accent);
  color: var(--et-on-accent);
}

.et-cta.is-danger {
  background: var(--et-danger);
  color: var(--et-on-danger);
}

/* press feedback is a transform only — it must not push neighbours around */
.et-cta:active {
  transform: scale(0.985);
}

.et-cta:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: 2px;
}

.et-cta[disabled] {
  background: var(--et-surface-2);
  color: var(--et-text-disabled);
  cursor: not-allowed;
  transform: none;
}

.et-cta-spinner {
  width: var(--et-space-5);
  height: var(--et-space-5);
  border-radius: 50%;
  border: 2px solid currentColor;
  border-top-color: transparent;
  animation: et-cta-spin 700ms linear infinite;
}

@keyframes et-cta-spin {
  to {
    transform: rotate(360deg);
  }
}

/* ---- tap-to-fix notifications ---- */
.et-hero-notif {
  display: flex;
  align-items: center;
  gap: var(--et-space-2);
  width: 100%;
  min-height: var(--et-touch);
  padding: var(--et-space-3) var(--et-pad-card);
  border-radius: var(--et-radius-sm);
  border: 1px solid var(--et-warn);
  background: var(--et-warn-quiet);
  color: var(--et-text);
  font: inherit;
  text-align: start;
  cursor: pointer;
  transition: transform var(--et-dur-instant) var(--et-ease-standard);
}

.et-hero-notif:active {
  transform: scale(0.985);
}

.et-hero-notif:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: 2px;
}

.et-hero-notif-icon {
  color: var(--et-warn);
  flex: 0 0 auto;
}

.et-hero-notif-chevron {
  color: var(--et-text-3);
  flex: 0 0 auto;
}

.et-hero-notif-text {
  display: flex;
  flex-direction: column;
  min-width: 0;
  flex: 1;
}

.et-hero-notif-title {
  font-size: var(--et-font-body-sm);
  font-weight: var(--et-weight-semibold);
}

.et-hero-notif-sub {
  font-size: var(--et-font-caption);
  color: var(--et-text-2);
}

/* ---- empty states ---- */
.et-hero-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: var(--et-space-4) var(--et-space-2) var(--et-space-5);
  gap: var(--et-space-1);
}

.et-hero-empty-title {
  font-size: var(--et-font-headline);
  font-weight: var(--et-weight-semibold);
  letter-spacing: -0.02em;
  text-align: center;
}

.et-hero-empty-sub {
  font-size: var(--et-font-body-sm);
  line-height: var(--et-leading-normal);
  color: var(--et-text-2);
  max-width: 34ch;
  text-align: center;
}

.truncate {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* ---- shimmer skeletons: shown before the first network-info reply ---- */
.et-skeleton {
  position: relative;
  overflow: hidden;
  background: var(--et-surface-2);
}

.et-skeleton::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    90deg,
    transparent 0%,
    color-mix(in srgb, var(--et-surface-3) 72%, transparent) 50%,
    transparent 100%
  );
  transform: translateX(-100%);
  animation: et-shimmer 1.4s var(--et-ease-standard) infinite;
}

@keyframes et-shimmer {
  100% {
    transform: translateX(100%);
  }
}

/* ---- tablet / wide viewport ---- */
@media (min-width: 720px) {
  .et-hero-cta {
    margin-inline: calc(var(--et-space-4) * -1);
  }
}

@media (prefers-reduced-motion: reduce) {
  .et-signal-glyph::before {
    animation: none;
  }
  .et-skeleton::after {
    animation: none;
  }
  /* the spinner is the only loading affordance, so it keeps rotating — but
     slowly enough not to read as motion */
  .et-cta-spinner {
    animation-duration: 2s;
  }
}
</style>
