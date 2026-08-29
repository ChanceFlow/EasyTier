import type { NetworkTypes } from 'easytier-frontend-lib'
import { addPluginListener } from '@tauri-apps/api/core'
import { Utils } from 'easytier-frontend-lib'
import { get_vpn_status, prepare_vpn, start_vpn, stop_vpn, update_notification } from 'tauri-plugin-vpnservice-api'
import { reactive } from 'vue'
import { collectNetworkInfo, getConfig, listNetworkInstanceIds, setTunFd } from './backend'

type Route = NetworkTypes.Route

interface vpnStatus {
  running: boolean
  ipv4Addr: string | null | undefined
  ipv4Cidr: number | null | undefined
  routes: string[]
  dns: string | null | undefined
}

// ---- shared realtime stats for the phone hero (and the ongoing
// notification): both are fed by the same 2s IO ticker further below ----
//
// Contract consumed by MeshHero.vue. Rates are bytes/s averaged over the
// last sampling interval; `history` is a ~60s rolling window of {t, rx, tx}
// samples used to draw the mini sparkline.
export interface MobileStatsSample {
  t: number
  rx: number
  tx: number
}

export const mobileStats = reactive({
  rxRate: 0,
  txRate: 0,
  connected: false,
  peerCount: 0,
  routeCount: 0,
  /** id of the instance the ticker is currently observing (explicit or discovered) */
  instanceId: '',
  networkName: '',
  virtualIp: '',
  /** instance reported a fatal error_msg (network join failed, wrong secret...) */
  lastError: '',
  /** Android VPN permission was denied/dismissed on the last start attempt */
  permissionDenied: false,
  /** at least one collectNetworkInfo round-trip has completed since boot */
  ready: false,
  history: [] as MobileStatsSample[],
})

let vpnReconcileTimer: ReturnType<typeof setTimeout> | null = null
const VPN_RECONCILE_INTERVAL_MS = 2000
const VPN_RECONCILE_MAX_ATTEMPTS = 60

let desiredVpnInstanceId: string | undefined
let activeVpnInstanceId: string | undefined
let vpnReconcileGeneration = 0
let vpnReconcileAttempts = 0
let vpnReconcileQueue: Promise<void> = Promise.resolve()
let vpnPermissionRequest: Promise<boolean> | null = null

const curVpnStatus: vpnStatus = {
  running: false,
  ipv4Addr: undefined,
  ipv4Cidr: undefined,
  routes: [],
  dns: undefined,
}

async function requestVpnPermissionOnce() {
  console.log('prepare vpn')
  const prepare_ret = await prepare_vpn()
  console.log('prepare vpn', JSON.stringify((prepare_ret)))
  if (prepare_ret?.errorMsg?.length) {
    throw new Error(prepare_ret.errorMsg)
  }

  const granted = prepare_ret?.granted ?? true
  if (!granted) {
    console.info('vpn permission request was denied or dismissed')
    mobileStats.permissionDenied = true
  }
  else {
    mobileStats.permissionDenied = false
  }

  return granted
}

async function requestVpnPermission() {
  if (vpnPermissionRequest) {
    console.log('reuse pending vpn permission request')
    return await vpnPermissionRequest
  }

  const request = requestVpnPermissionOnce()
  vpnPermissionRequest = request
  try {
    return await request
  }
  finally {
    if (vpnPermissionRequest === request) {
      vpnPermissionRequest = null
    }
  }
}

function clearVpnReconcileTimer() {
  if (vpnReconcileTimer) {
    clearTimeout(vpnReconcileTimer)
    vpnReconcileTimer = null
  }
}

function beginVpnReconcile(instanceId?: string) {
  clearVpnReconcileTimer()
  desiredVpnInstanceId = instanceId
  vpnReconcileAttempts = 0
  vpnReconcileGeneration += 1
  return vpnReconcileGeneration
}

function isCurrentVpnReconcile(instanceId: string, generation: number) {
  return desiredVpnInstanceId === (instanceId || undefined) && vpnReconcileGeneration === generation
}

