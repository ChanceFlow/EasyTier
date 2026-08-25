import { mount, type VueWrapper } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import { defineComponent, h, nextTick, reactive } from 'vue'
import Config from '../src/components/Config.vue'
import { vuetify } from '../src/theme'
import {
  DEFAULT_NETWORK_CONFIG,
  toBackendNetworkConfig,
  type NetworkConfig,
} from '../src/types/network'

const CONFIG_FLAG_FIELDS = [
  'latency_first',
  'use_smoltcp',
  'disable_ipv6',
  'ipv6_public_addr_auto',
  'enable_kcp_proxy',
  'disable_kcp_input',
  'enable_quic_proxy',
  'disable_quic_input',
  'disable_p2p',
  'p2p_only',
  'lazy_p2p',
  'bind_device',
  'no_tun',
  'enable_exit_node',
  'relay_all_peer_rpc',
  'need_p2p',
  'multi_thread',
  'proxy_forward_by_system',
  'disable_encryption',
  'disable_tcp_hole_punching',
  'disable_udp_hole_punching',
  'enable_udp_broadcast_relay',
  'disable_upnp',
  'disable_sym_hole_punching',
  'enable_magic_dns',
  'enable_private_mode',
] as const satisfies readonly (keyof NetworkConfig)[]

const CONFIG_CHECKBOX_FIELDS = [
  ['dhcp', '#virtual_ip_auto'],
  ...CONFIG_FLAG_FIELDS.map((field) => [field, `#${field}`] as const),
] as const satisfies readonly (readonly [keyof NetworkConfig, string])[]

const CONFIG_TOGGLE_FIELDS = [
  'enable_relay_network_whitelist',
  'enable_manual_routes',
  'enable_socks5',
] as const satisfies readonly (keyof NetworkConfig)[]

const CONFIG_UI_BOOLEAN_FIELDS = [
  ...CONFIG_CHECKBOX_FIELDS.map(([field]) => field),
  ...CONFIG_TOGGLE_FIELDS,
] as const satisfies readonly (keyof NetworkConfig)[]

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string, values?: unknown[]) => values ? `${key}:${values.join(',')}` : key,
  }),
}))

const AclManagerStub = defineComponent({
  name: 'AclManager',
  props: {
    modelValue: Object,
  },
  emits: ['update:modelValue'],
  setup(props) {
    return () => h('pre', { 'data-stub': 'acl-manager' }, JSON.stringify(props.modelValue))
  },
})

function splitList(value: string): string[] {
  return value.split(',').map((item) => item.trim()).filter((item) => item.length > 0)
}

function makeConfig(): NetworkConfig {
  const config = DEFAULT_NETWORK_CONFIG()

  return {
    ...config,
    dhcp: false,
    virtual_ipv4: '10.1.2.3',
    network_length: 24,
    network_name: 'mesh-a',
    network_secret: 'secret-a',
    peer_urls: ['tcp://peer-a:11010', 'udp://peer-b:11010'],
    latency_first: true,
    use_smoltcp: true,
    disable_ipv6: true,
    no_tun: true,
    hostname: 'host-a',
    proxy_cidrs: ['10.10.0.0/16', '172.16.1.0/24'],
    vpn_portal_config: {
      wireguard_listen: '0.0.0.0:22023',
      wireguard_private_key: 'portal-private-key',
      clients: [{
        name: 'phone-a',
        virtual_ip: '10.1.2.10/24',
        groups: ['ops'],
      }],
    },
    listener_urls: ['tcp://0.0.0.0:12010'],
    dev_name: 'tun-test',
    mtu: 1280,
    instance_recv_bps_limit: '9007199254740993',
    enable_relay_network_whitelist: true,
    relay_network_whitelist: ['network-a'],
    enable_manual_routes: true,
    routes: ['192.168.0.0/16'],
    enable_socks5: true,
    socks5_port: 1086,
    exit_nodes: ['exit-a'],
    mapped_listeners: ['tcp://127.0.0.1:22000'],
    port_forwards: [{
      proto: 'udp',
      bind_ip: '0.0.0.0',
      bind_port: 18080,
      dst_ip: '10.0.0.2',
      dst_port: 8080,
    }],
  }
}

