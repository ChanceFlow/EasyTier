<script setup lang="ts">
import { invoke } from '@tauri-apps/api/core'
import { writeText } from '@tauri-apps/plugin-clipboard-manager'
import { type } from '@tauri-apps/plugin-os'
import { exit } from '@tauri-apps/plugin-process'
import { open } from '@tauri-apps/plugin-shell'
import { I18nUtils, NetworkTypes, RemoteManagement, Utils } from 'easytier-frontend-lib'
import { useDisplay, useTheme } from 'vuetify'
import MeshHero from '~/components/MeshHero.vue'
import ModeSwitcher from '~/components/ModeSwitcher.vue'
import OnboardingDialog from '~/components/OnboardingDialog.vue'
import QuickNetworkDialog from '~/components/QuickNetworkDialog.vue'
import { getEasytierVersion, getServiceStatus, saveNetworkConfig } from '~/composables/backend'
import { loadLastNetworkInstanceId, saveLastNetworkInstanceId } from '~/composables/config'
import { usePhoneText } from '~/composables/hero_text'
import { createHeroTransition } from '~/composables/hero_transition'
import {
  consumePendingMobileVpnTileAction,
  initMobileVpnService,
  mobileStats,
  setMobileStatsInstanceId,
  setMobileVpnTileActionHandler,
  startMobileIoNotification,
  syncMobileVpnService,
} from '~/composables/mobile_vpn'
import { executeVpnTileAction } from '~/composables/mobile_vpn_tile'
import { loadMode, type Mode, saveMode, type WebClientConfig } from '~/composables/mode'
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

// ---- 导航 ----------------------------------------------------------------
// 移动端一级导航:首页 / 节点 / 配置 / 动态 / 设置。五项都是「目的地」,没有一项
// 是另一个页面的子视图。
//
// 「配置」曾经被降级成「网络详情」推入页,理由是它是 44 字段的专家表单、不该占
// 一级导航位。那条理由被推翻了:对 EasyTier 的用户(自建 mesh 的技术用户)来说配置
// 是一级需求而不是 1% 的会话,可发现性比导航预算的洁癖更重要;而 5 格本来就在
// 底部导航 3–5 的规范上限之内(见 design-system MASTER.md §6)。
// 于是配置回到页签,推入页整个删掉 —— 否则两个入口指向同一个表单。
const APP_TABS = [
  { id: 'mesh', labelKey: 'tabs.home', iconOn: 'mdi-shield', iconOff: 'mdi-shield-outline' },
  { id: 'devices', labelKey: 'tabs.devices', iconOn: 'mdi-devices', iconOff: 'mdi-devices' },
  { id: 'config', labelKey: 'tabs.config', iconOn: 'mdi-cog', iconOff: 'mdi-cog-outline' },
  { id: 'activity', labelKey: 'tabs.activity', iconOn: 'mdi-pulse', iconOff: 'mdi-chart-line' },
  { id: 'settings', labelKey: 'tabs.settings', iconOn: 'mdi-tune', iconOff: 'mdi-tune-variant' },
] as const
type AppTab = typeof APP_TABS[number]['id']
const appTab = ref<AppTab>('mesh')

// 桌面端没有底部导航(手机底部栏钉在桌面窗口底部、还会压住内容),改用顶栏
// 分段导航。四段与移动端的四个内容目的地一一对应,只是「首页」在这里是
// RemoteManagement 的 home 面板(桌面仪表盘),不是手机的 MeshHero。
const DESKTOP_TABS = [
  { id: 'home', labelKey: 'tabs.overview' },
  { id: 'devices', labelKey: 'tabs.devices' },
  { id: 'config', labelKey: 'tabs.config' },
  { id: 'activity', labelKey: 'tabs.activity' },
] as const
type DesktopPanel = typeof DESKTOP_TABS[number]['id']
const desktopPanel = ref<DesktopPanel>('home')

// 只有这四个 tab 交给 RemoteManagement 当面板渲染。写成 computed 而不是直接传
// appTab,是因为 AppTab 里还有 'mesh' / 'settings',而 RemoteManagement 的 panel
// 只接受 home/devices/config/activity —— 直接传过不了 vue-tsc。
const remotePanel = computed<'devices' | 'config' | 'activity'>(() => {
  if (appTab.value === 'config') {
    return 'config'
  }
  return appTab.value === 'activity' ? 'activity' : 'devices'
})

