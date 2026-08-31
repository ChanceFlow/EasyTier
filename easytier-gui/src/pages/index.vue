<script setup lang="ts">
import type { loadMode, type Mode, saveMode, WebClientConfig } from '~/composables/mode'

import { invoke } from '@tauri-apps/api/core'
import { writeText } from '@tauri-apps/plugin-clipboard-manager'
import { type } from '@tauri-apps/plugin-os'
import { exit } from '@tauri-apps/plugin-process'
import { open } from '@tauri-apps/plugin-shell'
import { I18nUtils, RemoteManagement, Utils } from 'easytier-frontend-lib'
import { useDisplay, useTheme } from 'vuetify'
import MeshHero from '~/components/MeshHero.vue'
import ModeSwitcher from '~/components/ModeSwitcher.vue'
import OnboardingDialog from '~/components/OnboardingDialog.vue'
import { getEasytierVersion, getServiceStatus } from '~/composables/backend'
import { loadLastNetworkInstanceId, saveLastNetworkInstanceId } from '~/composables/config'

import { usePhoneText } from '~/composables/hero_text'
import { createHeroTransition } from '~/composables/hero_transition'
import { initMobileVpnService, mobileStats, setMobileStatsInstanceId, startMobileIoNotification, syncMobileVpnService } from '~/composables/mobile_vpn'
import { checkNotificationGate, notificationsBlocked, openNotificationSettings } from '~/composables/notification_gate'
import { initSysBarSync } from '~/composables/sysbar'
import { useTray } from '~/composables/tray'
import { GUIRemoteClient } from '~/modules/api'

const { t, locale } = useI18n()
const { pt } = usePhoneText()
const { smAndDown: mobileUI } = useDisplay()
const theme = useTheme()
const aboutVisible = ref(false)
const modeDialogVisible = ref(false)
const settingsSheetOpen = ref(false)
const logSheetOpen = ref(false)
const currentLogLevel = ref('off')
const currentMode = ref<Mode>({ mode: 'normal' })
const editingMode = ref<Mode>({ mode: 'normal' })
const isModeSaving = ref(false)
const manualDisconnect = ref(false)

// ---- phone hero / onboarding ----
const onboardingVisible = ref(false)
const heroBusy = ref(false)
// true once the very first isClientRunning() probe resolved
const heroBooted = ref(false)

const heroTransition = createHeroTransition({
  timeoutMs: 15000,
  onTimeout: (timedOutState) => {
    if (timedOutState === 'connecting') {
      mobileStats.lastError = pt('hero.timeout_error', '连接超时，未能建立隧道', 'Connection timed out, tunnel could not be established')
      toast(pt('hero.timeout_error', '连接超时，未能建立隧道', 'Connection timed out, tunnel could not be established'), 'error', 5000)
    }
    else {
      toast(pt('hero.disconnect_timeout', '断开连接超时', 'Disconnection timed out'), 'error', 5000)
    }
  },
})
const heroDesired = heroTransition.desired

watch(() => mobileStats.connected, (connected) => {
  const transitionEvent = heroTransition.handleConnectedChange(connected)
  if (transitionEvent === 'connected') {
    toast(pt('hero.connected_toast', '已接入网络', 'Connected to network'), 'success')
  }
  else if (transitionEvent === 'disconnected') {
    toast(pt('hero.disconnected_toast', '已断开网络', 'Disconnected from network'), 'info')
  }
})

watch(() => mobileStats.permissionDenied, (denied) => {
  if (denied) {
    heroTransition.reset()
  }
})

const configServerDialogVisible = ref(false)
const configServerConnected = ref(false)

// ---- Vuetify toast/snackbar ----
const snackbar = ref(false)
const snackbarMessage = ref('')
const snackbarColor = ref('success')

