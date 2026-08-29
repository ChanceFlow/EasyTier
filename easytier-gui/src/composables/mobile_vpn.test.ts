import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => {
  const listeners = new Map<string, (payload: unknown) => Promise<void>>()
  const configs = new Map<string, Record<string, unknown>>()
  const networkInfo = new Map<string, unknown>()

  return {
    listeners,
    configs,
    networkInfo,
    addPluginListener: vi.fn(async (_plugin: string, event: string, listener: (payload: unknown) => Promise<void>) => {
      listeners.set(event, listener)
    }),
    collectNetworkInfo: vi.fn(async (instanceId: string) => ({
      info: { map: { [instanceId]: networkInfo.get(instanceId) } },
    })),
    getConfig: vi.fn(async (instanceId: string) => configs.get(instanceId)),
    getVpnStatus: vi.fn<() => Promise<Record<string, unknown>>>(async () => ({ running: false })),
    listNetworkInstanceIds: vi.fn<() => Promise<{ running_inst_ids: unknown[] }>>(async () => ({ running_inst_ids: [] })),
    prepareVpn: vi.fn(async () => ({ granted: true })),
    setTunFd: vi.fn(async () => undefined),
    startVpn: vi.fn(async () => {
      await listeners.get('vpn_service_start')?.({ fd: 1 })
      return {}
    }),
    stopVpn: vi.fn(async () => {
      await listeners.get('vpn_service_stop')?.({})
      return {}
    }),
    updateNotification: vi.fn(async () => ({})),
  }
})

vi.mock('@tauri-apps/api/core', () => ({
  addPluginListener: mocks.addPluginListener,
}))

vi.mock('easytier-frontend-lib', () => ({
  Utils: {
    UuidToStr: (value: unknown) => String(value),
    ipv4ToString: (address: { addr: string }) => address.addr,
  },
}))

vi.mock('tauri-plugin-vpnservice-api', () => ({
  get_vpn_status: mocks.getVpnStatus,
  prepare_vpn: mocks.prepareVpn,
  start_vpn: mocks.startVpn,
  stop_vpn: mocks.stopVpn,
  update_notification: mocks.updateNotification,
}))

vi.mock('./backend', () => ({
  collectNetworkInfo: mocks.collectNetworkInfo,
  getConfig: mocks.getConfig,
  listNetworkInstanceIds: mocks.listNetworkInstanceIds,
  setTunFd: mocks.setTunFd,
}))

function setConfig(instanceId: string, noTun = false) {
  mocks.configs.set(instanceId, {
    no_tun: noTun,
    dhcp: false,
    enable_magic_dns: false,
    routes: [],
  })
}

function setReady(instanceId: string, ipv4: string) {
  mocks.networkInfo.set(instanceId, {
    my_node_info: {
      virtual_ipv4: {
        address: { addr: ipv4 },
        network_length: 24,
      },
    },
    routes: [],
  })
}

async function loadVpnModule() {
  const mobileVpn = await import('./mobile_vpn')
  await mobileVpn.initMobileVpnService()
  return mobileVpn
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.resetModules()
  mocks.listeners.clear()
  mocks.configs.clear()
  mocks.networkInfo.clear()
  mocks.addPluginListener.mockClear()
  mocks.collectNetworkInfo.mockClear()
  mocks.getConfig.mockClear()
  mocks.getVpnStatus.mockReset()
  mocks.getVpnStatus.mockResolvedValue({ running: false })
  mocks.listNetworkInstanceIds.mockReset()
  mocks.listNetworkInstanceIds.mockResolvedValue({ running_inst_ids: [] })
  mocks.prepareVpn.mockClear()
  mocks.setTunFd.mockClear()
  mocks.startVpn.mockClear()
  mocks.stopVpn.mockClear()
  mocks.updateNotification.mockClear()
})

