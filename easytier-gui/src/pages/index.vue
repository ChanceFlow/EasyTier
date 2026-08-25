<script setup lang="ts">

import { type } from '@tauri-apps/plugin-os'

import { invoke } from '@tauri-apps/api/core'
import { writeText } from '@tauri-apps/plugin-clipboard-manager'
import { open } from '@tauri-apps/plugin-shell'
import { exit } from '@tauri-apps/plugin-process'
import { I18nUtils, RemoteManagement, Utils } from "easytier-frontend-lib"
import { useTray } from '~/composables/tray'
import { initMobileVpnService, syncMobileVpnService } from '~/composables/mobile_vpn'
import { GUIRemoteClient } from '~/modules/api'

import { loadMode, saveMode, WebClientConfig, type Mode } from '~/composables/mode'
import { saveLastNetworkInstanceId, loadLastNetworkInstanceId } from '~/composables/config'
import ModeSwitcher from '~/components/ModeSwitcher.vue'
import { getEasytierVersion, getServiceStatus } from '~/composables/backend'
import { useDisplay } from 'vuetify'

const { t, locale } = useI18n()
// 移动端(小屏)弹窗全屏展示
const { smAndDown: mobileUI } = useDisplay()
const aboutVisible = ref(false)
const modeDialogVisible = ref(false)
const currentMode = ref<Mode>({ mode: 'normal' })
const editingMode = ref<Mode>({ mode: 'normal' })
const isModeSaving = ref(false)
const manualDisconnect = ref(false)

const configServerDialogVisible = ref(false)
const configServerConnected = ref(false)

// ---- Vuetify toast/snackbar ----
const snackbar = ref(false)
const snackbarMessage = ref('')
const snackbarColor = ref('success')

function toast(message: string, severity: 'success' | 'error' | 'info' = 'success', life = 3000) {
  snackbarMessage.value = message
  snackbarColor.value = severity
  snackbar.value = true
}

// ---- Confirm dialog ----
const confirmDialog = ref(false)
const confirmMessage = ref('')
const confirmHeader = ref('')
let confirmCallback: (() => void) | null = null

function requireConfirm(message: string, header: string, callback: () => void) {
  confirmMessage.value = message
  confirmHeader.value = header
  confirmCallback = callback
  confirmDialog.value = true
}
function confirmAccept() {
  confirmDialog.value = false
  confirmCallback?.()
  confirmCallback = null
}

async function openModeDialog() {
  editingMode.value = JSON.parse(JSON.stringify(loadMode()))
  modeDialogVisible.value = true
}

async function onModeSave() {
  if (isModeSaving.value) {
    return;
  }
  isModeSaving.value = true
  try {
    await initWithMode(editingMode.value);
    modeDialogVisible.value = false
  }
  catch (e: any) {
    toast(t('error') + ': ' + e, 'error', 10000)
    console.error("Error switching mode", e, currentMode.value, editingMode.value)
    await initWithMode(currentMode.value);
  }
  finally {
    isModeSaving.value = false
  }
}

async function onUninstallService() {
  requireConfirm(t('mode.uninstall_service_confirm'), t('mode.uninstall_service'), async () => {
    isModeSaving.value = true
    try {
      await initWithMode({ ...currentMode.value, mode: 'normal' });
      await initService(undefined)
      toast(t('web.common.success'), 'success')
      modeDialogVisible.value = false
    } catch (e: any) {
      toast(t('error') + ': ' + e, 'error', 10000)
      console.error("Error uninstalling service", e)
    } finally {
      isModeSaving.value = false
    }
  });
}

function stripModeMetadata(mode: Mode) {
  if (mode.mode !== 'service') {
    return mode
  }

  const serviceConfig = { ...mode }
  delete serviceConfig.installed_core_version
  return serviceConfig
}

function modeConfigChanged(next: Mode) {
  return JSON.stringify(stripModeMetadata(next)) !== JSON.stringify(stripModeMetadata(currentMode.value))
}