// tab 徽标与 Hero 用同一个数据源,避免两处数字打架
const peerBadgeCount = computed(() =>
  mobileStats.ready && mobileStats.connected ? mobileStats.peerCount : 0,
)

// declared up front: initWithMode and the hero actions reference them
const remoteClient = computed(() => new GUIRemoteClient())
const instanceId = ref<string | undefined>(undefined)
const clientRunning = ref(false)

// ---- phone hero / onboarding ----
const onboardingVisible = ref(false)
const createNetworkDialogVisible = ref(false)
const isCreatingNetwork = ref(false)
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
const snackbarTimeout = ref(3000)

function toast(message: string, severity: 'success' | 'error' | 'info' | 'warning' = 'success', life?: number) {
  snackbarMessage.value = message
  snackbarColor.value = severity
  // honor the caller's lifetime; errors get extra time by default so long
  // messages can be read (the snackbar also offers a manual close button)
  snackbarTimeout.value = life ?? (severity === 'error' ? 8000 : 3000)
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

const showAutostartHint = ref(false)

async function openModeDialog() {
  editingMode.value = JSON.parse(JSON.stringify(loadMode()))
  showAutostartHint.value = false
  modeDialogVisible.value = true
}

async function openAutostartDialog() {
  editingMode.value = JSON.parse(JSON.stringify(loadMode()))
  editingMode.value.mode = 'service'
  showAutostartHint.value = true
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
    setMobileVpnTileActionHandler(handleMobileVpnTileAction)
    cleanupFns.push(() => setMobileVpnTileActionHandler())
    try {
      await consumePendingMobileVpnTileAction()
      await syncMobileVpnService()
    }
    catch (e: any) {
      console.error('easytier sync vpn service failed', e)
    }
  }
})

useTray(true)

async function handleMobileVpnTileAction(action: 'start' | 'stop') {
  try {
    const result = await executeVpnTileAction(action, remoteClient.value, {
      lastInstanceId: loadLastNetworkInstanceId(),
      syncVpnService: syncMobileVpnService,
    })

    if (!result.instanceId) {
      toast(`${t('vpn_tile_no_network')}: ${t('vpn_tile_no_network_description')}`, 'warning', 5000)
      return
    }

    instanceId.value = result.instanceId
    saveLastNetworkInstanceId(result.instanceId)
    toast(
      t(action === 'start' ? 'vpn_tile_started' : 'vpn_tile_stopped'),
      action === 'start' ? 'success' : 'info',
      3000,
    )
  }
  catch (error) {
    console.error('VPN tile action failed', action, error)
    toast(`${t('error')}: ${t('vpn_tile_action_failed', { error: String(error) })}`, 'error', 8000)
  }
}

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
    if (typeof document !== 'undefined' && document.hidden) {
      return
    }
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