describe('mobile VPN reconciliation ownership', () => {
  it('stops A before retrying an unavailable B, then starts B when it becomes ready', async () => {
    setConfig('A')
    setConfig('B')
    setReady('A', '10.0.0.1')
    const vpn = await loadVpnModule()

    await vpn.onNetworkInstanceChange('A')
    expect(mocks.startVpn).toHaveBeenCalledTimes(1)

    mocks.startVpn.mockClear()
    await vpn.onNetworkInstanceChange('B')

    expect(mocks.stopVpn).toHaveBeenCalledTimes(1)
    expect(mocks.startVpn).not.toHaveBeenCalled()

    setReady('B', '10.0.0.2')
    await vpn.onNetworkInstanceUpdate('B')

    expect(mocks.startVpn).toHaveBeenCalledTimes(1)
    expect(mocks.startVpn).toHaveBeenCalledWith(expect.objectContaining({ ipv4Addr: '10.0.0.2/24' }))
  })

  it('stops the previous owner during pre-run even if the new instance never reaches post-run', async () => {
    setConfig('A')
    setConfig('B')
    setReady('A', '10.0.0.1')
    const vpn = await loadVpnModule()

    await vpn.onNetworkInstanceChange('A')
    mocks.stopVpn.mockClear()

    await vpn.prepareVpnService('B')

    expect(mocks.stopVpn).toHaveBeenCalledTimes(1)
  })

  it('preserves the VPN while retrying the same instance', async () => {
    setConfig('A')
    setReady('A', '10.0.0.1')
    const vpn = await loadVpnModule()

    await vpn.onNetworkInstanceChange('A')
    mocks.stopVpn.mockClear()
    mocks.networkInfo.delete('A')

    await vpn.onNetworkInstanceUpdate('A')

    expect(mocks.stopVpn).not.toHaveBeenCalled()
  })

  it('ignores an update from an instance that no longer owns the VPN', async () => {
    setConfig('A')
    setConfig('B')
    setReady('A', '10.0.0.1')
    const vpn = await loadVpnModule()

    await vpn.onNetworkInstanceChange('A')
    await vpn.onNetworkInstanceChange('B')
    mocks.collectNetworkInfo.mockClear()

    await vpn.onNetworkInstanceUpdate('A')

    expect(mocks.collectNetworkInfo).not.toHaveBeenCalled()
  })

  it('does not apply an in-flight result after the desired instance changes', async () => {
    setConfig('A')
    setConfig('B')
    setReady('A', '10.0.0.1')
    const vpn = await loadVpnModule()

    await vpn.onNetworkInstanceChange('A')
    mocks.startVpn.mockClear()
    mocks.stopVpn.mockClear()

    interface NetworkInfoResponse { info: { map: Record<string, unknown> } }
    let resolveNetworkInfo: (value: NetworkInfoResponse) => void = () => undefined
    let markCollectStarted: () => void = () => undefined
    const collectStarted = new Promise<void>((resolve) => {
      markCollectStarted = resolve
    })
    mocks.collectNetworkInfo.mockImplementationOnce(async () => await new Promise<NetworkInfoResponse>((resolve) => {
      resolveNetworkInfo = resolve
      markCollectStarted()
    }))

    const staleUpdate = vpn.onNetworkInstanceUpdate('A')
    await collectStarted
    const switchToB = vpn.onNetworkInstanceChange('B')
    resolveNetworkInfo({
      info: {
        map: {
          A: {
            my_node_info: {
              virtual_ipv4: {
                address: { addr: '10.0.0.99' },
                network_length: 24,
              },
            },
            routes: [],
          },
        },
      },
    })

    await Promise.all([staleUpdate, switchToB])

    expect(mocks.startVpn).not.toHaveBeenCalled()
    expect(mocks.stopVpn).toHaveBeenCalledTimes(1)
  })

  it('stops a native VPN with unknown ownership before retrying the selected instance', async () => {
    setConfig('A')
    mocks.getVpnStatus.mockResolvedValue({
      running: true,
      ipv4Addr: '10.0.0.1/24',
      routes: [],
    })
    mocks.listNetworkInstanceIds.mockResolvedValue({ running_inst_ids: ['A'] })
    const vpn = await loadVpnModule()

    await vpn.syncMobileVpnService()

    expect(mocks.stopVpn).toHaveBeenCalledTimes(1)
    expect(mocks.startVpn).not.toHaveBeenCalled()
  })
})

// ---- phone hero: shared mobileStats written by the IO ticker ----

function setTraffic(instanceId: string, rx: number, tx: number, ipv4 = '10.9.9.9') {
  mocks.networkInfo.set(instanceId, {
    my_node_info: {
      virtual_ipv4: { address: { addr: ipv4 }, network_length: 24 },
    },
    routes: ['10.1.0.0/24', '10.2.0.0/24'],
    peer_route_pairs: [
      { peer: { conns: [{ stats: { rx_bytes: String(rx), tx_bytes: String(tx) } }] } },
    ],
  })
}