function scheduleVpnReconcile(instanceId: string, generation: number, reason: string) {
  if (!isCurrentVpnReconcile(instanceId, generation))
    return

  if (vpnReconcileAttempts >= VPN_RECONCILE_MAX_ATTEMPTS) {
    console.error(
      'vpn service reconcile stopped after maximum attempts',
      instanceId,
      VPN_RECONCILE_MAX_ATTEMPTS,
      reason,
    )
    return
  }

  clearVpnReconcileTimer()
  vpnReconcileAttempts += 1
  console.log(
    'vpn service is not ready, retrying',
    JSON.stringify({
      instanceId,
      attempt: vpnReconcileAttempts,
      maxAttempts: VPN_RECONCILE_MAX_ATTEMPTS,
      delayMs: VPN_RECONCILE_INTERVAL_MS,
      reason,
    }),
  )
  vpnReconcileTimer = setTimeout(() => {
    vpnReconcileTimer = null
    void enqueueVpnReconcile(instanceId, generation)
  }, VPN_RECONCILE_INTERVAL_MS)
}

function resetVpnConfigStatus() {
  curVpnStatus.ipv4Addr = undefined
  curVpnStatus.ipv4Cidr = undefined
  curVpnStatus.routes = []
  curVpnStatus.dns = undefined
  // a fresh start gets a clean permission slate; a re-denial re-flags it
  mobileStats.permissionDenied = false
}

function syncVpnStatusFromNative(status: Awaited<ReturnType<typeof get_vpn_status>>) {
  curVpnStatus.running = status?.running ?? false
  if (!curVpnStatus.running) {
    activeVpnInstanceId = undefined
    resetVpnConfigStatus()
    return
  }

  const ipv4WithCidr = status?.ipv4Addr
  if (ipv4WithCidr?.length) {
    const [ipv4Addr, cidr] = ipv4WithCidr.split('/')
    curVpnStatus.ipv4Addr = ipv4Addr

    const parsedCidr = Number(cidr)
    curVpnStatus.ipv4Cidr = Number.isInteger(parsedCidr) ? parsedCidr : undefined
  }
  else {
    curVpnStatus.ipv4Addr = undefined
    curVpnStatus.ipv4Cidr = undefined
  }

  curVpnStatus.routes = [...(status?.routes ?? [])]
  curVpnStatus.dns = status?.dns ?? undefined
}

async function waitVpnStatus(target_status: boolean, timeout_sec: number) {
  const start_time = Date.now()
  while (curVpnStatus.running !== target_status) {
    if (Date.now() - start_time > timeout_sec * 1000) {
      throw new Error('wait vpn status timeout')
    }
    await new Promise(r => setTimeout(r, 50))
  }
}

async function doStopVpn(force = false) {
  const wasRunning = curVpnStatus.running
  if (!force && !wasRunning) {
    activeVpnInstanceId = undefined
    return
  }
  console.log('stop vpn')
  const stop_ret = await stop_vpn()
  console.log('stop vpn', JSON.stringify((stop_ret)))
  if (wasRunning) {
    await waitVpnStatus(false, 3)
  }

  activeVpnInstanceId = undefined
  resetVpnConfigStatus()
}

async function doStartVpn(instanceId: string, ipv4Addr: string, cidr: number, routes: string[], dns?: string) {
  if (curVpnStatus.running) {
    return
  }

  console.log('start vpn service', ipv4Addr, cidr, routes, dns)
  const request = {
    ipv4Addr: `${ipv4Addr}/${cidr}`,
    routes,
    dns,
    disallowedApplications: ['com.kkrainbow.easytier'],
    mtu: 1300,
  }

  let start_ret = await start_vpn(request)
  console.log('start vpn response', JSON.stringify(start_ret))
  if (start_ret?.errorMsg === 'need_prepare') {
    const granted = await requestVpnPermission()
    if (!granted) {
      throw new Error('vpn_permission_denied')
    }
    start_ret = await start_vpn(request)
    console.log('start vpn retry response', JSON.stringify(start_ret))
  }

  if (start_ret?.errorMsg?.length) {
    throw new Error(start_ret.errorMsg)
  }
  await waitVpnStatus(true, 3)

  curVpnStatus.ipv4Addr = ipv4Addr
  curVpnStatus.ipv4Cidr = cidr
  curVpnStatus.routes = routes
  curVpnStatus.dns = dns
  activeVpnInstanceId = instanceId
  mobileStats.permissionDenied = false
}

