<script setup lang="ts">
import { useId } from 'vue'
import { usePhoneText } from '~/composables/hero_text'
import { mobileStats } from '~/composables/mobile_vpn'

const props = defineProps<{
  /** RPC client reachable (backend alive). Drives retry vs start semantics. */
  clientRunning: boolean
  /** Currently selected network instance id (state machine lives in index.vue). */
  instanceId?: string
  /** A connect/disconnect round-trip is in flight. */
  busy?: boolean
  /** First isClientRunning() probe has resolved (prevents boot-time flash). */
  booted?: boolean
  isAndroid?: boolean
}>()

const emit = defineEmits<{
  (e: 'connect'): void
  (e: 'disconnect'): void
  (e: 'grant'): void
  (e: 'retry'): void
}>()

const { pt } = usePhoneText()
const { t } = useI18n()
const uid = useId().replace(/[^\w-]/g, '')

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

const waitingPeers = computed(() => running.value && mobileStats.peerCount === 0)

const title = computed(() => {
  if (notFound.value)
    return t('client.not_running')
  if (permissionState.value)
    return pt('hero.permission_title', '需要 VPN 权限', 'VPN permission required')
  if (failedState.value)
    return pt('hero.failed_title', '连接失败', 'Connection failed')
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
  if (stoppedState.value) {
    return props.instanceId
      ? pt('hero.stopped_sub', '配置已就绪，点“连接”即可接入组网。', 'Your config is ready. Tap Connect to join the mesh.')
      : pt('hero.noconfig_sub', '还没有网络配置——可在下方「高级控制台」新建。', 'No network config yet — create one in the Advanced console below.')
  }
  return ''
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

// ---- main action -----------------------------------------------------------
const actionIsDisconnect = computed(() => running.value)
const actionLabel = computed(() => {
  if (notFound.value)
    return t('client.retry')
  if (permissionState.value)
    return pt('hero.action_grant', '重新授权', 'Grant permission')
  if (actionIsDisconnect.value)
    return t('status.disconnect')
  return pt('hero.action_connect', '连接', 'Connect')
})

function onAction() {
  if (props.busy)
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
  emit('connect')
}

const statusTone = computed(() => {
  if (running.value)
    return 'is-on'
  if (permissionState.value || failedState.value)
    return 'is-warn'
  return 'is-off'
})
</script>

<template>
  <section class="et-hero" :aria-busy="skeleton">
    <!-- ============ skeleton: first collectNetworkInfo round-trip ============ -->
    <template v-if="skeleton">
      <div class="et-hero-card et-reveal" style="--et-reveal-delay: 0ms">
        <div class="et-skeleton" style="width: 44%; height: 26px; border-radius: 8px" />
        <div class="et-skeleton mt-3" style="width: 62%; height: 14px; border-radius: 7px" />
        <div class="et-skeleton mt-5" style="width: 100%; height: 64px; border-radius: var(--et-radius-sm)" />
      </div>
      <div class="et-hero-card et-reveal" style="--et-reveal-delay: 90ms">
        <div class="et-skeleton" style="width: 100%; height: 56px; border-radius: 999px" />
      </div>
    </template>

    <!-- ========================= empty / error states ======================== -->
    <div v-else-if="notFound || permissionState || failedState || stoppedState" class="et-hero-card et-reveal" style="--et-reveal-delay: 0ms">
      <div class="et-hero-empty">
        <div class="et-hero-empty-orb" :class="statusTone">
          <v-icon v-if="notFound" size="30">
            mdi-server-network-off
          </v-icon>
          <v-icon v-else-if="permissionState" size="30">
            mdi-shield-key-outline
          </v-icon>
          <v-icon v-else-if="failedState" size="30">
            mdi-shield-alert-outline
          </v-icon>
          <v-icon v-else size="30">
            mdi-shield-off-outline
          </v-icon>
        </div>
        <div class="text-h6 et-hero-empty-title text-center font-weight-bold">
          {{ title }}
        </div>
        <div class="et-hero-empty-sub text-center">
          {{ subtitle }}
        </div>
      </div>
    </div>

    <!-- ============================== live hero ============================== -->
    <template v-else>
      <!-- status card: name + virtual IP, pulse when connected -->
      <div class="et-hero-card et-reveal et-hero-status" style="--et-reveal-delay: 0ms">
        <div class="et-hero-shield" :class="{ 'is-on': running }">
          <svg viewBox="0 0 24 24" width="26" height="26" aria-hidden="true">
            <path
              d="M12 2 4 5v6c0 5.25 3.4 9.74 8 11 4.6-1.26 8-5.75 8-11V5l-8-3Z"
              :style="{ fill: running ? 'var(--et-accent)' : 'var(--et-surface-3)' }"
            />
            <path
              d="M8.6 12.2l2.3 2.3 4.5-4.6"
              fill="none"
              :style="{ stroke: running ? '#06231c' : 'var(--et-text-tertiary)' }"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </div>
        <div class="et-hero-id min-w-0">
          <div class="et-hero-name truncate">
            {{ mobileStats.networkName || 'EasyTier' }}
          </div>
          <div class="et-hero-ip mono" :class="{ 'is-live': running }">
            {{ mobileStats.virtualIp || '—.—.—.—' }}
          </div>
        </div>
        <div class="et-hero-state et-status-pill" :class="running ? 'is-on' : 'is-off'">
          <div v-if="running" class="et-pulse-dot" />
          <v-icon v-else size="12">
            mdi-wifi-off
          </v-icon>
          <span>{{ running ? t('status.connected') : t('status.disconnected') }}</span>
        </div>
      </div>

      <div class="et-hero-cols">
        <div class="et-hero-col">
          <!-- rates + 60s sparkline -->
          <div class="et-hero-card et-reveal" style="--et-reveal-delay: 90ms">
            <div class="et-hero-rate-row">
              <span class="et-hero-rate-icon is-rx"><v-icon size="15">mdi-arrow-down-bold</v-icon></span>
              <span class="et-hero-rate-value mono"><span :key="rxText" class="et-rate-roll">{{ rxText }}</span></span>
            </div>
            <div class="et-hero-rate-row">
              <span class="et-hero-rate-icon is-tx"><v-icon size="15">mdi-arrow-up-bold</v-icon></span>
              <span class="et-hero-rate-value mono"><span :key="txText" class="et-rate-roll">{{ txText }}</span></span>
            </div>
            <div class="et-hero-spark mt-2" :class="{ 'is-flat': sparkEmpty }">
              <svg :viewBox="`0 0 ${SPARK_W} ${SPARK_H}`" preserveAspectRatio="none" aria-hidden="true">
                <defs>
                  <linearGradient :id="`${uid}-rx`" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0" :style="{ stopColor: 'var(--et-accent)', stopOpacity: 0.30 }" />
                    <stop offset="1" :style="{ stopColor: 'var(--et-accent-dim)', stopOpacity: 0.04 }" />
                  </linearGradient>
                  <linearGradient :id="`${uid}-tx`" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0" :style="{ stopColor: 'var(--et-info)', stopOpacity: 0.20 }" />
                    <stop offset="1" :style="{ stopColor: 'var(--et-info)', stopOpacity: 0.02 }" />
                  </linearGradient>
                </defs>
                <line x1="0" :y1="SPARK_H - SPARK_PAD" :x2="SPARK_W" :y2="SPARK_H - SPARK_PAD" :style="{ stroke: 'var(--et-border-hairline)' }" stroke-width="1" />
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
        </div>

        <div class="et-hero-col">
          <!-- stat chips -->
          <div class="et-hero-chips et-reveal" style="--et-reveal-delay: 170ms">
            <div class="et-hero-chip">
              <v-icon size="15" color="primary">
                mdi-nodes
              </v-icon>
              <span class="mono">{{ mobileStats.peerCount }}</span>
              <span class="et-hero-chip-label">{{ pt('hero.peers', '节点', 'Peers') }}</span>
            </div>
            <div class="et-hero-chip">
              <v-icon size="15" color="primary">
                mdi-routes
              </v-icon>
              <span class="mono">{{ mobileStats.routeCount }}</span>
              <span class="et-hero-chip-label">{{ pt('hero.routes', '路由', 'Routes') }}</span>
            </div>
          </div>

          <!-- main action -->
          <div class="et-reveal" style="--et-reveal-delay: 250ms">
            <v-btn
              class="et-hero-action"
              block
              rounded="pill"
              size="x-large"
              :color="actionIsDisconnect ? 'error' : 'primary'"
              :variant="actionIsDisconnect ? 'outlined' : 'flat'"
              :loading="busy"
              :prepend-icon="actionIsDisconnect ? 'mdi-lan-disconnect' : 'mdi-lan-connect'"
              @click="onAction"
            >
              {{ actionLabel }}
            </v-btn>
          </div>
        </div>
      </div>

      <!-- waiting for peers nuance -->
      <div v-if="waitingPeers" class="et-hero-waiting et-reveal" style="--et-reveal-delay: 320ms" role="status">
        <v-icon size="14" class="mr-2">
          mdi-magnet-on
        </v-icon>
        {{ pt('hero.waiting_peers', '已加入网络，正在等待对端接入…', 'Joined the network — waiting for peers…') }}
      </div>
    </template>

    <!-- the action button is also part of the empty states -->
    <div v-if="!skeleton && (notFound || permissionState || failedState || stoppedState)" class="et-reveal" style="--et-reveal-delay: 90ms">
      <v-btn
        class="et-hero-action"
        block
        rounded="pill"
        size="x-large"
        color="primary"
        variant="flat"
        :loading="busy"
        :prepend-icon="notFound ? 'mdi-replay' : (permissionState ? 'mdi-shield-key-outline' : 'mdi-lan-connect')"
        @click="onAction"
      >
        {{ actionLabel }}
      </v-btn>
    </div>
  </section>
</template>

<style scoped>
.et-hero {
  padding: 16px 16px 8px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.et-hero-card {
  background: var(--et-surface);
  border: 1px solid var(--et-border);
  border-radius: var(--et-radius);
  padding: 14px 16px;
  box-shadow: 0 10px 30px -18px rgb(0 0 0 / 55%);
}

/* ---- status row ---- */
.et-hero-status {
  display: flex;
  align-items: center;
  gap: 12px;
}

.et-hero-shield {
  width: 46px;
  height: 46px;
  flex-shrink: 0;
  border-radius: 14px;
  display: grid;
  place-items: center;
  background: var(--et-surface-2);
  border: 1px solid var(--et-border-hairline);
  transition:
    box-shadow 0.4s ease,
    border-color 0.4s ease;
}

.et-hero-shield.is-on {
  border-color: var(--et-accent);
  box-shadow:
    0 0 0 0 var(--et-glow),
    0 0 22px -6px var(--et-glow);
  animation: et-hero-breathe 2.6s ease-in-out infinite;
}

@keyframes et-hero-breathe {
  0%,
  100% {
    box-shadow:
      0 0 0 0 var(--et-glow),
      0 0 22px -8px var(--et-glow);
  }
  50% {
    box-shadow:
      0 0 0 6px transparent,
      0 0 26px -4px var(--et-glow);
  }
}

.et-hero-id {
  min-width: 0;
  flex: 1;
}

.et-hero-name {
  font-size: 1.3rem;
  font-weight: 800;
  letter-spacing: -0.03em;
  line-height: 1.2;
}

.et-hero-ip {
  font-size: 0.86rem;
  color: var(--et-text-secondary);
  margin-top: 2px;
}

.et-hero-ip.is-live {
  color: var(--et-accent);
}

/* ---- rate rows ---- */
.et-hero-cols {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.et-hero-col {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-width: 0;
}

.et-hero-rate-row {
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 34px;
}

.et-hero-rate-icon {
  width: 26px;
  height: 26px;
  border-radius: 8px;
  display: grid;
  place-items: center;
  flex-shrink: 0;
}

.et-hero-rate-icon.is-rx {
  background: var(--et-accent-dim);
  color: var(--et-accent);
}

.et-hero-rate-icon.is-tx {
  background: color-mix(in srgb, var(--et-info) 16%, transparent);
  color: var(--et-info);
}

.et-hero-rate-value {
  font-size: 1.28rem;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  letter-spacing: -0.02em;
  overflow: hidden;
  white-space: nowrap;
}

.et-rate-roll {
  display: inline-block;
  animation: et-rate-in 0.22s cubic-bezier(0.2, 0.7, 0.3, 1);
}

@keyframes et-rate-in {
  from {
    transform: translateY(7px);
    opacity: 0;
  }
  to {
    transform: none;
    opacity: 1;
  }
}

/* ---- sparkline ---- */
.et-hero-spark {
  position: relative;
  height: 64px;
  border-radius: var(--et-radius-sm);
  overflow: hidden;
  background: linear-gradient(180deg, transparent 55%, var(--et-accent-dim) 100%), var(--et-surface-2);
  border: 1px solid var(--et-border-hairline);
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
  font-size: 0.68rem;
  letter-spacing: 0.04em;
  color: var(--et-text-tertiary);
}

/* ---- chips ---- */
.et-hero-chips {
  display: flex;
  gap: 8px;
}

.et-hero-chip {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  padding: 10px 8px;
  border-radius: 999px;
  background: var(--et-surface);
  border: 1px solid var(--et-border);
  font-size: 0.92rem;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  min-width: 0;
}

.et-hero-chip-label {
  font-size: 0.72rem;
  font-weight: 500;
  color: var(--et-text-secondary);
}

/* ---- main action ---- */
.et-hero-action {
  min-height: var(--et-touch);
  font-weight: 700;
  letter-spacing: 0.01em;
}

/* ---- empty states ---- */
.et-hero-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 18px 8px 20px;
  gap: 6px;
}

.et-hero-empty-orb {
  width: 64px;
  height: 64px;
  border-radius: 20px;
  display: grid;
  place-items: center;
  margin-bottom: 8px;
  background: var(--et-surface-2);
  border: 1px solid var(--et-border-hairline);
  color: var(--et-text-tertiary);
}

.et-hero-empty-orb.is-warn {
  background: color-mix(in srgb, var(--et-warning) 14%, var(--et-surface-2));
  color: var(--et-warning);
  border-color: color-mix(in srgb, var(--et-warning) 30%, transparent);
}

.et-hero-empty-title {
  letter-spacing: -0.02em;
}

.et-hero-empty-sub {
  font-size: 0.82rem;
  line-height: 1.5;
  color: var(--et-text-secondary);
  max-width: 30ch;
}

.et-hero-waiting {
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.74rem;
  color: var(--et-text-secondary);
  padding: 2px 0 4px;
}

.truncate {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* staggered entrance — cascading reveal, restrained steps */
.et-reveal {
  opacity: 0;
  animation: et-rise 0.5s cubic-bezier(0.2, 0.7, 0.3, 1) forwards;
  animation-delay: var(--et-reveal-delay, 0ms);
}

@keyframes et-rise {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}

/* ---- tablet / wide viewport: split rates+trend | stats+action ---- */
@media (min-width: 720px) {
  .et-hero-cols {
    flex-direction: row;
    align-items: stretch;
  }

  .et-hero-cols .et-hero-col {
    flex: 1;
  }

  .et-hero-cols .et-hero-col:first-child {
    flex: 1.25;
  }
}

@media (prefers-reduced-motion: reduce) {
  .et-reveal {
    animation: none;
    opacity: 1;
  }
  .et-rate-roll {
    animation: none;
  }
  .et-hero-shield.is-on {
    animation: none;
    box-shadow: 0 0 22px -8px var(--et-glow);
  }
}
</style>