async function expandAllPanels(wrapper: VueWrapper) {
  const titles = wrapper.findAll('.v-expansion-panel-title')
  for (const title of titles) {
    await title.trigger('click')
    await nextTick()
  }
  await nextTick()
}

function mountConfig(config: NetworkConfig = makeConfig()) {
  const curNetwork = reactive(config) as NetworkConfig
  const wrapper = mount(Config, {
    props: {
      curNetwork,
      hostname: 'host-from-prop',
    },
    global: {
      plugins: [vuetify],
      stubs: {
        AclManager: AclManagerStub,
      },
    },
  })

  return { curNetwork, wrapper }
}

function input(wrapper: VueWrapper, selector: string): HTMLInputElement {
  return wrapper.find(selector).element as HTMLInputElement
}

async function setInput(wrapper: VueWrapper, selector: string, value: string) {
  await wrapper.find(selector).setValue(value)
  await nextTick()
}

async function comboboxSet(wrapper: VueWrapper, selector: string, value: string) {
  const el = wrapper.find(selector)
  await el.setValue(value)
  await el.trigger('keydown', { key: 'Enter' })
  await nextTick()
}

async function comboboxClearAll(wrapper: VueWrapper, selector: string) {
  // Chips live in the enclosing .v-combobox field, not under the inner input id.
  for (let guard = 0; guard < 20; guard++) {
    const rootEl = wrapper.find(selector).element.closest('.v-combobox') as HTMLElement | null
    const close = rootEl?.querySelector('.v-chip .v-chip__close') as HTMLElement | null
    if (!close) break
    close.click()
    await nextTick()
  }
}