async function onVpnServiceStart(payload: any) {
  console.log('vpn service start', JSON.stringify(payload))
  curVpnStatus.running = true
  if (payload.fd) {
    await setTunFd(payload.fd).catch((e) => {
      console.error('set tun fd failed', e)
    })
  }
}

async function onVpnServiceStop(payload: any) {
  console.log('vpn service stop', JSON.stringify(payload))
  curVpnStatus.running = false
  activeVpnInstanceId = undefined
  resetVpnConfigStatus()
}

async function registerVpnServiceListener() {
  console.log('register vpn service listener')
  await addPluginListener(
    'vpnservice',
    'vpn_service_start',
    onVpnServiceStart,
  )

  await addPluginListener(
    'vpnservice',
    'vpn_service_stop',
    onVpnServiceStop,
  )
}

function getRoutesForVpn(routes: Route[] | undefined, node_config: NetworkTypes.NetworkConfig): string[] {
  const ret = []
  for (const r of routes ?? []) {
    for (let cidr of r.proxy_cidrs ?? []) {
      if (!cidr.includes('/')) {
        cidr += '/32'
      }
      ret.push(cidr)
    }
  }

  for (const route of node_config.routes ?? []) {
    ret.push(route)
  }

  if (node_config.enable_magic_dns) {
    ret.push('100.100.100.101/32')
  }

  // sort and dedup
  return Array.from(new Set(ret)).sort()
}

async function stopVpnOwnedByOtherInstance(instanceId: string, generation: number) {
  if (!isCurrentVpnReconcile(instanceId, generation))
    return false

  if (curVpnStatus.running && activeVpnInstanceId !== instanceId) {
    console.warn('vpn service owner changed', activeVpnInstanceId, instanceId)
    await doStopVpn()
  }

  return isCurrentVpnReconcile(instanceId, generation)
}