function toast(message: string, severity: 'success' | 'error' | 'info' = 'success', _life = 3000) {
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
    return
  }
  isModeSaving.value = true
  try {
    await initWithMode(editingMode.value)
    modeDialogVisible.value = false
  }
  catch (e: any) {
    toast(`${t('error')}: ${e}`, 'error', 10000)
    console.error('Error switching mode', e, currentMode.value, editingMode.value)
    await initWithMode(currentMode.value)
  }
  finally {
    isModeSaving.value = false
  }
}

async function onUninstallService() {
  requireConfirm(t('mode.uninstall_service_confirm'), t('mode.uninstall_service'), async () => {
    isModeSaving.value = true
    try {
      await initWithMode({ ...currentMode.value, mode: 'normal' })
      await initService(undefined)
      toast(t('web.common.success'), 'success')
      modeDialogVisible.value = false
    }
    catch (e: any) {
      toast(`${t('error')}: ${e}`, 'error', 10000)
      console.error('Error uninstalling service', e)
    }
    finally {
      isModeSaving.value = false
    }
  })
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
    toast(`${t('error')}: ${e}`, 'error', 10000)
    console.error('Error stopping service', e)
  }
  finally {
    isModeSaving.value = false
  }
}

async function initWithMode(mode: Mode) {
  const running_inst_ids = (await remoteClient.value.list_network_instance_ids().catch(() => undefined))?.running_inst_ids ?? []

  if (currentMode.value.mode === 'service' && mode.mode !== 'service') {
    let serviceStatus = await getServiceStatus()
    if (serviceStatus === 'Running') {
      manualDisconnect.value = true
      await setServiceStatus(false)
      serviceStatus = await getServiceStatus()
      for (let i = 0; i < 10; i++) { // macOS takes a while to stop the service
        if (serviceStatus === 'Stopped') {
          break
        }
        await new Promise(resolve => setTimeout(resolve, 100))
        serviceStatus = await getServiceStatus()
      }
    }
    if (serviceStatus === 'Stopped') {
      await initService(undefined)
    }
  }

  let url: string | undefined
  let retrys = 1
  switch (mode.mode) {
    case 'remote':
      if (!mode.remote_rpc_address) {
        toast(`${t('error')}: ${t('mode.remote_rpc_address_empty')}`, 'error', 10000)
        return initWithMode({ ...mode, mode: 'normal' })
      }
      url = mode.remote_rpc_address
      break
    case 'service': {
      if (!mode.config_dir || !mode.file_log_dir || !mode.file_log_level || !mode.rpc_portal) {
        toast(`${t('error')}: ${t('mode.service_config_empty')}`, 'error', 10000)
        return initWithMode({ ...mode, mode: 'normal' })
      }
      let serviceStatus = await getServiceStatus()
      const coreVersion = await getEasytierVersion()
      if (serviceStatus === 'NotInstalled' || modeConfigChanged(mode) || mode.installed_core_version !== coreVersion) {
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
      if (serviceStatus === 'Stopped') {
        await setServiceStatus(true)
      }
      url = `tcp://${mode.rpc_portal.replace('0.0.0.0', '127.0.0.1')}`
      retrys = 5
      break
    }
    case 'normal':
      url = mode.rpc_portal
      break
  }
  for (let i = 0; i < retrys; i++) {
    try {
      await connectRpcClient(mode.mode === 'normal', url)
      break
    }
    catch (e) {
      if (i === retrys - 1) {
        const errMsg = e instanceof Error ? e.message : String(e)
        toast(`${t('error')}: ${t('mode.rpc_connection_failed', { error: errMsg })}`, 'error', 1000)
        throw e
      }
      console.error('Error connecting rpc client, retrying...', e)
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
  // First-run intro: phone only, gated by a versioned localStorage flag.
  if (mobileUI.value && !localStorage.getItem('et_onboarded_v1')) {
    onboardingVisible.value = true
  }

  if (type() === 'android') {
    initSysBarSync(theme.global.name)
    void checkNotificationGate()
    try {
      await initMobileVpnService()
    }
    catch (e: any) {
      console.error('easytier init vpn service failed', e)
    }
  }
  // the shared 2s stats ticker feeds both the Android ongoing notification and
  // the phone hero (mobileStats); harmless on desktop where the hero is hidden
  startMobileIoNotification()

  cleanupFns.push(await listenGlobalEvents())
  currentMode.value = loadMode()
  await initWithMode(currentMode.value)

  if (type() === 'android') {
    try {
      await syncMobileVpnService()
    }
    catch (e: any) {
      console.error('easytier sync vpn service failed', e)
    }
  }
})

useTray(true)

const remoteClient = computed(() => new GUIRemoteClient())
const instanceId = ref<string | undefined>(undefined)
const clientRunning = ref(false)

watch(instanceId, (newVal) => {
  if (newVal) {
    saveLastNetworkInstanceId(newVal)
  }
  // let the shared stats ticker prefer the instance the UI is showing
  setMobileStatsInstanceId(newVal)
})

watch(clientRunning, async (newVal, oldVal) => {
  if (!newVal && oldVal) {
    if (manualDisconnect.value) {
      manualDisconnect.value = false
      return
    }
    await reconnectClient()
  }
  else if (newVal && !oldVal) {
    const lastInstanceId = loadLastNetworkInstanceId()
    if (lastInstanceId) {
      instanceId.value = lastInstanceId
    }
  }
})

onMounted(async () => {
  const timer = setInterval(async () => {
    try {
      clientRunning.value = await isClientRunning()
    }
    catch (e) {
      clientRunning.value = false
      console.error('Error checking client running status', e)
    }
  }, 1000)

  onUnmounted(() => {
    clearInterval(timer)
  })

  clientRunning.value = await isClientRunning().catch(() => false)
  heroBooted.value = true
})
async function reconnectClient() {
  editingMode.value = JSON.parse(JSON.stringify(loadMode()))
  await onModeSave()
}

// ---- phone hero actions (same chain as the existing desktop flows) ----
// the hero may show an instance discovered by the stats ticker even before
// the collapsed RemoteManagement panel has synced the v-model id
function heroInstanceId(): string | undefined {
  return instanceId.value || mobileStats.instanceId || undefined
}

async function heroConnect() {
  if (heroBusy.value || heroDesired.value !== 'idle') {
    return
  }
  const targetId = heroInstanceId()
  if (!clientRunning.value || !targetId) {
    // backend unreachable or nothing selected: reuse the retry path
    heroBusy.value = true
    try {
      await reconnectClient()
    }
    finally {
      heroBusy.value = false
    }
    return
  }
  heroBusy.value = true
  heroTransition.startConnecting()
  try {
    await remoteClient.value.update_network_instance_state(targetId, false)
    clientRunning.value = await isClientRunning()
  }
  catch (e: any) {
    heroTransition.reset()
    toast(`${t('error')}: ${e}`, 'error', 10000)
    console.error('hero connect failed', e)
  }
  finally {
    heroBusy.value = false
  }
}

async function heroDisconnect() {
  if (heroBusy.value || heroDesired.value !== 'idle') {
    return
  }
  const targetId = heroInstanceId()
  if (!targetId) {
    return
  }
  heroBusy.value = true
  heroTransition.startDisconnecting()
  try {
    await remoteClient.value.update_network_instance_state(targetId, true)
  }
  catch (e: any) {
    heroTransition.reset()
    toast(`${t('error')}: ${e}`, 'error', 10000)
    console.error('hero disconnect failed', e)
  }
  finally {
    heroBusy.value = false
  }
}

async function heroGrantVpn() {
  if (heroBusy.value) {
    return
  }
  heroBusy.value = true
  try {
    // re-runs the VPN reconcile, which re-asks for the system permission
    await syncMobileVpnService()
  }
  catch (e: any) {
    toast(`${t('error')}: ${e}`, 'error', 10000)
    console.error('hero vpn re-sync failed', e)
  }
  finally {
    heroBusy.value = false
  }
}

onMounted(async () => {
  window.setTimeout(async () => {
    await setTrayMenu([
      await MenuItemShow(t('tray.show')),
      await MenuItemExit(t('tray.exit')),
    ])
  }, 1000)
})

const isAndroid = computed(() => {
  try {
    return type() === 'android'
  }
  catch {
    return false
  }
})

const isDarkTheme = computed(() => theme.global.name.value === 'm3Dark')

function toggleTheme(): void {
  const next = isDarkTheme.value ? 'm3Light' : 'm3Dark'
  theme.global.name.value = next
  localStorage.setItem('et-theme', next)
}

const logLevels: Array<'off' | 'warn' | 'info' | 'debug' | 'trace'> = ['off', 'warn', 'info', 'debug', 'trace']

async function applyLogLevel(level: typeof logLevels[number]): Promise<void> {
  currentLogLevel.value = level
  await setLoggingLevel(level)
}

// 从后端获取正确的日志路径
async function getLogDirPath(): Promise<string> {
  return await invoke<string>('get_log_dir_path')
}

interface SettingsSheetItem {
  key: string
  label: string
  icon: string
  value: string
  command: () => void | Promise<void>
  visible?: boolean
}

const settingsSheetItems = computed<SettingsSheetItem[]>(() => [
  {
    key: 'language',
    label: t('exchange_language'),
    icon: 'mdi-translate',
    value: locale.value === 'en' ? 'EN' : '中文',
    command: async () => {
      await I18nUtils.loadLanguageAsync((locale.value === 'en' ? 'cn' : 'en'))
      await setTrayMenu([
        await MenuItemShow(t('tray.show')),
        await MenuItemExit(t('tray.exit')),
      ])
    },
  },
  {
    key: 'theme',
    label: t('status.appearance'),
    icon: 'mdi-theme-light-dark',
    value: isDarkTheme.value ? t('status.appearance_dark') : t('status.appearance_light'),
    command: toggleTheme,
  },
  {
    key: 'mode',
    label: t('mode.switch_mode'),
    icon: 'mdi-sync',
    value: t(`mode.${currentMode.value.mode}`),
    command: () => {
      settingsSheetOpen.value = false
      void openModeDialog()
    },
    visible: !isAndroid.value,
  },
  {
    key: 'config-server',
    label: t('config-server.title'),
    icon: 'mdi-web',
    value: t(`config-server.${configServerConnectionStatus.value}`).replace(/^:\s*/, ''),
    command: () => {
      settingsSheetOpen.value = false
      void openConfigServerDialog()
    },
    visible: ['normal', 'service'].includes(currentMode.value.mode),
  },
  {
    key: 'logging',
    label: t('logging'),
    icon: 'mdi-file-document',
    value: t(`logging_level_${currentLogLevel.value}`),
    command: () => { logSheetOpen.value = true },
  },
  {
    key: 'onboarding',
    label: pt('hero.replay_onboarding', '重看引导', 'Replay intro'),
    icon: 'mdi-school-outline',
    value: '',
    command: () => {
      settingsSheetOpen.value = false
      onboardingVisible.value = true
    },
    visible: mobileUI.value,
  },
])

async function openLogDir(): Promise<void> {
  await open(await getLogDirPath())
}

async function copyLogDir(): Promise<void> {
  await writeText(await getLogDirPath())
}

async function connectRpcClient(isNormalMode: boolean, url?: string) {
  await initRpcConnection(isNormalMode, url)
  console.log('easytier rpc connection established, isNormalMode: ', isNormalMode)
}

async function openConfigServerDialog() {
  editingMode.value = JSON.parse(JSON.stringify(loadMode()))
  configServerDialogVisible.value = true
}
async function onConfigServerSave() {
  if (JSON.stringify(currentMode.value) === JSON.stringify(editingMode.value)) {
    configServerDialogVisible.value = false
    return
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
  console.log('Saving config server url', (editingMode.value as WebClientConfig).config_server_url)
  await onModeSave()
  configServerDialogVisible.value = false
}
onMounted(() => {
  const timer = setInterval(async () => {
    if (currentMode.value.mode !== 'normal')
      return
    if (!currentMode.value.config_server_url)
      return
    configServerConnected.value = await isWebClientConnected()
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

function visibleSettingsItems(): SettingsSheetItem[] {
  return settingsSheetItems.value.filter((item: SettingsSheetItem) => item.visible !== false)
}

async function exitApp(): Promise<void> {
  await exit(1)
}
</script>

<template>
  <div id="root" class="et-app">
    <header class="et-nav">
      <div class="et-nav-inner">
        <div class="d-flex align-center ga-2 min-w-0">
          <div class="et-squircle" style="background: var(--et-accent);">
            <v-icon size="18" color="onPrimary">
              mdi-shield-outline
            </v-icon>
          </div>
          <span class="et-nav-title">EasyTier</span>
        </div>

        <div class="d-flex align-center ga-1">
          <div v-if="clientRunning" class="et-status-pill is-on">
            <div class="et-pulse-dot" />
            <span class="truncate">{{ t('status.connected') }}</span>
          </div>
          <div v-else class="et-status-pill is-off">
            <v-icon size="12">
              mdi-wifi-off
            </v-icon>
            <span class="truncate">{{ t('status.disconnected') }}</span>
          </div>
          <v-btn
            icon="mdi-cog-outline"
            variant="text"
            size="small"
            :aria-label="t('web.settings.title')"
            @click="settingsSheetOpen = true"
          />
        </div>
      </div>
    </header>

    <v-bottom-sheet v-model="settingsSheetOpen">
      <v-card class="et-sheet-card pb-4">
        <div class="sheet-grabber" />
        <v-card-title class="text-subtitle-1 font-weight-bold pt-1">
          {{ t('web.settings.title') }}
        </v-card-title>
        <v-card-text class="pt-2">
          <div class="et-group mb-3">
            <div
              v-for="item in visibleSettingsItems()"
              :key="item.key"
              class="et-row et-row-pressable"
              @click="item.command()"
            >
              <div class="d-flex align-center ga-3 min-w-0">
                <div class="et-squircle" style="background: var(--et-surface-2);">
                  <v-icon size="18" color="primary">
                    {{ item.icon }}
                  </v-icon>
                </div>
                <span class="font-weight-medium">{{ item.label }}</span>
              </div>
              <div class="d-flex align-center ga-1 flex-shrink-0">
                <span class="text-caption text-medium-emphasis">{{ item.value }}</span>
                <v-icon size="18" color="medium-emphasis">
                  mdi-chevron-right
                </v-icon>
              </div>
            </div>
          </div>

          <div class="et-group mb-3">
            <div class="et-row et-row-pressable" @click="aboutVisible = true; settingsSheetOpen = false">
              <div class="d-flex align-center ga-3">
                <div class="et-squircle" style="background: var(--et-surface-2);">
                  <v-icon size="18" color="primary">
                    mdi-information-outline
                  </v-icon>
                </div>
                <span class="font-weight-medium">{{ t('about.title') }}</span>
              </div>
              <v-icon size="18" color="medium-emphasis">
                mdi-chevron-right
              </v-icon>
            </div>
          </div>

          <v-btn
            block
            color="error"
            variant="tonal"
            size="large"
            rounded="pill"
            prepend-icon="mdi-power"
            @click="exitApp"
          >
            {{ t('exit') }}
          </v-btn>
        </v-card-text>
      </v-card>
    </v-bottom-sheet>

    <v-bottom-sheet v-model="logSheetOpen">
      <v-card class="et-sheet-card pb-4">
        <div class="sheet-grabber" />
        <v-card-title class="text-subtitle-1 font-weight-bold pt-1">
          {{ t('logging') }}
        </v-card-title>
        <v-card-text>
          <div class="et-group mb-3">
            <div
              v-for="level in logLevels"
              :key="level"
              class="et-row et-row-pressable"
              @click="applyLogLevel(level)"
            >
              <span class="font-weight-medium">{{ t(`logging_level_${level}`) }}</span>
              <v-icon v-if="currentLogLevel === level" color="primary" size="20">
                mdi-check
              </v-icon>
            </div>
          </div>
          <div class="et-group">
            <div v-if="!isAndroid" class="et-row et-row-pressable" @click="openLogDir">
              <span>{{ t('logging_open_dir') }}</span>
              <v-icon size="18" color="medium-emphasis">
                mdi-folder-open-outline
              </v-icon>
            </div>
            <div class="et-row et-row-pressable" @click="copyLogDir">
              <span>{{ t('logging_copy_dir') }}</span>
              <v-icon size="18" color="medium-emphasis">
                mdi-content-copy
              </v-icon>
            </div>
          </div>
        </v-card-text>
      </v-card>
    </v-bottom-sheet>

    <v-dialog v-model="aboutVisible" max-width="480px" :fullscreen="mobileUI">
      <v-card rounded="xl" class="et-dialog-card">
        <v-card-text class="pt-6">
          <About />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="aboutVisible = false">
            {{ t('close') }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="modeDialogVisible" max-width="540px" :fullscreen="mobileUI">
      <v-card :title="t('mode.switch_mode')" rounded="xl" class="et-dialog-card">
        <v-card-text>
          <ModeSwitcher v-model="editingMode" @uninstall-service="onUninstallService" @stop-service="onStopService" />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="modeDialogVisible = false">
            {{ t('web.common.cancel') }}
          </v-btn>
          <v-btn color="primary" variant="flat" rounded="pill" prepend-icon="mdi-content-save" :loading="isModeSaving" @click="onModeSave">
            {{ t('web.common.save') }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="configServerDialogVisible" max-width="540px" :fullscreen="mobileUI">
      <v-card :title="t('config-server.title')" rounded="xl" class="et-dialog-card">
        <v-card-text>
          <div class="d-flex flex-column ga-3">
            <label for="config-server-address" class="text-caption font-weight-medium">{{ t('config-server.address') }}</label>
            <v-text-field
              id="config-server-address"
              v-model="(editingMode as WebClientConfig).config_server_url"
              variant="outlined"
              hide-details
              :placeholder="t('config-server.address_placeholder')"
            />
            <small class="text-medium-emphasis config-server-desc">{{ t('config-server.description') }}</small>
          </div>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="configServerDialogVisible = false">
            {{ t('web.common.cancel') }}
          </v-btn>
          <v-btn color="primary" variant="flat" rounded="pill" prepend-icon="mdi-content-save" :loading="isModeSaving" @click="onConfigServerSave">
            {{ t('web.common.save') }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <main class="et-main">
      <div class="et-main-body">
        <!-- ================= phone: hero + collapsed advanced console ================= -->
        <template v-if="mobileUI">
          <MeshHero
            :client-running="clientRunning"
            :instance-id="instanceId"
            :busy="heroBusy || isModeSaving"
            :desired="heroDesired"
            :booted="heroBooted"
            :is-android="isAndroid"
            :notif-blocked="notificationsBlocked"
            @connect="heroConnect"
            @disconnect="heroDisconnect"
            @grant="heroGrantVpn"
            @retry="reconnectClient"
            @open-notif-settings="openNotificationSettings"
          />

          <div class="et-adv-wrap pb-6">
            <v-expansion-panels flat>
              <v-expansion-panel value="advanced" class="et-adv-panel">
                <v-expansion-panel-title>
                  <div class="d-flex align-center ga-3 min-w-0">
                    <div class="et-squircle" style="background: var(--et-surface-2);">
                      <v-icon size="16" color="primary">
                        mdi-console-network-outline
                      </v-icon>
                    </div>
                    <div class="min-w-0">
                      <div class="et-adv-title">
                        {{ pt('hero.advanced_console', '高级控制台', 'Advanced console') }}
                      </div>
                      <div class="et-adv-sub truncate">
                        {{ pt('hero.advanced_hint', '网络配置、节点详情与历史事件都在这里', 'Network config, node details and events live here') }}
                      </div>
                    </div>
                  </div>
                </v-expansion-panel-title>
                <v-expansion-panel-text>
                  <RemoteManagement
                    v-if="clientRunning"
                    v-model:instance-id="instanceId"
                    :api="remoteClient"
                    :pause-auto-refresh="isModeSaving"
                  />
                  <div v-else class="et-empty d-flex flex-column align-center justify-center">
                    <v-icon size="56" class="mb-4" color="medium-emphasis">
                      mdi-server-network-off
                    </v-icon>
                    <div class="text-h6 text-center font-weight-bold mb-3">
                      {{ t('client.not_running') }}
                    </div>
                    <v-btn color="primary" variant="flat" rounded="pill" :loading="isModeSaving" prepend-icon="mdi-replay" @click="reconnectClient">
                      {{ t('client.retry') }}
                    </v-btn>
                  </div>
                </v-expansion-panel-text>
              </v-expansion-panel>
            </v-expansion-panels>
          </div>
        </template>

        <!-- ============ desktop: full web console, unchanged path ============ -->
        <template v-else>
          <RemoteManagement
            v-if="clientRunning"
            v-model:instance-id="instanceId"
            class="fill-height"
            :api="remoteClient"
            :pause-auto-refresh="isModeSaving"
          />
          <div v-else class="et-empty d-flex flex-column align-center justify-center">
            <v-icon size="56" class="mb-4" color="medium-emphasis">
              mdi-server-network-off
            </v-icon>
            <div class="text-h6 text-center font-weight-bold mb-3">
              {{ t('client.not_running') }}
            </div>
            <v-btn color="primary" variant="flat" rounded="pill" :loading="isModeSaving" prepend-icon="mdi-replay" @click="reconnectClient">
              {{ t('client.retry') }}
            </v-btn>
          </div>
        </template>
      </div>
    </main>

    <OnboardingDialog v-model="onboardingVisible" />

    <v-dialog v-model="confirmDialog" max-width="420px">
      <v-card :title="confirmHeader" rounded="xl" class="et-dialog-card">
        <v-card-text>{{ confirmMessage }}</v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" color="secondary" @click="confirmDialog = false; confirmCallback = null">
            {{ t('web.common.cancel') }}
          </v-btn>
          <v-btn color="error" variant="flat" rounded="pill" @click="confirmAccept">
            {{ t('web.common.confirm') }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-snackbar v-model="snackbar" :color="snackbarColor" timeout="2500" location="top" rounded="pill">
      {{ snackbarMessage }}
    </v-snackbar>
  </div>
</template>

<style scoped>
.config-server-desc {
  white-space: pre-wrap;
}

.truncate {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* the collapsed "advanced console" disclosure under the phone hero */
.et-adv-wrap {
  padding: 0 16px;
}

.et-adv-panel {
  background: var(--et-surface) !important;
  border: 1px solid var(--et-border) !important;
  border-radius: var(--et-radius) !important;
}

.et-adv-title {
  font-size: 0.92rem;
  font-weight: 700;
  letter-spacing: -0.01em;
}

.et-adv-sub {
  font-size: 0.72rem;
  color: var(--et-text-secondary);
  margin-top: 1px;
}
</style>
