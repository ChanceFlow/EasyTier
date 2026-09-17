<template>
  <div class="network-chart et-chart-host">
    <div class="d-flex align-center justify-space-between flex-wrap ga-2 mb-2 px-1">
      <div class="d-flex align-center ga-3 text-caption">
        <!-- TX Rate Pill(实线,与图中 TX 线型一致) -->
        <div class="et-rate-pill is-tx">
          <div class="et-rate-icon">
            <v-icon size="12">mdi-arrow-up-bold</v-icon>
          </div>
          <div class="d-flex flex-column">
            <span class="et-rate-label">{{ t('upload') }}</span>
            <span class="et-rate-num mono">{{ currentUpload }}/s</span>
          </div>
        </div>

        <!-- RX Rate Pill(虚线,与图中 RX 线型一致) -->
        <div class="et-rate-pill is-rx">
          <div class="et-rate-icon">
            <v-icon size="12">mdi-arrow-down-bold</v-icon>
          </div>
          <div class="d-flex flex-column">
            <span class="et-rate-label">{{ t('download') }}</span>
            <span class="et-rate-num mono">{{ currentDownload }}/s</span>
          </div>
        </div>
      </div>

      <!-- Peak indicator -->
      <div class="et-peak-pill mono text-caption text-medium-emphasis">
        <span class="text-xs">{{ t('status.peak', 'PEAK') }}:</span>
        <span class="font-weight-medium ms-1">{{ peakFormatted }}/s</span>
      </div>
    </div>

    <!-- 实时流的文字等价物:当前值 + 状态文字,并提供暂停/继续 -->
    <div class="et-chart-status mb-1 px-1">
      <span class="et-chart-status__text mono">{{ chartStatusText }}</span>
      <button
        type="button"
        class="et-chart-pause"
        :aria-pressed="paused"
        :aria-label="paused ? t('status.resume_chart', 'Resume live chart') : t('status.pause_chart', 'Pause live chart')"
        @click="togglePause"
      >
        <svg v-if="paused" class="et-chart-pause__icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M8 5.5v13l11-6.5-11-6.5Z" />
        </svg>
        <svg v-else class="et-chart-pause__icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M7 5h3.5v14H7V5Zm6.5 0H17v14h-3.5V5Z" />
        </svg>
        <span>{{ paused ? t('status.resume', 'Resume') : t('status.pause', 'Pause') }}</span>
      </button>
    </div>

    <div class="et-canvas-container">
      <canvas ref="chartCanvas" role="img" :aria-label="chartAriaLabel" />
    </div>
  </div>
</template>

<script setup lang="ts">
import {
  CategoryScale,
  Chart as ChartJS,
  Filler,
  Legend,
  LinearScale,
  LineController,
  LineElement,
  PointElement,
  Title,
  Tooltip,
} from 'chart.js'
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useTheme } from 'vuetify'

const { t } = useI18n()
const theme = useTheme()

// Register Chart.js components
ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  LineController,
  Title,
  Tooltip,
  Legend,
  Filler,
)

interface Props {
  uploadRate: string
  downloadRate: string
}

const props = defineProps<Props>()

const chartCanvas = ref<HTMLCanvasElement>()
let chart: ChartJS | null = null
let updateTimer: number | null = null

// Store 60 data points (2 min window at 2s per sample)
const maxDataPoints = 60
const uploadHistory: number[] = []
const downloadHistory: number[] = []
const timeLabels: string[] = []

const currentUpload = ref('0 B')
const currentDownload = ref('0 B')
const peakBytes = ref(0)

const peakFormatted = computed(() => formatBytes(peakBytes.value))

// 暂停是语义状态:直接由这个 ref 决定刷新与否,不依赖 transitionend/animationend。
const paused = ref(false)

function togglePause() {
  paused.value = !paused.value
}

const chartStatusText = computed(() => {
  const values = `${t('upload')} ${currentUpload.value}/s · ${t('download')} ${currentDownload.value}/s`
  return paused.value
    ? `${t('status.chart_paused', 'Paused')} · ${values}`
    : `${t('status.chart_live', 'Live')} · ${values}`
})

const chartAriaLabel = computed(() => {
  return `${t('status.live_bandwidth')} — ${chartStatusText.value} · ${t('status.peak', 'PEAK')} ${peakFormatted.value}/s`
})