async function reconcileNetworkInstance(instanceId: string, generation: number) {
  if (!isCurrentVpnReconcile(instanceId, generation))
    return

  clearVpnReconcileTimer()

  if (!instanceId) {
    console.warn('vpn service skipped because instance id is empty')
    if (curVpnStatus.running) {
      await doStopVpn()
    }
    return
  }
  const config = await getConfig(instanceId)
  if (!isCurrentVpnReconcile(instanceId, generation))
    return

  console.log('vpn service loaded config', instanceId, JSON.stringify({
    no_tun: config.no_tun,
    dhcp: config.dhcp,
    enable_magic_dns: config.enable_magic_dns,
  }))
  if (config.no_tun) {
    console.log('vpn service skipped because no_tun is enabled', instanceId)
    if (activeVpnInstanceId === instanceId) {
      await doStopVpn()
    }
    return
  }

  if (!await stopVpnOwnedByOtherInstance(instanceId, generation))
    return

  let curNetworkInfo
  try {
    curNetworkInfo = (await collectNetworkInfo(instanceId))?.info?.map?.[instanceId]
  }
  catch (e) {
    console.warn('vpn service network info query failed', instanceId, e)
    scheduleVpnReconcile(instanceId, generation, 'network_info_query_failed')
    return
  }

  if (!isCurrentVpnReconcile(instanceId, generation))
    return

  if (!curNetworkInfo) {
    scheduleVpnReconcile(instanceId, generation, 'network_info_unavailable')
    return
  }

  if (curNetworkInfo.error_msg?.length) {
    console.warn('vpn service skipped because network instance failed', instanceId, curNetworkInfo.error_msg)
    vpnReconcileAttempts = 0
    await doStopVpn()
    return
  }

  const virtualIpv4 = curNetworkInfo.my_node_info?.virtual_ipv4
  const virtual_ip = virtualIpv4?.address?.addr ? Utils.ipv4ToString(virtualIpv4.address) : undefined

  if (!virtual_ip || !virtual_ip.length) {
    scheduleVpnReconcile(
      instanceId,
      generation,
      config.dhcp ? 'dhcp_ipv4_unavailable' : 'static_ipv4_unavailable',
    )
    return
  }

  vpnReconcileAttempts = 0

  let network_length = virtualIpv4?.network_length
  if (!network_length) {
    network_length = 24
  }

  const routes = getRoutesForVpn(curNetworkInfo?.routes, config)

  const dns = config.enable_magic_dns ? '100.100.100.101' : undefined

  const ipChanged = virtual_ip !== curVpnStatus.ipv4Addr
  const cidrChanged = network_length !== curVpnStatus.ipv4Cidr
  const routesChanged = JSON.stringify(routes) !== JSON.stringify(curVpnStatus.routes)
  const dnsChanged = dns != curVpnStatus.dns
  const configChanged = ipChanged || cidrChanged || routesChanged || dnsChanged
  const shouldStartVpn = !curVpnStatus.running

  if (shouldStartVpn || configChanged) {
    console.info('vpn service virtual ip changed', JSON.stringify(curVpnStatus), virtual_ip)
    if (curVpnStatus.running) {
      try {
        await doStopVpn()
      }
      catch (e) {
        console.error(e)
      }
    }

    try {
      if (!isCurrentVpnReconcile(instanceId, generation))
        return

      await doStartVpn(instanceId, virtual_ip, network_length, routes, dns)
      if (!isCurrentVpnReconcile(instanceId, generation) && activeVpnInstanceId === instanceId) {
        await doStopVpn()
      }
    }
    catch (e) {
      if (e instanceof Error && e.message === 'need_prepare') {
        console.info('vpn permission is required before starting the Android VPN service')
        return
      }
      if (e instanceof Error && e.message === 'vpn_permission_denied') {
        console.info('vpn permission request was denied or dismissed')
        return
      }
      console.error('start vpn service failed', e)
    }
  }
}

function enqueueVpnTask(task: () => Promise<void>) {
  const run = vpnReconcileQueue
    .catch((e) => {
      console.error('previous vpn service reconcile failed', e)
    })
    .then(task)
  vpnReconcileQueue = run.catch((e) => {
    console.error('vpn service reconcile failed', e)
  })
  return run
}

function enqueueVpnReconcile(instanceId: string, generation: number) {
  return enqueueVpnTask(() => reconcileNetworkInstance(instanceId, generation))
}

export async function onNetworkInstanceChange(instanceId: string) {
  const generation = beginVpnReconcile(instanceId || undefined)

  if (instanceId && await isNoTunEnabled(instanceId)) {
    if (vpnReconcileGeneration !== generation)
      return

    if (activeVpnInstanceId === instanceId) {
      desiredVpnInstanceId = undefined
      await enqueueVpnReconcile('', generation)
      return
    }

    desiredVpnInstanceId = activeVpnInstanceId
    if (activeVpnInstanceId) {
      await enqueueVpnReconcile(activeVpnInstanceId, generation)
    }
    return
  }

  if (vpnReconcileGeneration !== generation)
    return

  await enqueueVpnReconcile(instanceId, generation)
}

export async function onNetworkInstanceUpdate(instanceId: string) {
  if (!instanceId || instanceId !== desiredVpnInstanceId)
    return

  const generation = beginVpnReconcile(instanceId)
  await enqueueVpnReconcile(instanceId, generation)
}

async function isNoTunEnabled(instanceId: string | undefined) {
  if (!instanceId) {
    return false
  }
  return (await getConfig(instanceId)).no_tun ?? false
}