describe('Config.vue network config projection', () => {
  it('projects config values into the visible form controls', async () => {
    const { curNetwork, wrapper } = mountConfig()
    await expandAllPanels(wrapper)

    expect(input(wrapper, '#network_name').value).toBe('mesh-a')
    expect(input(wrapper, '#network_secret').value).toBe('secret-a')
    expect(input(wrapper, '#virtual_ip').value).toBe('10.1.2.3')
    expect(input(wrapper, '#virtual_ip_auto').checked).toBe(false)
    expect(input(wrapper, '#latency_first').checked).toBe(true)
    expect(input(wrapper, '#use_smoltcp').checked).toBe(true)
    expect(input(wrapper, '#disable_ipv6').checked).toBe(true)
    expect(input(wrapper, '#no_tun').checked).toBe(true)

    // initial nodes render as URL rows (compact text shows each URL)
    const basicPanel = wrapper.findAll('.v-expansion-panel')[0]
    expect(basicPanel.findAll('.url-compact-text').map((e) => e.text()))
      .toEqual(['tcp://peer-a:11010', 'udp://peer-b:11010'])

    expect(input(wrapper, '#hostname').value).toBe('host-a')

    // proxy CIDRs render as chips
    expect(wrapper.findAll('.v-chip').map((c) => c.text())).toEqual(
      expect.arrayContaining(['10.10.0.0/16', '172.16.1.0/24']),
    )

    expect(input(wrapper, '#vpn_portal_wireguard_listen').value).toBe('0.0.0.0:22023')
    expect(input(wrapper, '#vpn_portal_wireguard_private_key').value).toBe('portal-private-key')
    expect(input(wrapper, '#vpn_portal_client_name_0').value).toBe('phone-a')
    expect(input(wrapper, '#vpn_portal_client_virtual_ip_0').value).toBe('10.1.2.10/24')
    expect(input(wrapper, '#vpn_portal_client_groups_0').value).toBe('ops')
    expect(input(wrapper, '#dev_name').value).toBe('tun-test')
    expect(input(wrapper, '#mtu').value).toBe('1280')
    expect(input(wrapper, '#instance_recv_bps_limit').value).toBe('9007199254740993')

    // relay whitelist / routes / exit nodes render as chips
    expect(wrapper.findAll('.v-chip').map((c) => c.text())).toEqual(
      expect.arrayContaining(['network-a', '192.168.0.0/16', 'exit-a']),
    )
    expect(input(wrapper, '#socks5_port').value).toBe('1086')

    // listener / mapped listeners render as URL rows
    const advancedPanel = wrapper.findAll('.v-expansion-panel')[1]
    expect(advancedPanel.findAll('.url-compact-text').map((e) => e.text()))
      .toEqual(['tcp://0.0.0.0:12010', 'tcp://127.0.0.1:22000'])

    // port forwards: proto toggle + bind/dst inputs
    expect(input(wrapper, 'input[placeholder="port_forwards_bind_addr"]').value).toBe('0.0.0.0')
    expect(input(wrapper, 'input[placeholder="port_forwards_dst_addr"]').value).toBe('10.0.0.2')
    const protoButtons = wrapper.findAll('.v-btn-toggle button').map((b) => b.text())
    expect(protoButtons).toEqual(['tcp', 'udp'])

    expect(wrapper.findComponent(AclManagerStub).props('modelValue')).toStrictEqual(curNetwork.acl)
  })

  it('projects form edits back into config and backend JSON', async () => {
    const { curNetwork, wrapper } = mountConfig()
    await expandAllPanels(wrapper)

    await wrapper.find('#virtual_ip_auto').setValue(false)
    await setInput(wrapper, '#network_name', 'mesh-edited')
    await setInput(wrapper, '#network_secret', 'secret-edited')
    await setInput(wrapper, '#virtual_ip', '10.7.7.7')
    await wrapper.find('#no_tun').setValue(false)
    await wrapper.find('#disable_ipv6').setValue(false)
    await setInput(wrapper, '#hostname', 'host-edited')

    // replace proxy CIDRs: clear chips then add
    await comboboxClearAll(wrapper, '#subnet-proxy')
    await comboboxSet(wrapper, '#subnet-proxy', '10.7.0.0/16')
    await comboboxSet(wrapper, '#subnet-proxy', '172.17.0.0/16')

    await setInput(wrapper, '#vpn_portal_wireguard_listen', '[::]:23000')
    await setInput(wrapper, '#vpn_portal_wireguard_private_key', 'edited-private-key')
    await setInput(wrapper, '#vpn_portal_client_name_0', 'laptop-a')
    await setInput(wrapper, '#vpn_portal_client_virtual_ip_0', '10.1.2.20/24')

    // replace listener URLs by editing the first row host + adding one more
    const advancedPanel = wrapper.findAll('.v-expansion-panel')[1]
    const listenerHost = advancedPanel.findAll('.url-host-field input')[0]
    await listenerHost.setValue('10.1.1.1')
    await listenerHost.trigger('blur')
    await nextTick()
    const listenerAdd = advancedPanel.findAll('.url-list-add')[0]
    await listenerAdd.trigger('click')
    await nextTick()

    await setInput(wrapper, '#dev_name', 'tun-edited')
    await setInput(wrapper, '#mtu', '1260')
    await setInput(wrapper, '#instance_recv_bps_limit', '9007199254740993')

    // relay whitelist: clear + add
    await comboboxClearAll(wrapper, '#relay_network_whitelist')
    await comboboxSet(wrapper, '#relay_network_whitelist', 'network-edited')

    // routes: clear + add
    await comboboxClearAll(wrapper, '#routes')
    await comboboxSet(wrapper, '#routes', '192.168.10.0/24')

    await setInput(wrapper, '#socks5_port', '1089')

    // exit nodes: clear + add
    await comboboxClearAll(wrapper, '#exit_nodes')
    await comboboxSet(wrapper, '#exit_nodes', 'exit-edited')

    // port forward proto + addresses
    const protoButtons = wrapper.findAll('.v-btn-toggle button')
    await protoButtons[0].trigger('click') // tcp
    await nextTick()
    await setInput(wrapper, 'input[placeholder="port_forwards_bind_addr"]', '127.0.0.1')
    await setInput(wrapper, 'input[placeholder="port_forwards_dst_addr"]', '10.9.0.2')
    const pfPanel = wrapper.findAll('.v-expansion-panel')[2]
    const portNumbers = pfPanel.findAll<HTMLInputElement>('input[type="number"]')
    const bindPort = portNumbers[0]
    const dstPort = portNumbers[1]
    await bindPort.setValue('19090')
    await dstPort.setValue('9090')

    expect(curNetwork).toMatchObject({
      dhcp: false,
      virtual_ipv4: '10.7.7.7',
      network_name: 'mesh-edited',
      network_secret: 'secret-edited',
      no_tun: false,
      disable_ipv6: false,
      hostname: 'host-edited',
      proxy_cidrs: ['10.7.0.0/16', '172.17.0.0/16'],
      vpn_portal_config: {
        wireguard_listen: '[::]:23000',
        wireguard_private_key: 'edited-private-key',
        clients: [{
          name: 'laptop-a',
          virtual_ip: '10.1.2.20/24',
          groups: ['ops'],
        }],
      },
      dev_name: 'tun-edited',
      mtu: 1260,
      instance_recv_bps_limit: '9007199254740993',
      relay_network_whitelist: ['network-edited'],
      routes: ['192.168.10.0/24'],
      socks5_port: 1089,
      exit_nodes: ['exit-edited'],
      port_forwards: [{
        proto: 'tcp',
        bind_ip: '127.0.0.1',
        bind_port: 19090,
        dst_ip: '10.9.0.2',
        dst_port: 9090,
      }],
    })
    expect(curNetwork.listener_urls[0]).toBe('tcp://10.1.1.1:12010')
    expect(curNetwork.listener_urls).toHaveLength(2)

    const backend = toBackendNetworkConfig(curNetwork)
    expect(backend).toMatchObject({
      virtual_ipv4: '10.7.7.7',
      network_name: 'mesh-edited',
      network_secret: 'secret-edited',
      mtu: 1260,
      instance_recv_bps_limit: '9007199254740993',
      vpn_portal_config: {
        wireguard_listen: '[::]:23000',
        wireguard_private_key: 'edited-private-key',
        clients: [{
          name: 'laptop-a',
          virtual_ip: '10.1.2.20/24',
          groups: ['ops'],
        }],
      },
      port_forwards: [{
        proto: 'tcp',
        bind_ip: '127.0.0.1',
        bind_port: 19090,
        dst_ip: '10.9.0.2',
        dst_port: 9090,
      }],
    })
  })

  it('round-trips every visible boolean config control into backend JSON', async () => {
    const config = makeConfig()
    const originalFlagValues = new Map(
      CONFIG_UI_BOOLEAN_FIELDS.map((field, index) => {
        const value = index % 2 === 0
        config[field] = value
        return [field, value]
      }),
    )

    const { curNetwork, wrapper } = mountConfig(config)
    await expandAllPanels(wrapper)

    for (const [field, selector] of CONFIG_CHECKBOX_FIELDS) {
      const value = originalFlagValues.get(field)
      expect(input(wrapper, selector).checked, `${field} should project into UI`).toBe(value)
      await wrapper.find(selector).setValue(!value)
      await nextTick()
    }

    // First .v-switch is the VPN Portal enable switch; the next three are the
    // relay whitelist / manual routes / socks5 toggles.
    const switchInputs = wrapper.findAll('.v-switch input')
    expect(switchInputs).toHaveLength(CONFIG_TOGGLE_FIELDS.length + 1)
    for (const [index, field] of CONFIG_TOGGLE_FIELDS.entries()) {
      const value = originalFlagValues.get(field)
      const switchEl = switchInputs[index + 1]
      expect((switchEl.element as HTMLInputElement).checked, `${field} should project into UI`)
        .toBe(value)
      await switchEl.setValue(!value)
      await nextTick()
    }

    const backend = toBackendNetworkConfig(curNetwork) as Record<string, unknown>
    for (const [field, value] of originalFlagValues) {
      const expectedValue = !value
      expect(curNetwork[field], `${field} should update config`).toBe(expectedValue)
      expect(backend[field], `${field} should be preserved in backend JSON`).toBe(expectedValue)
    }
  })

  it('uses VPN Portal config presence as the enable switch', async () => {
    const config = DEFAULT_NETWORK_CONFIG()
    const { curNetwork, wrapper } = mountConfig(config)
    await expandAllPanels(wrapper)

    const portalSwitch = wrapper.findAll('.v-switch input')[0]
    expect((portalSwitch.element as HTMLInputElement).checked).toBe(false)

    await portalSwitch.setValue(true)
    await nextTick()
    expect(curNetwork.vpn_portal_config).toEqual({
      wireguard_listen: '0.0.0.0:22022',
      clients: [],
    })

    await portalSwitch.setValue(false)
    await nextTick()
    expect(curNetwork.vpn_portal_config).toBeUndefined()
  })

  it('keeps each VPN Portal client row bound to the same client when reordered', async () => {
    const config = makeConfig()
    config.vpn_portal_config!.clients.push({
      name: 'phone-b',
      virtual_ip: '10.1.2.11',
      groups: ['guests'],
    })
    const { curNetwork, wrapper } = mountConfig(config)
    await expandAllPanels(wrapper)

    const firstClient = curNetwork.vpn_portal_config!.clients[0]
    const secondClient = curNetwork.vpn_portal_config!.clients[1]
    const firstClientInput = input(wrapper, '#vpn_portal_client_name_0')
    curNetwork.vpn_portal_config!.clients = [secondClient, firstClient]
    await nextTick()

    expect(input(wrapper, '#vpn_portal_client_name_1')).toBe(firstClientInput)
    await setInput(wrapper, '#vpn_portal_client_name_1', 'phone-a-edited')
    expect(firstClient.name).toBe('phone-a-edited')
    expect(secondClient.name).toBe('phone-b')
  })

  it('keeps VPN Portal ACL group menus attached inside the config container', async () => {
    const { wrapper } = mountConfig()
    await expandAllPanels(wrapper)

    const groupsSelect = wrapper.findAllComponents({ name: 'VSelect' })
      .find((select) => String(select.props('id')).includes('vpn_portal_client_groups'))
    expect(groupsSelect).toBeTruthy()
    expect(groupsSelect!.props('menuProps')?.attach).toBe('.config-root')
  })

  it('keeps uint64 input editable without losing large values', async () => {
    const { curNetwork, wrapper } = mountConfig()
    await expandAllPanels(wrapper)

    await setInput(wrapper, '#instance_recv_bps_limit', '1234')
    expect(curNetwork.instance_recv_bps_limit).toBe(1234)

    await setInput(wrapper, '#instance_recv_bps_limit', 'not-a-number')
    expect(curNetwork.instance_recv_bps_limit).toBe(1234)

    await setInput(wrapper, '#instance_recv_bps_limit', '0')
    expect(curNetwork.instance_recv_bps_limit).toBeNull()
    expect(input(wrapper, '#instance_recv_bps_limit').value).toBe('')

    await setInput(wrapper, '#instance_recv_bps_limit', '9007199254740993')
    expect(curNetwork.instance_recv_bps_limit).toBe('9007199254740993')

    await setInput(wrapper, '#instance_recv_bps_limit', '18446744073709551616')
    expect(curNetwork.instance_recv_bps_limit).toBe('9007199254740993')

    await setInput(wrapper, '#instance_recv_bps_limit', '')
    expect(curNetwork.instance_recv_bps_limit).toBeNull()
  })

  it('emits runNetwork with the current projected config', async () => {
    const { curNetwork, wrapper } = mountConfig()
    await expandAllPanels(wrapper)

    await setInput(wrapper, '#network_name', 'mesh-running')
    const runButton = wrapper.findAll('button.v-btn')
      .find((button) => button.text().includes('run_network'))
    expect(runButton).toBeTruthy()
    await runButton!.trigger('click')

    expect(wrapper.emitted('runNetwork')?.[0]).toEqual([curNetwork])
    expect((wrapper.emitted('runNetwork')?.[0][0] as NetworkConfig).network_name).toBe('mesh-running')
  })
})
