<script setup lang="ts">
import { computed, watch, onMounted, ref } from 'vue';
import type { Mode, ServiceMode, RemoteMode, NormalMode } from '~/composables/mode';
import { appConfigDir, appLogDir } from '@tauri-apps/api/path';
import { join } from '@tauri-apps/api/path';
import { getServiceStatus, type ServiceStatus } from '~/composables/backend';

const { t } = useI18n()

const model = defineModel<Mode>({ required: true })
const emit = defineEmits(['uninstall-service', 'stop-service'])

const defaultConfigDir = ref('')
const defaultLogDir = ref('')
const serviceStatus = ref<ServiceStatus>('NotInstalled')
const isServiceStatusLoaded = ref(false)

function normalizeRpcListenPort(port: unknown): number {
  const defaultPort = 15999
  const numericPort = typeof port === 'number' ? port : Number.parseInt(String(port ?? ''), 10)
  if (Number.isNaN(numericPort))
    return defaultPort
  return Math.min(65535, Math.max(1, Math.floor(numericPort)))
}

onMounted(async () => {
  defaultConfigDir.value = await join(await appConfigDir(), 'config.d')
  defaultLogDir.value = await appLogDir()
})

const modeOptions = computed(() => [
  { label: t('mode.normal'), value: 'normal' },
  { label: t('mode.service'), value: 'service' },
  { label: t('mode.remote'), value: 'remote' },
]);

const normalMode = computed({
  get: () => model.value.mode === 'normal' ? model.value as NormalMode : undefined,
  set: (value) => {
    if (value) {
      model.value = value
    }
  }
})

const rpcListenOptions = computed(() => [
  { label: t('web.common.disable'), value: false },
  { label: t('web.common.enable'), value: true },
])

const rpcListenEnabled = computed<boolean>({
  get: () => !!normalMode.value?.enable_rpc_port_listen,
  set: (value) => {
    if (!normalMode.value)
      return
    normalMode.value.enable_rpc_port_listen = value
  },
})

const rpcListenPort = computed<string>({
  get: () => String(normalMode.value?.rpc_listen_port ?? 15999),
  set: (value) => {
    if (!normalMode.value)
      return
    const trimmed = value.trim()
    if (trimmed === '')
      return
    if (!/^\d+$/.test(trimmed))
      return
    normalMode.value.rpc_listen_port = Number.parseInt(trimmed, 10)
  },
})

const serviceMode = computed({
  get: () => model.value.mode === 'service' ? model.value as ServiceMode : undefined,
  set: (value) => {
    if (value) {
      model.value = value
    }
  }
})

const remoteMode = computed({
  get: () => model.value.mode === 'remote' ? model.value as RemoteMode : undefined,
  set: (value) => {
    if (value) {
      model.value = value
    }
  }
})

const statusColor = computed(() => {
  switch (serviceStatus.value) {
    case 'Running':
      return 'success'
    case 'Stopped':
      return 'warning'
    case 'NotInstalled':
      return 'grey'
    default:
      return 'grey'
  }
})

watch(() => [normalMode.value?.enable_rpc_port_listen, normalMode.value?.rpc_listen_port], ([enabled, port]) => {
  if (!normalMode.value)
    return

  if (!enabled) {
    normalMode.value.rpc_portal = undefined
    return
  }

  const normalizedPort = normalizeRpcListenPort(port)
  if (normalMode.value.rpc_listen_port !== normalizedPort)
    normalMode.value.rpc_listen_port = normalizedPort

  const desiredPortal = `tcp://0.0.0.0:${normalizedPort}`
  if (normalMode.value.rpc_portal !== desiredPortal)
    normalMode.value.rpc_portal = desiredPortal
}, { immediate: true })

watch(() => model.value.mode, async (newMode, oldMode) => {
  if (newMode === oldMode)
    return

  if (newMode === 'service' && !isServiceStatusLoaded.value) {
    serviceStatus.value = await getServiceStatus()
    isServiceStatusLoaded.value = true
  }

  const oldModelValue = { ...model.value }

  if (newMode === 'normal') {
    const portal = normalMode.value?.rpc_portal?.trim()
    model.value = {
      ...oldModelValue,
      rpc_portal: portal || undefined,
      enable_rpc_port_listen: normalMode.value?.enable_rpc_port_listen,
      rpc_listen_port: normalMode.value?.rpc_listen_port,
      mode: 'normal',
    }
  }
  else if (newMode === 'service') {
    model.value = {
      ...oldModelValue,
      mode: 'service',
      config_dir: serviceMode.value?.config_dir || defaultConfigDir.value,
      rpc_portal: serviceMode.value?.rpc_portal || '127.0.0.1:15999',
      file_log_level: serviceMode.value?.file_log_level || 'off',
      file_log_dir: serviceMode.value?.file_log_dir || defaultLogDir.value,
    }
  }
  else if (newMode === 'remote') {
    model.value = {
      ...oldModelValue,
      mode: 'remote',
      remote_rpc_address: remoteMode.value?.remote_rpc_address || 'tcp://127.0.0.1:15999',
    }
  }
}, { immediate: true })