async function findRunningTunInstanceId() {
  const instanceIds = await listNetworkInstanceIds()
  const runningIds = (instanceIds.running_inst_ids ?? []).map(Utils.UuidToStr)
  console.log('vpn service sync running instances', JSON.stringify(runningIds))

  for (const instanceId of runningIds) {
    if (await isNoTunEnabled(instanceId)) {
      continue
    }

    return instanceId
  }

  return undefined
}

export async function initMobileVpnService() {
  await registerVpnServiceListener()
}

export async function prepareVpnService(instanceId: string) {
  if (await isNoTunEnabled(instanceId)) {
    return
  }

  const generation = beginVpnReconcile(instanceId)
  const stopPreviousOwner = enqueueVpnTask(async () => {
    await stopVpnOwnedByOtherInstance(instanceId, generation)
  })
  await Promise.all([requestVpnPermission(), stopPreviousOwner])
}

export async function syncMobileVpnService() {
  syncVpnStatusFromNative(await get_vpn_status())
  const instanceId = await findRunningTunInstanceId()
  if (instanceId) {
    console.log('vpn service sync selected instance', instanceId)
    await onNetworkInstanceChange(instanceId)
    return
  }

  await onNetworkInstanceChange('')
}

// ---- ongoing notification: live tunnel throughput (WireGuard-style) ----
const IO_NOTIFY_INTERVAL_MS = 2000
const IO_STATS_DISCOVERY_TTL_MS = 10_000
const MOBILE_STATS_HISTORY_MS = 60_000
let ioNotifyTimer: ReturnType<typeof setInterval> | null = null
let ioNotifyLast = { inst: '', rx: 0, tx: 0, at: 0 }
let ioNotifyWasActive = false
// the instance the hero UI is showing; falls back to auto-discovery while
// empty, so stats keep flowing even before the page wires its own selection
let statsInstanceId: string | undefined
let statsDiscovery = { at: 0, id: '' }
let statsNameForInstance: string | undefined

/** Tell the ticker which network instance the hero is displaying ('' clears). */
export function setMobileStatsInstanceId(instanceId: string | undefined) {
  const next = instanceId || undefined
  if (next !== statsInstanceId) {
    statsInstanceId = next
    // drop the discovery cache so the next tick re-resolves if needed
    statsDiscovery = { at: 0, id: '' }
  }
}

function pushMobileStatsSample(t: number, rx: number, tx: number) {
  const history = mobileStats.history
  history.push({ t, rx, tx })
  const cutoff = t - MOBILE_STATS_HISTORY_MS
  while (history.length > 0 && history[0].t < cutoff) {
    history.shift()
  }
}

function resetMobileStatsTraffic() {
  mobileStats.rxRate = 0
  mobileStats.txRate = 0
  mobileStats.peerCount = 0
  mobileStats.routeCount = 0
  mobileStats.virtualIp = ''
  mobileStats.lastError = ''
  mobileStats.history = []
}

async function resolveStatsInstanceId(): Promise<string> {
  const explicit = activeVpnInstanceId ?? statsInstanceId
  if (explicit) {
    return explicit
  }
  const now = Date.now()
  if (now - statsDiscovery.at > IO_STATS_DISCOVERY_TTL_MS) {
    statsDiscovery = { at: now, id: '' }
    try {
      const running = (await listNetworkInstanceIds()).running_inst_ids ?? []
      statsDiscovery.id = running.length ? Utils.UuidToStr(running[0]) : ''
    }
    catch (e) {
      console.debug('hero stats instance discovery failed', e)
    }
  }
  return statsDiscovery.id
}