async function onStopService() {
  isModeSaving.value = true
  manualDisconnect.value = true
  try {
    await setServiceStatus(false)
    toast(t('web.common.success'))
    modeDialogVisible.value = false
  }
  catch (e: any) {
    toast(t('error') + ': ' + e, 'error', 10000)
    console.error("Error stopping service", e)
  }
  finally {
    isModeSaving.value = false
  }
}

async function initWithMode(mode: Mode) {
  const running_inst_ids = (await remoteClient.value.list_network_instance_ids().catch(() => undefined))?.running_inst_ids ?? []

  if (currentMode.value.mode === 'service' && mode.mode !== 'service') {
    let serviceStatus = await getServiceStatus()
    if (serviceStatus === "Running") {
      manualDisconnect.value = true
      await setServiceStatus(false)
      serviceStatus = await getServiceStatus()
      for (let i = 0; i < 10; i++) { // macOS takes a while to stop the service
        if (serviceStatus === "Stopped") {
          break;
        }
        await new Promise(resolve => setTimeout(resolve, 100))
        serviceStatus = await getServiceStatus()
      }
    }
    if (serviceStatus === "Stopped") {
      await initService(undefined)
    }
  }

  let url: string | undefined = undefined
  let retrys = 1
  switch (mode.mode) {
    case 'remote':
      if (!mode.remote_rpc_address) {
        toast(t('error') + ': ' + t('mode.remote_rpc_address_empty'), 'error', 10000)
        return initWithMode({ ...mode, mode: 'normal' });
      }
      url = mode.remote_rpc_address
      break;
    case 'service': {
      if (!mode.config_dir || !mode.file_log_dir || !mode.file_log_level || !mode.rpc_portal) {
        toast(t('error') + ': ' + t('mode.service_config_empty'), 'error', 10000)
        return initWithMode({ ...mode, mode: 'normal' });
      }
      let serviceStatus = await getServiceStatus()
      const coreVersion = await getEasytierVersion()
      if (serviceStatus === "NotInstalled" || modeConfigChanged(mode) || mode.installed_core_version !== coreVersion) {
        mode.config_server_url = mode.config_server_url || undefined
        await initService({
          config_dir: mode.config_dir,
          file_log_dir: mode.file_log_dir,
          file_log_level: mode.file_log_level,
          rpc_portal: mode.rpc_portal,
          config_server: mode.config_server_url,
        })
        mode.installed_core_version = coreVersion
        serviceStatus = await getServiceStatus()
      }
      if (serviceStatus === "Stopped") {
        await setServiceStatus(true)
      }
      url = "tcp://" + mode.rpc_portal.replace("0.0.0.0", "127.0.0.1")
      retrys = 5
      break;
    }
    case 'normal':
      url = mode.rpc_portal;
      break;
  }
  for (let i = 0; i < retrys; i++) {
    try {
      await connectRpcClient(mode.mode === 'normal', url)
      break;
    } catch (e) {
      if (i === retrys - 1) {
        const errMsg = e instanceof Error ? e.message : String(e)
        toast(t('error') + ': ' + t('mode.rpc_connection_failed', { error: errMsg }), 'error', 1000)
        throw e;
      }
      console.error("Error connecting rpc client, retrying...", e)
      await new Promise(resolve => setTimeout(resolve, 1000))
    }
  }
  await sendConfigs(running_inst_ids.map(Utils.UuidToStr))
  if (mode.mode === 'normal') {
    mode.config_server_url = mode.config_server_url || undefined
    initWebClient(mode.config_server_url)
  }
  currentMode.value = mode
  saveMode(mode)
  clientRunning.value = await isClientRunning()
}

// Registered synchronously (not after an await inside onMounted) so the
// lifecycle hook is bound to the component instance.
const cleanupFns: Array<() => void> = []
onUnmounted(() => {
  cleanupFns.forEach(unlisten => unlisten())
})