async function handleCreateNetwork(form: { name: string, secret: string, dhcp: boolean, peerUrl: string }) {
  if (isCreatingNetwork.value) {
    return
  }
  isCreatingNetwork.value = true
  try {
    const cfg = NetworkTypes.DEFAULT_NETWORK_CONFIG()
    cfg.network_name = form.name || 'easytier'
    cfg.network_secret = form.secret
    cfg.dhcp = form.dhcp
    if (form.peerUrl) {
      cfg.peer_urls = [form.peerUrl]
    }
    await saveNetworkConfig(cfg)
    instanceId.value = cfg.instance_id
    saveLastNetworkInstanceId(cfg.instance_id)
    setMobileStatsInstanceId(cfg.instance_id)
    toast(pt('hero.create_success', '网络已创建', 'Network created'), 'success')
    createNetworkDialogVisible.value = false
  }
  catch (e: any) {
    toast(`${t('error')}: ${e}`, 'error', 10000)
    console.error('Failed to create network', e)
  }
  finally {
    isCreatingNetwork.value = false
  }
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

const configServerConnectionStatus = computed(() => {
  if (currentMode.value.mode !== 'normal') {
    return 'unknown'
  }
  if (!currentMode.value.config_server_url) {
    return 'disconnected'
  }
  return configServerConnected.value ? 'connected' : 'connecting'
})

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
    // 上游 #2579:自启实际由服务模式提供,但设置里原来没有任何叫「开机自启」的入口,
    // 用户找不到。这里指到服务模式并带上说明。
    key: 'autostart',
    label: t('mode.autostart'),
    icon: 'mdi-clock-start',
    value: '',
    command: () => {
      settingsSheetOpen.value = false
      void openAutostartDialog()
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
          reject(new Error('cancelled from settings'))
          stopWatch()
        }
      })
    })
  }
  await onModeSave()
  configServerDialogVisible.value = false
}
onMounted(() => {
  const timer = setInterval(async () => {
    if (typeof document !== 'undefined' && document.hidden) {
      return
    }
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
function visibleSettingsItems(): SettingsSheetItem[] {
  return settingsSheetItems.value.filter((item: SettingsSheetItem) => item.visible !== false)
}

function exitApp(): void {
  // never quit on a single tap: the mesh may keep running in the background,
  // so require an explicit confirmation (Esc / back-out simply cancels).
  requireConfirm(
    t('exit_confirm_message', 'A running mesh may stay connected after EasyTier quits. Exit now?'),
    t('exit_confirm_title', 'Exit EasyTier'),
    () => {
      void exit(1)
    },
  )
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

        <!-- 桌面端导航:顶栏分段控件。原来这里没有导航 —— 桌面窗口底部钉着的是
             RemoteManagement 内建的手机 tab bar(position:fixed; bottom:0),
             它会压住内容,而且桌面本来就不该有底部页签。 -->
        <nav
          v-if="!mobileUI"
          class="et-seg"
          role="tablist"
          :aria-label="pt('tabs.label', '主导航', 'Main navigation')"
        >
          <button
            v-for="tab in DESKTOP_TABS"
            :key="tab.id"
            type="button"
            class="et-seg-item"
            role="tab"
            :aria-selected="desktopPanel === tab.id"
            :class="{ 'is-active': desktopPanel === tab.id }"
            @click="desktopPanel = tab.id"
          >
            {{ t(tab.labelKey) }}
          </button>
        </nav>

        <div class="d-flex align-center ga-1">
          <template v-if="!mobileUI">
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
              icon="mdi-theme-light-dark"
              variant="text"
              size="small"
              class="et-nav-btn"
              :aria-label="t('status.appearance')"
              @click="toggleTheme"
            />
            <v-btn
              icon="mdi-translate"
              variant="text"
              size="small"
              class="et-nav-btn"
              :aria-label="t('exchange_language')"
              @click="I18nUtils.loadLanguageAsync(locale === 'en' ? 'cn' : 'en')"
            />
          </template>
          <!-- 移动端不再有齿轮:设置是底部导航的一格,齿轮会变成第二个设置入口。
               桌面端没有底部导航,齿轮仍然是设置的唯一入口。 -->
          <v-btn
            v-if="!mobileUI"
            icon="mdi-cog-outline"
            variant="text"
            size="default"
            class="et-nav-btn"
            :aria-label="t('web.settings.title')"
            @click="settingsSheetOpen = true"
          />
        </div>
      </div>
    </header>

    <v-bottom-sheet v-model="settingsSheetOpen">
      <v-card class="et-sheet-card pb-4">
        <div class="sheet-grabber" aria-hidden="true" />
        <v-card-title class="text-subtitle-1 font-weight-bold pt-1">
          {{ t('web.settings.title') }}
        </v-card-title>
        <v-card-text class="pt-2">
          <div class="et-group mb-3">
            <button
              v-for="item in visibleSettingsItems()"
              :key="item.key"
              type="button"
              class="et-row et-row-pressable et-row-btn"
              :aria-label="item.value ? `${item.label} · ${item.value}` : item.label"
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
            </button>
          </div>

          <div class="et-group mb-3">
            <button
              type="button"
              class="et-row et-row-pressable et-row-btn"
              :aria-label="t('about.title')"
              @click="aboutVisible = true; settingsSheetOpen = false"
            >
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
            </button>
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
        <div class="sheet-grabber" aria-hidden="true" />
        <v-card-title class="text-subtitle-1 font-weight-bold pt-1">
          {{ t('logging') }}
        </v-card-title>
        <v-card-text>
          <div class="et-group mb-3">
            <button
              v-for="level in logLevels"
              :key="level"
              type="button"
              class="et-row et-row-pressable et-row-btn"
              :aria-label="t(`logging_level_${level}`)"
              :aria-pressed="currentLogLevel === level"
              @click="applyLogLevel(level)"
            >
              <span class="font-weight-medium">{{ t(`logging_level_${level}`) }}</span>
              <v-icon v-if="currentLogLevel === level" color="primary" size="20">
                mdi-check
              </v-icon>
            </button>
          </div>
          <div class="et-group">
            <button
              v-if="!isAndroid"
              type="button"
              class="et-row et-row-pressable et-row-btn"
              :aria-label="t('logging_open_dir')"
              @click="openLogDir"
            >
              <span>{{ t('logging_open_dir') }}</span>
              <v-icon size="18" color="medium-emphasis">
                mdi-folder-open-outline
              </v-icon>
            </button>
            <button
              type="button"
              class="et-row et-row-pressable et-row-btn"
              :aria-label="t('logging_copy_dir')"
              @click="copyLogDir"
            >
              <span>{{ t('logging_copy_dir') }}</span>
              <v-icon size="18" color="medium-emphasis">
                mdi-content-copy
              </v-icon>
            </button>
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
          <!-- 上游 #2579:从设置里点「开机自启」进来时,说明自启是由服务模式提供的,
               否则用户找不到这个关联。 -->
          <v-alert
            v-if="showAutostartHint"
            type="info"
            variant="tonal"
            rounded="xl"
            class="mb-4"
          >
            {{ t('mode.autostart_hint') }}
          </v-alert>
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
      <div class="et-main-body" :class="{ 'has-app-tabbar': mobileUI }">
        <!-- ================= phone =================
             一级导航由 App 持有:首页 / 节点 / 配置 / 动态 / 设置。
             不再有"高级控制台"这层壳:折叠面板一层 + RemoteManagement 内建 tab bar
             一层等于导航套导航;而且内建 tab bar 是 position:fixed,折叠时被祖先的
             display:none 摁住、展开时立刻按视口钉到屏幕底部 —— 看起来就是"展开才凭空
             冒出四个 tab"。
             现在 RemoteManagement 只作为「面板」渲染(:hide-tab-bar + :panel)。 -->
        <template v-if="mobileUI">
          <MeshHero
            v-if="appTab === 'mesh'"
            class="et-animate-in"
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
            @create="createNetworkDialogVisible = true"
            @open-notif-settings="openNotificationSettings"
            @manage="appTab = 'config'"
          />

          <!-- 设置:与客户端是否在运行无关,所以必须排在 clientRunning 判断之前,
               否则后端没起来时设置页会变成"客户端未运行"。 -->
          <section v-else-if="appTab === 'settings'" class="et-settings-page et-animate-in">
            <h1 class="et-page-title">
              {{ t('web.settings.title') }}
            </h1>

            <div class="et-group mb-3">
              <button
                v-for="item in visibleSettingsItems()"
                :key="item.key"
                type="button"
                class="et-row et-row-pressable et-row-btn"
                :aria-label="item.value ? `${item.label} · ${item.value}` : item.label"
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
              </button>
            </div>

            <div class="et-group mb-3">
              <button
                type="button"
                class="et-row et-row-pressable et-row-btn"
                :aria-label="t('about.title')"
                @click="aboutVisible = true"
              >
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
              </button>
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
          </section>

          <template v-else>
            <RemoteManagement
              v-if="clientRunning"
              v-model:instance-id="instanceId"
              :api="remoteClient"
              :pause-auto-refresh="isModeSaving"
              :connected-override="mobileStats.ready ? mobileStats.connected : undefined"
              :hide-power-toggle="true"
              :hide-tab-bar="true"
              :panel="remotePanel"
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
        </template>

        <!-- ============ desktop: full web console + 顶栏分段导航 ============ -->
        <template v-else>
          <RemoteManagement
            v-if="clientRunning"
            v-model:instance-id="instanceId"
            class="fill-height"
            :api="remoteClient"
            :pause-auto-refresh="isModeSaving"
            :hide-tab-bar="true"
            :panel="desktopPanel"
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

    <!-- App 的一级导航。样式复用 design-system 的 .et-tab-bar / .et-tab-item
         （全局样式，已带安全区、毛玻璃与 --et-z-nav 语义层级），
         文案复用 frontend-lib 已有的 tabs.*，不再自造一套。 -->
    <nav
      v-if="mobileUI"
      class="et-tab-bar d-flex align-center justify-space-around"
      role="tablist"
      :aria-label="pt('tabs.label', '主导航', 'Main navigation')"
    >
      <button
        v-for="tab in APP_TABS"
        :key="tab.id"
        type="button"
        class="et-tab-item"
        :class="{ 'tab-active': appTab === tab.id }"
        role="tab"
        :aria-selected="appTab === tab.id"
        @click="appTab = tab.id"
      >
        <v-badge
          v-if="tab.id === 'devices' && peerBadgeCount > 0"
          :content="peerBadgeCount"
          color="primary"
          inline
        >
          <v-icon size="22">
            {{ appTab === tab.id ? tab.iconOn : tab.iconOff }}
          </v-icon>
        </v-badge>
        <v-icon v-else size="22">
          {{ appTab === tab.id ? tab.iconOn : tab.iconOff }}
        </v-icon>
        <span>{{ t(tab.labelKey) }}</span>
      </button>
    </nav>

    <OnboardingDialog v-model="onboardingVisible" />
    <QuickNetworkDialog
      v-model="createNetworkDialogVisible"
      :loading="isCreatingNetwork"
      @create="handleCreateNetwork"
    />

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

    <v-snackbar
      v-model="snackbar"
      :color="snackbarColor"
      :timeout="snackbarTimeout"
      :location="mobileUI ? 'bottom' : 'top'"
      :content-class="mobileUI ? 'et-snackbar-above-tabbar' : undefined"
      rounded="pill"
    >
      <div class="et-snackbar-text">
        {{ snackbarMessage }}
      </div>
      <template #actions>
        <v-btn
          icon="mdi-close"
          variant="text"
          size="small"
          :aria-label="t('close')"
          @click="snackbar = false"
        />
      </template>
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

/* long error toasts wrap instead of being clipped inside the rounded snackbar */
.et-snackbar-text {
  white-space: pre-wrap;
  word-break: break-word;
}

/* sheet rows are real <button>s now: .et-row (frontend-lib) still owns the
   layout + --et-touch floor, this only resets the UA chrome */
.et-row-btn {
  width: 100%;
  min-height: var(--et-touch);
  border: 0;
  background: transparent;
  color: inherit;
  font: inherit;
  text-align: start;
  cursor: pointer;
  appearance: none;
}

.et-row-btn:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: calc(var(--et-space-1) * -1);
}

/* 移动端底部固定导航会给内容封底：不预留高度的列表最后一项会被压住。
   高度 = tab bar 高度 + 安全区，与 .et-tab-bar 的定义保持一致。 */
.has-app-tabbar {
  padding-bottom: calc(var(--et-tab-height) + var(--et-safe-bottom) + var(--et-space-4));
}

/* icon buttons in the fixed header keep the platform touch floor even at
   size="small"; the compound selector outranks .v-btn--icon.v-btn--density-* */
.et-nav-btn.v-btn.v-btn--icon {
  min-width: var(--et-touch);
  min-height: var(--et-touch);
  width: var(--et-touch);
  height: var(--et-touch);
}

/* ---- 桌面端顶栏分段导航 ----
   取代原来钉在窗口底部的手机 tab bar。分段控件不占内容高度、不遮挡内容,
   选中态用背景+字重表达,不只靠颜色(色觉无障碍)。 */
.et-seg {
  display: flex;
  align-items: center;
  gap: var(--et-space-1);
  padding: var(--et-space-1);
  border-radius: var(--et-radius-pill);
  background: var(--et-surface-2);
}

.et-seg-item {
  border: 0;
  background: transparent;
  appearance: none;
  cursor: pointer;
  font: inherit;
  font-size: var(--et-font-body-sm);
  color: var(--et-text-2);
  min-height: calc(var(--et-touch) - var(--et-space-2));
  padding: 0 var(--et-space-4);
  border-radius: var(--et-radius-pill);
  transition:
    background-color var(--et-dur-fast) var(--et-ease-standard),
    color var(--et-dur-fast) var(--et-ease-standard);
}

.et-seg-item:hover {
  color: var(--et-text);
}

.et-seg-item.is-active {
  background: var(--et-surface-1);
  color: var(--et-text);
  font-weight: var(--et-weight-semibold);
  box-shadow: var(--et-shadow-1);
}

.et-seg-item:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: 2px;
}

/* ---- 设置页 ---- */
/* 根页面标题是 28px,紧贴 sticky header 只留 8px 会显得被切掉;给它一档呼吸。 */
.et-settings-page {
  padding-top: var(--et-space-4);
}

.et-page-title {
  font-size: var(--et-font-display);
  font-weight: var(--et-weight-semibold);
  letter-spacing: -0.02em;
  margin-bottom: var(--et-space-4);
}
</style>
