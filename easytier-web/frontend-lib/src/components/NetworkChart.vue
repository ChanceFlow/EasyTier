<template>
  <div class="network-chart et-chart-host">
    <div class="d-flex align-center justify-space-between mb-2 px-1">
      <div class="d-flex align-center ga-3 text-caption">
        <!-- TX Rate Pill -->
        <div class="et-rate-pill is-tx">
          <div class="et-rate-icon">
            <v-icon size="12">mdi-arrow-up-bold</v-icon>
          </div>
          <div class="d-flex flex-column">
            <span class="et-rate-label">{{ t('upload') }}</span>
            <span class="et-rate-num mono">{{ currentUpload }}/s</span>
          </div>
        </div>

        <!-- RX Rate Pill -->
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

    <div class="et-canvas-container" style="height: 8.5rem">
      <canvas ref="chartCanvas" />
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

const { t } = useI18n()

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

function initChart() {
  if (!chartCanvas.value)
    return

  const ctx = chartCanvas.value.getContext('2d')
  if (!ctx)
    return

  // Beautiful cyber gradient fills
  const txGrad = ctx.createLinearGradient(0, 0, 0, 140)
  txGrad.addColorStop(0, 'rgba(0, 242, 182, 0.28)')
  txGrad.addColorStop(1, 'rgba(0, 242, 182, 0.01)')

  const rxGrad = ctx.createLinearGradient(0, 0, 0, 140)
  rxGrad.addColorStop(0, 'rgba(0, 180, 216, 0.24)')
  rxGrad.addColorStop(1, 'rgba(0, 180, 216, 0.01)')

  chart = new ChartJS(ctx, {
    type: 'line',
    data: {
      labels: timeLabels,
      datasets: [
        {
          label: t('upload'),
          data: uploadHistory,
          borderColor: '#00F2B6',
          backgroundColor: txGrad,
          borderWidth: 2,
          fill: true,
          tension: 0.35,
          pointRadius: 0,
          pointHoverRadius: 5,
          pointHoverBackgroundColor: '#00F2B6',
          pointHoverBorderColor: '#080A0F',
          pointHoverBorderWidth: 2,
        },
        {
          label: t('download'),
          data: downloadHistory,
          borderColor: '#00B4D8',
          backgroundColor: rxGrad,
          borderWidth: 2,
          fill: true,
          tension: 0.35,
          pointRadius: 0,
          pointHoverRadius: 5,
          pointHoverBackgroundColor: '#00B4D8',
          pointHoverBorderColor: '#080A0F',
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
          backgroundColor: 'rgba(14, 19, 31, 0.95)',
          titleColor: '#F3F6FA',
          bodyColor: '#8E99AF',
          borderColor: 'rgba(0, 242, 182, 0.25)',
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
            display: false,
          },
          ticks: {
            maxTicksLimit: 4,
            color: 'rgba(142, 153, 175, 0.65)',
            font: {
              family: 'ET Mono, monospace',
              size: 9,
            },
          },
        },
        y: {
          display: true,
          beginAtZero: true,
          min: 0,
          grid: {
            color: 'rgba(255, 255, 255, 0.05)',
          },
          ticks: {
            maxTicksLimit: 4,
            color: 'rgba(142, 153, 175, 0.65)',
            callback(value: any) {
              return formatBytes(value as number)
            },
            font: {
              family: 'ET Mono, monospace',
              size: 9,
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

watch([() => props.uploadRate, () => props.downloadRate], () => {
  updateData()
}, { immediate: true })

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
  padding: 0.25rem 0.25rem 0;
}

.et-rate-pill {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px;
  border-radius: var(--et-radius-xs);
  background: var(--et-surface-2);
  border: 1px solid var(--et-border-hairline);
}

.et-rate-pill.is-tx {
  border-left: 2px solid var(--et-accent);
}
.et-rate-pill.is-tx .et-rate-icon {
  color: var(--et-accent);
}

.et-rate-pill.is-rx {
  border-left: 2px solid var(--et-cyan);
}
.et-rate-pill.is-rx .et-rate-icon {
  color: var(--et-cyan);
}

.et-rate-label {
  font-size: 0.65rem;
  font-weight: 600;
  color: var(--et-text-tertiary);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  line-height: 1;
}

.et-rate-num {
  font-size: 0.78rem;
  font-weight: 700;
  line-height: 1.2;
}

.et-peak-pill {
  font-size: 0.7rem;
  background: var(--et-surface-2);
  padding: 3px 8px;
  border-radius: 999px;
  border: 1px solid var(--et-border-hairline);
}

.et-canvas-container {
  position: relative;
  width: 100%;
}
</style>