onMounted(async () => {
  if (type() === 'android') {
    try {
      await initMobileVpnService()
    } catch (e: any) {
      console.error("easytier init vpn service failed", e)
    }
  }

  cleanupFns.push(await listenGlobalEvents())
  currentMode.value = loadMode()
  await initWithMode(currentMode.value);

  if (type() === 'android') {
    try {
      await syncMobileVpnService()
    } catch (e: any) {
      console.error("easytier sync vpn service failed", e)
    }
  }
});

useTray(true)

const remoteClient = computed(() => new GUIRemoteClient());
const instanceId = ref<string | undefined>(undefined);
const clientRunning = ref(false);

watch(instanceId, (newVal) => {
  if (newVal) {
    saveLastNetworkInstanceId(newVal);
  }
});

watch(clientRunning, async (newVal, oldVal) => {
  if (!newVal && oldVal) {
    if (manualDisconnect.value) {
      manualDisconnect.value = false
      return
    }
    await reconnectClient()
  } else if (newVal && !oldVal) {
    const lastInstanceId = loadLastNetworkInstanceId();
    if (lastInstanceId) {
      instanceId.value = lastInstanceId;
    }
  }
})

onMounted(async () => {
  const timer = setInterval(async () => {
    try {
      clientRunning.value = await isClientRunning()
    } catch (e) {
      clientRunning.value = false
      console.error("Error checking client running status", e)
    }
  }, 1000)

  onUnmounted(() => {
    clearInterval(timer)
  })

  clientRunning.value = await isClientRunning().catch(() => false)
})
async function reconnectClient() {
  editingMode.value = JSON.parse(JSON.stringify(loadMode()));
  await onModeSave()
}

onMounted(async () => {
  window.setTimeout(async () => {
    await setTrayMenu([
      await MenuItemShow(t('tray.show')),
      await MenuItemExit(t('tray.exit')),
    ])
  }, 1000)
})

let current_log_level = 'off'

// 从后端获取正确的日志路径
async function getLogDirPath(): Promise<string> {
  return await invoke<string>('get_log_dir_path')
}

const logMenuOpen = ref(false)
const logMenuItems: { key: string, label: string, command: () => void }[] = [
  ...(['off', 'warn', 'info', 'debug', 'trace'].map(level => ({
    key: 'level_' + level,
    label: t(`logging_level_${level}`) + (current_log_level === level ? ' ✓' : ''),
    command: async () => {
      current_log_level = level
      await setLoggingLevel(level)
    },
  }))),
  {
    key: 'separator',
    label: '---',
    command: () => {},
  },
  {
    key: 'open_dir',
    label: t('logging_open_dir'),
    command: async () => {
      await open(await getLogDirPath())
    },
  },
  {
    key: 'copy_dir',
    label: t('logging_copy_dir'),
    command: async () => {
      await writeText(await getLogDirPath())
    },
  },
]

const logMenuFiltered = computed(() => {
  if (type() === 'android') {
    return logMenuItems.filter(item => item.key !== 'open_dir')
  }
  return logMenuItems
})

const settingsMenuOpen = ref(false)
const settingsMenuItems = computed(() => [
  {
    key: 'language',
    label: t('exchange_language'),
    icon: 'mdi-translate',
    command: async () => {
      await I18nUtils.loadLanguageAsync((locale.value === 'en' ? 'cn' : 'en'))
      await setTrayMenu([
        await MenuItemShow(t('tray.show')),
        await MenuItemExit(t('tray.exit')),
      ])
    },
  },
  {
    key: 'mode',
    label: `${t('mode.switch_mode')}: ${t('mode.' + currentMode.value.mode)}`,
    icon: 'mdi-sync',
    command: openModeDialog,
    visible: () => type() !== 'android',
  },
  {
    key: 'config-server',
    label: `${t('config-server.title')}${t('config-server.' + configServerConnectionStatus.value)}`,
    icon: 'mdi-web',
    command: openConfigServerDialog,
    visible: () => ["normal", "service"].includes(currentMode.value.mode),
  },
  {
    key: 'logging',
    label: t('logging'),
    icon: 'mdi-file-document',
    items: logMenuItems,
    visible: () => true,
  },
  {
    key: 'about',
    label: t('about.title'),
    icon: 'mdi-at',
    command: async () => {
      aboutVisible.value = true
    },
  },
  {
    key: 'exit',
    label: t('exit'),
    icon: 'mdi-power',
    command: async () => {
      await exit(1)
    },
  },
])