describe('mobileStats hero data layer', () => {
  it('publishes rates, counts and a rolling history without touching the notification', async () => {
    mocks.configs.set('S', { network_name: 'demo-net', routes: [] })
    setTraffic('S', 1000, 2000)
    const vpn = await loadVpnModule()

    vpn.setMobileStatsInstanceId('S')
    vpn.startMobileIoNotification()
    await vi.advanceTimersByTimeAsync(2000)

    // first sample only establishes the counter baseline
    expect(vpn.mobileStats.ready).toBe(true)
    expect(vpn.mobileStats.connected).toBe(true)
    expect(vpn.mobileStats.virtualIp).toBe('10.9.9.9')
    expect(vpn.mobileStats.peerCount).toBe(1)
    expect(vpn.mobileStats.routeCount).toBe(2)
    expect(vpn.mobileStats.rxRate).toBe(0)
    expect(vpn.mobileStats.history.length).toBe(1)

    setTraffic('S', 3000, 3000)
    await vi.advanceTimersByTimeAsync(2000)

    expect(vpn.mobileStats.rxRate).toBe(1000)
    expect(vpn.mobileStats.txRate).toBe(500)
    expect(vpn.mobileStats.history.length).toBe(2)
    expect(vpn.mobileStats.networkName).toBe('demo-net')
    // no VPN ownership on this path → the notification must stay untouched
    expect(mocks.updateNotification).not.toHaveBeenCalled()
  })

  it('keeps the history window around 60s of samples', async () => {
    setTraffic('S', 500, 500)
    const vpn = await loadVpnModule()

    vpn.setMobileStatsInstanceId('S')
    vpn.startMobileIoNotification()
    await vi.advanceTimersByTimeAsync(122_000)

    // 61 samples taken, only those inside the last 60s survive
    expect(vpn.mobileStats.history.length).toBeGreaterThan(20)
    expect(vpn.mobileStats.history.length).toBeLessThanOrEqual(31)
  })

  it('resets to idle when the observed instance disappears', async () => {
    setTraffic('S', 1000, 1000)
    const vpn = await loadVpnModule()

    vpn.setMobileStatsInstanceId('S')
    vpn.startMobileIoNotification()
    await vi.advanceTimersByTimeAsync(2000)
    expect(vpn.mobileStats.connected).toBe(true)

    vpn.setMobileStatsInstanceId('')
    mocks.listNetworkInstanceIds.mockResolvedValue({ running_inst_ids: [] })
    await vi.advanceTimersByTimeAsync(2000)

    expect(vpn.mobileStats.connected).toBe(false)
    expect(vpn.mobileStats.rxRate).toBe(0)
    expect(vpn.mobileStats.history.length).toBe(0)
  })

  it('still drives the Android ongoing notification when the VPN owns the tunnel', async () => {
    setConfig('A')
    setReady('A', '10.0.0.1')
    const vpn = await loadVpnModule()

    await vpn.onNetworkInstanceChange('A')
    expect(mocks.startVpn).toHaveBeenCalledTimes(1)

    setTraffic('A', 1000, 2000)
    vpn.startMobileIoNotification()
    await vi.advanceTimersByTimeAsync(2000)

    setTraffic('A', 3000, 3000)
    await vi.advanceTimersByTimeAsync(2000)

    expect(mocks.updateNotification).toHaveBeenLastCalledWith(1000, 500)
    expect(vpn.mobileStats.rxRate).toBe(1000)
  })

  it('flags a denied VPN permission for the hero empty state', async () => {
    setConfig('A')
    setReady('A', '10.0.0.1')
    mocks.startVpn.mockImplementation(async () => ({ errorMsg: 'need_prepare' }))
    mocks.prepareVpn.mockResolvedValue({ granted: false })
    const vpn = await loadVpnModule()

    await vpn.onNetworkInstanceChange('A')

    expect(vpn.mobileStats.permissionDenied).toBe(true)
    // the tunnel never came up, so VPN ownership stays unset
    expect(mocks.updateNotification).not.toHaveBeenCalled()
  })
})