</script>

<template>
  <div class="d-flex flex-column ga-4">
    <div>
      <v-btn-toggle
        id="mode-select"
        :model-value="model.mode"
        density="comfortable"
        divided
        color="primary"
        class="w-100"
        @update:model-value="model.mode = $event"
      >
        <v-btn v-for="opt in modeOptions" :key="opt.value" :value="opt.value" class="flex-grow-1">
          {{ opt.label }}
        </v-btn>
      </v-btn-toggle>
    </div>

    <!-- Mode descriptions -->
    <div v-if="model.mode === 'normal'" class="text-body-2 text-medium-emphasis">
      {{ t('mode.normal_description') }}
    </div>
    <div v-else-if="model.mode === 'service'" class="text-body-2 text-medium-emphasis">
      {{ t('mode.service_description') }}
    </div>
    <div v-else-if="model.mode === 'remote'" class="text-body-2 text-medium-emphasis">
      {{ t('mode.remote_description') }}
    </div>

    <div v-if="normalMode" class="d-flex flex-column ga-3">
      <div class="d-flex align-center ga-3 flex-wrap">
        <label for="rpc-listen-toggle" class="mode-label">{{ t('mode.enable_rpc_tcp_listen') }}</label>
        <v-btn-toggle
          id="rpc-listen-toggle"
          :model-value="rpcListenEnabled"
          density="comfortable"
          divided
          color="primary"
          @update:model-value="rpcListenEnabled = !!$event"
        >
          <v-btn v-for="opt in rpcListenOptions" :key="String(opt.value)" :value="opt.value">
            {{ opt.label }}
          </v-btn>
        </v-btn-toggle>
      </div>
      <div v-if="rpcListenEnabled" class="d-flex flex-column ga-2">
        <div class="d-flex align-center ga-2">
          <label for="rpc-listen-port" class="mode-label">{{ t('mode.rpc_listen_port') }}</label>
          <v-text-field id="rpc-listen-port" v-model="rpcListenPort" inputmode="numeric" variant="outlined" density="compact" hide-details class="flex-grow-1" />
        </div>
      </div>
    </div>

    <div v-if="serviceMode" class="d-flex flex-column ga-3">
      <div class="d-flex align-center ga-2">
        <label for="config-dir" class="mode-label">{{ t('mode.config_dir') }}</label>
        <v-text-field id="config-dir" v-model="serviceMode.config_dir" variant="outlined" density="compact" hide-details class="flex-grow-1" />
      </div>
      <div class="d-flex align-center ga-2">
        <label for="rpc-portal" class="mode-label">{{ t('mode.rpc_portal') }}</label>
        <v-text-field id="rpc-portal" v-model="serviceMode.rpc_portal" variant="outlined" density="compact" hide-details class="flex-grow-1" />
      </div>
      <div class="d-flex align-center ga-2">
        <label for="log-level" class="mode-label">{{ t('mode.log_level') }}</label>
        <v-select
          id="log-level"
          v-model="serviceMode.file_log_level"
          :items="['off', 'warn', 'info', 'debug', 'trace']"
          variant="outlined"
          density="compact"
          hide-details
          class="mode-select"
        />
      </div>
      <div class="d-flex align-center ga-2">
        <label for="log-dir" class="mode-label">{{ t('mode.log_dir') }}</label>
        <v-text-field id="log-dir" v-model="serviceMode.file_log_dir" variant="outlined" density="compact" hide-details class="flex-grow-1" />
      </div>
      <div class="d-flex align-center justify-space-between flex-wrap">
        <div class="d-flex align-center ga-2">
          <label class="mode-label">{{ t('mode.service_status') }}</label>
          <span :color="statusColor" class="font-weight-medium" :class="`text-${statusColor}`">{{ t(`mode.service_status_${serviceStatus.toLowerCase()}`) }}</span>
        </div>
        <div class="d-flex align-center ga-2">
          <v-btn v-if="serviceStatus === 'Running'" variant="text" color="warning" :prepend-icon="'mdi-stop-circle-outline'" @click="emit('stop-service')">
            {{ t('mode.stop_service') }}
          </v-btn>
          <v-btn v-if="serviceStatus !== 'NotInstalled'" variant="text" color="error" :prepend-icon="'mdi-trash-can-outline'" @click="emit('uninstall-service')">
            {{ t('mode.uninstall_service') }}
          </v-btn>
        </div>
      </div>
    </div>

    <div v-if="remoteMode" class="d-flex flex-column ga-2">
      <div class="d-flex align-center ga-2">
        <label for="remote-addr" class="mode-label">{{ t('mode.remote_rpc_address') }}</label>
        <v-text-field id="remote-addr" v-model="remoteMode.remote_rpc_address" variant="outlined" density="compact" hide-details class="flex-grow-1" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.mode-label {
  white-space: nowrap;
  color: var(--v-theme-onSurface);
}
.mode-select {
  max-width: 14rem;
}
</style>