async function connectRpcClient(isNormalMode: boolean, url?: string) {
  await initRpcConnection(isNormalMode, url)
  console.log("easytier rpc connection established, isNormalMode: ", isNormalMode)
}

async function openConfigServerDialog() {
  editingMode.value = JSON.parse(JSON.stringify(loadMode()))
  configServerDialogVisible.value = true
}
async function onConfigServerSave() {
  if (JSON.stringify(currentMode.value) === JSON.stringify(editingMode.value)) {
    configServerDialogVisible.value = false
    return;
  }
  if (editingMode.value.mode === 'service') {
    await new Promise<void>((resolve, reject) => {
      requireConfirm(t('config-server.update_service_confirm'), t('config-server.title'), () => {
        resolve()
      })
      // if dialog dismissed without accept, reject
      const stopWatch = watch(confirmDialog, (val) => {
        if (!val && confirmCallback === null) {
          reject()
          stopWatch()
        }
      })
    })
  }
  console.log("Saving config server url", (editingMode.value as WebClientConfig).config_server_url)
  await onModeSave();
  configServerDialogVisible.value = false
}
onMounted(() => {
  const timer = setInterval(async () => {
    if (currentMode.value.mode !== 'normal') return;
    if (!currentMode.value.config_server_url) return;
    configServerConnected.value = await isWebClientConnected();
  }, 1000)

  onUnmounted(() => {
    clearInterval(timer)
  })
})
const configServerConnectionStatus = computed(() => {
  if (currentMode.value.mode !== 'normal') {
    return 'unknown'
  }
  if (!currentMode.value.config_server_url) {
    return 'disconnected'
  }
  return configServerConnected.value ? 'connected' : 'connecting'
})

// --- mobile-first nav ---

function runSettingsAction(item: any) {
  settingsMenuOpen.value = false
  if (item.items) {
    // submenu (logging)
    logMenuOpen.value = true
    return
  }
  item.command?.()
}

</script>