async function tickIoNotification() {
  const vpnInstanceId = activeVpnInstanceId
  let statsInstanceIdResolved = ''
  try {
    statsInstanceIdResolved = await resolveStatsInstanceId()

    // tunnel just dropped: put the notification back to idle text.
    // NOTE: the notification itself stays tied to the *VPN* instance only,
    // exactly as before — the hero stats below may track a non-VPN instance.
    if (!vpnInstanceId) {
      if (ioNotifyWasActive) {
        await update_notification(0, 0)
        ioNotifyWasActive = false
      }
    }

    if (!statsInstanceIdResolved) {
      ioNotifyLast = { inst: '', rx: 0, tx: 0, at: 0 }
      mobileStats.connected = false
      mobileStats.ready = true
      mobileStats.instanceId = ''
      mobileStats.networkName = ''
      resetMobileStatsTraffic()
      return
    }
    mobileStats.instanceId = statsInstanceIdResolved

    if (ioNotifyLast.inst !== statsInstanceIdResolved) {
      ioNotifyLast = { inst: statsInstanceIdResolved, rx: 0, tx: 0, at: 0 }
      mobileStats.history = []
    }
    if (vpnInstanceId) {
      ioNotifyWasActive = true
    }

    const info = (await collectNetworkInfo(statsInstanceIdResolved))?.info?.map?.[statsInstanceIdResolved]
    mobileStats.ready = true
    if (!info) {
      mobileStats.connected = false
      mobileStats.rxRate = 0
      mobileStats.txRate = 0
      mobileStats.peerCount = 0
      return
    }

    let rx = 0
    let tx = 0
    // direct peers carry the connection stats; some builds (and the dev mock)
    // only populate peer_route_pairs, so fall back to the peers embedded there
    const peers: any[] = (info?.peers?.length
      ? info.peers
      : (info?.peer_route_pairs ?? []).map((pair: any) => pair?.peer))
      .filter((p: any) => !!p)
    // field naming varies between the vendored proto TS and CI-regenerated
    // typings (snake vs camel localNames), so read them dynamically
    for (const peer of peers) {
      for (const raw of peer?.conns ?? []) {
        const conn = raw as unknown as Record<string, unknown>
        if (conn.is_closed ?? conn.isClosed) continue
        const st = (conn.stats ?? {}) as unknown as Record<string, unknown>
        rx += Number(st.rx_bytes ?? st.rxBytes ?? 0)
        tx += Number(st.tx_bytes ?? st.txBytes ?? 0)
      }
    }

    const now = Date.now()
    const dt = ioNotifyLast.at > 0 ? (now - ioNotifyLast.at) / 1000 : 0
    const rxRate = dt > 0.2 ? Math.max(0, (rx - ioNotifyLast.rx) / dt) : 0
    const txRate = dt > 0.2 ? Math.max(0, (tx - ioNotifyLast.tx) / dt) : 0
    ioNotifyLast = { inst: statsInstanceIdResolved, rx, tx, at: now }

    const failed = !!info.error_msg?.length
    mobileStats.connected = !failed
    mobileStats.rxRate = failed ? 0 : rxRate
    mobileStats.txRate = failed ? 0 : txRate
    mobileStats.peerCount = failed ? 0 : peers.length
    mobileStats.routeCount = failed ? 0 : ((info.routes?.length ?? 0) || (info.peer_route_pairs?.length ?? 0))
    mobileStats.lastError = info.error_msg ?? ''
    mobileStats.virtualIp = failed
      ? ''
      : (Utils.ipv4ToString(info.my_node_info?.virtual_ipv4?.address ?? { addr: 0 }) || '')
    pushMobileStatsSample(now, failed ? 0 : rxRate, failed ? 0 : txRate)

    if (!statsNameForInstance || statsNameForInstance !== statsInstanceIdResolved) {
      statsNameForInstance = statsInstanceIdResolved
      getConfig(statsInstanceIdResolved)
        .then((cfg) => {
          if (statsNameForInstance === statsInstanceIdResolved) {
            mobileStats.networkName = (cfg as { network_name?: string })?.network_name ?? ''
          }
        })
        .catch(() => { /* hero falls back to the generic title */ })
    }

    if (vpnInstanceId) {
      await update_notification(rxRate, txRate)
    }
  }
  catch (e) {
    mobileStats.ready = true
    console.debug('io notification tick skipped', e)
  }
}

export function startMobileIoNotification() {
  if (ioNotifyTimer) return
  ioNotifyTimer = setInterval(() => { void tickIoNotification() }, IO_NOTIFY_INTERVAL_MS)
}