// Parse rate string with units to bytes/sec
function parseRateToBytes(rateStr: string): number {
  if (!rateStr || rateStr === '0')
    return 0

  const match = rateStr.match(/([0-9.]+)\s*([KMGT]?i?B)/i)
  if (!match)
    return 0

  const value = parseFloat(match[1])
  const unit = match[2].toUpperCase()

  const multipliers: { [key: string]: number } = {
    B: 1,
    KB: 1000,
    KIB: 1024,
    MB: 1000000,
    MIB: 1024 * 1024,
    GB: 1000000000,
    GIB: 1024 * 1024 * 1024,
    TB: 1000000000000,
    TIB: 1024 * 1024 * 1024 * 1024,
  }

  return value * (multipliers[unit] || 1)
}

// Format bytes to human readable string
function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0)
    return '0 B'

  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.min(sizes.length - 1, Math.floor(Math.log(bytes) / Math.log(k)))

  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`
}

function updateData() {
  // 暂停后停止刷新:保留现有曲线与数值,继续按钮恢复
  if (paused.value)
    return

  const uploadBytes = parseRateToBytes(props.uploadRate)
  const downloadBytes = parseRateToBytes(props.downloadRate)

  currentUpload.value = formatBytes(uploadBytes)
  currentDownload.value = formatBytes(downloadBytes)

  const currentMax = Math.max(uploadBytes, downloadBytes)
  if (currentMax > peakBytes.value) {
    peakBytes.value = currentMax
  }

  uploadHistory.push(uploadBytes)
  downloadHistory.push(downloadBytes)

  const now = new Date()
  const timeStr = now.toLocaleTimeString(navigator.language, {
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
  timeLabels.push(timeStr)

  if (uploadHistory.length > maxDataPoints) {
    uploadHistory.shift()
    downloadHistory.shift()
    timeLabels.shift()
  }

  if (chart) {
    chart.data.labels = timeLabels
    chart.data.datasets[0].data = uploadHistory
    chart.data.datasets[1].data = downloadHistory
    chart.update('none')
  }
}

// ---------------------------------------------------------------------------
// Theme-aware canvas palette
//
// Canvas colors cannot use CSS variables directly, so we read the `--et-*`
// design tokens from the DOM at runtime. Reading from the chart's own canvas
// (which inherits the tokens from `.v-application`) is what actually follows
// the light/dark switch: Vuetify puts the theme class on `.v-application`, not
// on `<html>`, so `document.documentElement` would always report the dark
// `:root` values. The element lookup keeps a `documentElement` fallback for
// SSR / non-browser hosts.
//
// No hardcoded colours: an unresolvable token degrades to the `transparent`
// keyword instead of a baked-in hex value.
// ---------------------------------------------------------------------------
interface ChartPalette {
  accent: string
  info: string
  textSecondary: string
  grid: string
  tooltipBg: string
  tooltipTitle: string
  tooltipBody: string
  tooltipBorder: string
  pointBorder: string
  fontFamily: string
  tickFontSize: number
}

function readCssVar(name: string): string {
  if (typeof window === 'undefined' || typeof document === 'undefined')
    return ''

  const el = chartCanvas.value ?? document.documentElement
  return el ? getComputedStyle(el).getPropertyValue(name).trim() : ''
}

// Parse #rgb/#rgba/#rrggbb/#rrggbbaa (and best-effort rgb()/rgba()) to rgb.
// `color-mix()` and anything unrecognized is passed through unchanged.
function parseColorToRgb(color: string): { r: number, g: number, b: number } | null {
  const input = (color || '').trim()
  if (!input)
    return null

  const hex = input.match(/^#([0-9a-f]{3,8})$/i)
  if (hex) {
    let h = hex[1]
    if (h.length === 3 || h.length === 4)
      h = h.split('').map(c => c + c).join('')
    if (h.length < 6)
      return null
    return {
      r: Number.parseInt(h.slice(0, 2), 16),
      g: Number.parseInt(h.slice(2, 4), 16),
      b: Number.parseInt(h.slice(4, 6), 16),
    }
  }

  const rgb = input.match(/^rgba?\(([^)]+)\)$/i)
  if (rgb) {
    const parts = rgb[1].split(/[\s,/]+/).filter(Boolean)
    if (parts.length < 3)
      return null
    return {
      r: Math.round(Number.parseFloat(parts[0])),
      g: Math.round(Number.parseFloat(parts[1])),
      b: Math.round(Number.parseFloat(parts[2])),
    }
  }

  return null
}

// Convert a theme token to an rgba() string with the requested alpha so the
// Chart.js gradient stops / fills can be derived from the active theme.
function toRgba(color: string, alpha: number): string {
  const parsed = parseColorToRgb(color)
  if (!parsed)
    return 'transparent'
  return `rgba(${parsed.r}, ${parsed.g}, ${parsed.b}, ${alpha})`
}

// Chart-local grid tint. A decorative border token composites to well under
// 1.3:1 against the chart surface, at which point the chart reads as having no
// scale at all. Deriving the grid from the secondary text token at a low alpha
// keeps it subtle but clearly perceptible in both themes.
const GRID_ALPHA = 0.32

function readPalette(): ChartPalette {
  const accent = readCssVar('--et-accent')
  const info = readCssVar('--et-info')
  const textSecondary = readCssVar('--et-text-2')
  const text = readCssVar('--et-text')
  const surface = readCssVar('--et-surface-1')
  const fontFamily = readCssVar('--et-font-data') || 'monospace'
  const tickFontSize = Number.parseFloat(readCssVar('--et-font-micro')) || 10

  return {
    accent,
    info,
    textSecondary,
    grid: toRgba(textSecondary, GRID_ALPHA),
    tooltipBg: toRgba(surface, 0.95),
    tooltipTitle: text || textSecondary,
    tooltipBody: textSecondary,
    tooltipBorder: toRgba(accent, 0.28),
    pointBorder: surface,
    fontFamily,
    tickFontSize,
  }
}

function initChart() {
  if (!chartCanvas.value)
    return

  const ctx = chartCanvas.value.getContext('2d')
  if (!ctx)
    return

  const palette = readPalette()

  // Theme-derived gradient fills
  const txGrad = ctx.createLinearGradient(0, 0, 0, 140)
  txGrad.addColorStop(0, toRgba(palette.accent, 0.28))
  txGrad.addColorStop(1, toRgba(palette.accent, 0.01))

  const rxGrad = ctx.createLinearGradient(0, 0, 0, 140)
  rxGrad.addColorStop(0, toRgba(palette.info, 0.24))
  rxGrad.addColorStop(1, toRgba(palette.info, 0.01))

  chart = new ChartJS(ctx, {
    type: 'line',
    data: {
      labels: timeLabels,
      datasets: [
        {
          label: t('upload'),
          data: uploadHistory,
          borderColor: palette.accent,
          backgroundColor: txGrad,
          borderWidth: 2,
          // 实线 = 上传
          borderDash: [],
          fill: true,
          tension: 0.35,
          pointRadius: 0,
          pointHoverRadius: 5,
          pointHoverBackgroundColor: palette.accent,
          pointHoverBorderColor: palette.pointBorder,
          pointHoverBorderWidth: 2,
        },
        {
          label: t('download'),
          data: downloadHistory,
          borderColor: palette.info,
          backgroundColor: rxGrad,
          borderWidth: 2,
          // 虚线 = 下载:序列不只靠颜色区分(灰度/色盲下仍可辨)
          borderDash: [6, 4],
          fill: true,
          tension: 0.35,
          pointRadius: 0,
          pointHoverRadius: 5,
          pointHoverBackgroundColor: palette.info,
          pointHoverBorderColor: palette.pointBorder,
          pointHoverBorderWidth: 2,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: {
        intersect: false,
        mode: 'index',
      },
      plugins: {
        legend: {
          display: false,
        },
        tooltip: {
          backgroundColor: palette.tooltipBg,
          titleColor: palette.tooltipTitle,
          bodyColor: palette.tooltipBody,
          borderColor: palette.tooltipBorder,
          borderWidth: 1,
          padding: 8,
          cornerRadius: 10,
          boxPadding: 4,
          callbacks: {
            label(context: any) {
              const value = context.parsed.y
              return ` ${context.dataset.label}: ${formatBytes(value)}/s`
            },
          },
        },
      },
      scales: {
        x: {
          display: true,
          grid: {
            color: palette.grid,
          },
          ticks: {
            maxTicksLimit: 4,
            color: palette.textSecondary,
            font: {
              family: palette.fontFamily,
              size: palette.tickFontSize,
            },
          },
        },
        y: {
          display: true,
          beginAtZero: true,
          min: 0,
          grid: {
            color: palette.grid,
          },
          ticks: {
            maxTicksLimit: 4,
            color: palette.textSecondary,
            callback(value: any) {
              return formatBytes(value as number)
            },
            font: {
              family: palette.fontFamily,
              size: palette.tickFontSize,
            },
          },
        },
      },
      animation: {
        duration: 0,
      },
    },
  })
}

// React to live theme switches: colors are read from the DOM at chart
// creation, so the chart is rebuilt once the new theme class has been applied.
function rebuildChart() {
  if (chart) {
    chart.destroy()
    chart = null
  }
  initChart()
}

watch(() => theme.name.value, async () => {
  if (!chart)
    return
  await nextTick()
  rebuildChart()
})

// NOTE: no `immediate: true` here — the single initial data push happens in
// `onMounted` after the history buffers are seeded, otherwise the chart would
// receive two samples for the same mount.
watch([() => props.uploadRate, () => props.downloadRate], () => {
  updateData()
})

onMounted(async () => {
  const now = new Date()
  for (let i = 0; i < maxDataPoints; i++) {
    const date = new Date(now.getTime() - (maxDataPoints - i) * 2000)
    const timeStr = date.toLocaleTimeString(navigator.language, {
      hour12: false,
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
    uploadHistory.push(0)
    downloadHistory.push(0)
    timeLabels.push(timeStr)
  }

  await nextTick()
  initChart()
  updateData()

  updateTimer = window.setInterval(() => {
    if (typeof document !== 'undefined' && document.hidden)
      return
    updateData()
  }, 2000)
})

onUnmounted(() => {
  if (chart) {
    chart.destroy()
    chart = null
  }
  if (updateTimer) {
    clearInterval(updateTimer)
    updateTimer = null
  }
})
</script>

<style scoped>
.network-chart {
  background: transparent;
  padding: var(--et-space-1) var(--et-space-1) 0;
}

.et-rate-pill {
  display: flex;
  align-items: center;
  gap: var(--et-space-1);
  padding: var(--et-space-1) var(--et-space-2);
  border-radius: var(--et-radius-xs);
  background: var(--et-surface-2);
  border: 1px solid var(--et-border);
}

/* 左侧边框的实/虚与图中线型一致:序列不只靠颜色区分 */
.et-rate-pill.is-tx {
  border-left: 3px solid var(--et-accent);
}
.et-rate-pill.is-tx .et-rate-icon {
  color: var(--et-accent);
}

.et-rate-pill.is-rx {
  border-left: 3px dashed var(--et-info);
}
.et-rate-pill.is-rx .et-rate-icon {
  color: var(--et-info);
}

.et-rate-label {
  font-size: var(--et-font-micro);
  font-weight: var(--et-weight-semibold);
  color: var(--et-text-3);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  line-height: 1;
}

.et-rate-num {
  font-size: var(--et-font-caption);
  font-weight: var(--et-weight-semibold);
  line-height: 1.2;
}

.et-peak-pill {
  font-size: var(--et-font-micro);
  background: var(--et-surface-2);
  padding: var(--et-space-1) var(--et-space-2);
  border-radius: var(--et-radius-pill);
  border: 1px solid var(--et-border);
}

/* 实时流的文字等价物 + 暂停/继续 */
.et-chart-status {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--et-space-2);
  min-height: var(--et-touch-web);
}

.et-chart-status__text {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--et-font-micro);
  color: var(--et-text-2);
  font-variant-numeric: var(--et-numeric);
}

.et-chart-pause {
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  gap: var(--et-space-1);
  min-height: var(--et-touch-web);
  padding: 0 var(--et-space-2);
  border: 1px solid var(--et-control-border);
  border-radius: var(--et-radius-pill);
  background: var(--et-surface-2);
  color: var(--et-text-2);
  font-size: var(--et-font-micro);
  font-weight: var(--et-weight-medium);
  cursor: pointer;
}

.et-chart-pause[aria-pressed='true'] {
  background: var(--et-accent-quiet);
  color: var(--et-accent);
  border-color: color-mix(in srgb, var(--et-accent) 45%, transparent);
}

.et-chart-pause__icon {
  width: 12px;
  height: 12px;
}

.et-canvas-container {
  position: relative;
  width: 100%;
  height: 8.5rem;
}
</style>