<template>
  <div id="root" class="ios-app-root">
    <!-- iOS App Navigation Bar -->
    <header class="ios-nav-bar d-flex align-center justify-space-between px-3">
      <div class="d-flex align-center ga-2">
        <div class="ios-squircle bg-primary">
          <v-icon size="18" color="white">mdi-shield-outline</v-icon>
        </div>
        <span class="ios-nav-title">EasyTier</span>
      </div>

      <div class="d-flex align-center ga-1">
        <!-- Status Indicator Pill -->
        <div
          v-if="clientRunning"
          class="ios-status-pill pill-online d-flex align-center ga-1 px-2 py-1"
        >
          <div class="status-pulse-dot"></div>
          <span>{{ t('network_running') }}</span>
        </div>
        <div
          v-else
          class="ios-status-pill pill-offline d-flex align-center ga-1 px-2 py-1"
        >
          <v-icon size="12">mdi-wifi-off</v-icon>
          <span>{{ t('client.not_running') }}</span>
        </div>

        <!-- Language switcher -->
        <v-btn icon="mdi-translate" variant="text" size="small" @click="I18nUtils.toggleLanguage" />

        <!-- Settings menu -->
        <v-menu v-model="settingsMenuOpen" location="bottom end">
          <template #activator="{ props: menuProps }">
            <v-btn icon="mdi-dots-horizontal-circle-outline" v-bind="menuProps" variant="text" size="small" />
          </template>
          <v-list density="comfortable" min-width="220" rounded="xl" class="ios-menu-list">
            <template v-for="item in settingsMenuItems" :key="item.key">
              <v-divider v-if="item.key === 'exit' && item.visible?.()" class="my-1" />
              <v-list-item
                v-if="(item.visible === undefined || item.visible()) && item.key !== 'logging'"
                :prepend-icon="item.icon"
                @click="runSettingsAction(item)"
              >
                <v-list-item-title>{{ item.label }}</v-list-item-title>
              </v-list-item>
              <!-- Logging submenu item (opens log menu) -->
              <v-list-item v-if="(item.visible === undefined || item.visible()) && item.key === 'logging'">
                <v-list-item-title>
                  <v-menu v-model="logMenuOpen" location="end" open-on-hover>
                    <template #activator="{ props: subProps }">
                      <span v-bind="subProps" class="d-flex align-center justify-space-between">
                        <span><v-icon start :icon="item.icon" size="small" />{{ item.label }}</span>
                        <v-icon size="small">mdi-chevron-right</v-icon>
                      </span>
                    </template>
                    <v-list density="comfortable" min-width="180" rounded="xl">
                      <v-list-item
                        v-for="sub in logMenuFiltered"
                        :key="sub.key"
                        @click="sub.command()"
                      >
                        <v-list-item-title>{{ sub.label }}</v-list-item-title>
                      </v-list-item>
                    </v-list>
                  </v-menu>
                </v-list-item-title>
              </v-list-item>
            </template>
          </v-list>
        </v-menu>
      </div>
    </header>

    <!-- Dialogs -->
    <v-dialog v-model="aboutVisible" max-width="480px" :fullscreen="mobileUI">
      <v-card rounded="xl" class="ios-dialog-card">
        <v-card-text class="pt-4"><About /></v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="aboutVisible = false">{{ t('close') }}</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="modeDialogVisible" max-width="540px" :fullscreen="mobileUI">
      <v-card :title="t('mode.switch_mode')" rounded="xl" class="ios-dialog-card">
        <v-card-text>
          <ModeSwitcher v-model="editingMode" @uninstall-service="onUninstallService" @stop-service="onStopService" />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="modeDialogVisible = false">{{ t('web.common.cancel') }}</v-btn>
          <v-btn color="primary" variant="flat" rounded="pill" :prepend-icon="'mdi-content-save'" :loading="isModeSaving" @click="onModeSave">
            {{ t('web.common.save') }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="configServerDialogVisible" max-width="540px" :fullscreen="mobileUI">
      <v-card :title="t('config-server.title')" rounded="xl" class="ios-dialog-card">
        <v-card-text>
          <div class="d-flex flex-column ga-3">
            <label for="config-server-address" class="text-caption font-weight-medium">{{ t('config-server.address') }}</label>
            <v-text-field
              id="config-server-address"
              v-model="(editingMode as WebClientConfig).config_server_url"
              variant="outlined"
              density="compact"
              hide-details
              :placeholder="t('config-server.address_placeholder')"
            />
            <small class="text-medium-emphasis config-server-desc">{{ t('config-server.description') }}</small>
          </div>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="configServerDialogVisible = false">{{ t('web.common.cancel') }}</v-btn>
          <v-btn color="primary" variant="flat" rounded="pill" :prepend-icon="'mdi-content-save'" :loading="isModeSaving" @click="onConfigServerSave">
            {{ t('web.common.save') }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Main App Body -->
    <main class="ios-main-wrap">
      <div class="ios-main-body">
        <RemoteManagement
          v-if="clientRunning"
          class="fill-height"
          :api="remoteClient"
          :pause-auto-refresh="isModeSaving"
          v-model:instance-id="instanceId"
        />
        <div v-else class="empty-state fill-height d-flex flex-column align-center justify-center py-12">
          <v-icon size="56" class="mb-4 empty-icon">mdi-server-network-off</v-icon>
          <div class="text-h6 text-center font-weight-bold mb-3">{{ t('client.not_running') }}</div>
          <v-btn color="primary" variant="flat" rounded="pill" :loading="isModeSaving" :prepend-icon="'mdi-replay'" @click="reconnectClient">
            {{ t('client.retry') }}
          </v-btn>
        </div>
      </div>
    </main>

    <!-- Confirm dialog -->
    <v-dialog v-model="confirmDialog" max-width="420px">
      <v-card :title="confirmHeader" rounded="xl" class="ios-dialog-card">
        <v-card-text>{{ confirmMessage }}</v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" color="secondary" @click="confirmDialog = false; confirmCallback = null">{{ t('web.common.cancel') }}</v-btn>
          <v-btn color="error" variant="flat" rounded="pill" @click="confirmAccept">{{ t('web.common.confirm') }}</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Snackbar (toast) -->
    <v-snackbar v-model="snackbar" :color="snackbarColor" timeout="2500" location="top" rounded="pill">
      {{ snackbarMessage }}
    </v-snackbar>
  </div>
</template>

<style scoped lang="postcss">
.ios-app-root {
  height: 100vh;
  width: 100vw;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background-color: var(--ios-bg);
}

.ios-nav-bar {
  height: calc(48px + env(safe-area-inset-top));
  padding-top: env(safe-area-inset-top);
  border-bottom: 1px solid var(--ios-border);
  backdrop-filter: blur(25px);
  -webkit-backdrop-filter: blur(25px);
  background: color-mix(in srgb, var(--ios-bg) 85%, transparent);
  flex-shrink: 0;
  z-index: 100;
}

.ios-nav-title {
  font-size: 1.0625rem;
  font-weight: 700;
  letter-spacing: -0.3px;
}

.ios-status-pill {
  font-size: 0.75rem;
  font-weight: 600;
  border-radius: 999px;
}

.pill-online {
  background: rgba(48, 209, 88, 0.15);
  color: var(--ios-green);
}

.pill-offline {
  background: var(--ios-surface-secondary);
  color: var(--ios-text-secondary);
}

.status-pulse-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background-color: var(--ios-green);
  animation: pulse-dot 1.5s ease-in-out infinite;
}

@keyframes pulse-dot {
  0% { transform: scale(0.85); opacity: 0.7; }
  50% { transform: scale(1.25); opacity: 1; }
  100% { transform: scale(0.85); opacity: 0.7; }
}

.ios-main-wrap {
  flex: 1;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.ios-main-body {
  flex: 1;
  overflow-y: auto;
  max-width: 540px;
  margin: 0 auto;
  width: 100%;
}

.ios-dialog-card {
  background-color: var(--ios-surface) !important;
}

.empty-icon {
  color: var(--ios-text-secondary);
  opacity: 0.5;
}

.config-server-desc {
  white-space: pre-wrap;
}
</style>

<style scoped lang="postcss">
#root {
  height: 100vh;
  width: 100vw;
  overflow: hidden;
  background: var(--v-theme-background);
}
.app-bar {
  height: 56px !important;
  padding-top: env(safe-area-inset-top);
  border-bottom: 1px solid rgba(var(--v-theme-outlineVariant), 0.25) !important;
  backdrop-filter: blur(20px);
}
.app-title-text {
  font-size: 1.125rem;
  font-weight: 700;
  letter-spacing: -0.2px;
}
.status-chip {
  max-width: 10rem;
}
.status-pulse-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background-color: #10b981;
  animation: pulse-dot 1.5s ease-in-out infinite;
}
@keyframes pulse-dot {
  0% { transform: scale(0.85); opacity: 0.7; }
  50% { transform: scale(1.2); opacity: 1; }
  100% { transform: scale(0.85); opacity: 0.7; }
}
.page-body-wrap {
  height: 100vh;
}
.page-body {
  height: calc(100vh - 56px);
  overflow-y: auto;
  max-width: 600px;
  margin: 0 auto;
  width: 100%;
  padding-top: 0.5rem;
}
.empty-icon {
  color: var(--v-theme-onSurfaceVariant);
  opacity: 0.5;
}
.config-server-desc {
  white-space: pre-wrap;
}
</style>

<style>
body {
  height: 100vh;
  width: 100vw;
  padding: 0;
  margin: 0;
  overflow: hidden;
}
</style>
