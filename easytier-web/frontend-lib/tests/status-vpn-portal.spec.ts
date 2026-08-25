import { flushPromises, mount } from '@vue/test-utils'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { defineComponent, h } from 'vue'
import Status from '../src/components/Status.vue'
import { vuetify } from '../src/theme'
import { VpnPortalClientState, type NetworkInstance } from '../src/types/network'

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}))

vi.mock('@vueuse/core', () => ({
  useTimeAgo: () => '',
}))

vi.mock('../src/components/NetworkChart.vue', () => ({
  default: defineComponent({ render: () => h('div') }),
}))

const NetworkChartStub = defineComponent({ render: () => h('div') })

function runningInstance(): NetworkInstance {
  return {
    instance_id: '12345678-9abc-def0-fedc-ba9876543210',
    running: true,
    error_msg: '',
    detail: {
      dev_name: 'tun0',
      running: true,
      events: [],
      routes: [],
      peers: [],
      peer_route_pairs: [],
      my_node_info: {
        virtual_ipv4: { address: { addr: 0x0a000001 }, network_length: 24 },
        hostname: 'portal-node',
        version: 'test',
        ips: {
          public_ipv4: { addr: 0 },
          interface_ipv4s: [],
          public_ipv6: { part1: 0, part2: 0, part3: 0, part4: 0 },
          interface_ipv6s: [],
          listeners: [],
        },
        stun_info: { udp_nat_type: 0, tcp_nat_type: 0, last_update_time: 0 },
        listeners: [],
        peer_id: 1,
      },
    },
  }
}

afterEach(() => {
  document.body.innerHTML = ''
})

function mountStatus(api: any) {
  return mount(Status, {
    props: {
      curNetworkInst: runningInstance(),
      api,
    },
    global: {
      plugins: [vuetify],
      stubs: {
        HumanEvent: true,
        NetworkChart: NetworkChartStub,
      },
    },
  })
}

describe('Status VPN Portal details', () => {
  it('fetches client configs only when the user opens the dialog', async () => {
    const getVpnPortalInfo = vi.fn(async () => ({
      vpn_type: 'wireguard',
      client_config: '',
      connected_clients: [],
      listener: '0.0.0.0:22022',
      clients: [{
        name: 'phone-a',
        virtual_ip: '10.0.0.10',
        groups: ['ops'],
        state: VpnPortalClientState.ONLINE,
        peer_id: 42,
        endpoint: '203.0.113.5:51820',
        tunnel_ip: '192.0.2.1',
        client_config: '[Interface]\nPrivateKey = secret',
      }],
    }))
    const wrapper = mountStatus({ get_vpn_portal_info: getVpnPortalInfo })

    try {
      expect(getVpnPortalInfo).not.toHaveBeenCalled()

      const showButton = wrapper.findAll('button.v-btn')
        .find((button) => button.text().includes('show_vpn_portal_config'))
      expect(showButton).toBeTruthy()
      await showButton!.trigger('click')
      await flushPromises()

      expect(getVpnPortalInfo).toHaveBeenCalledOnce()
      expect(getVpnPortalInfo).toHaveBeenCalledWith('12345678-9abc-def0-fedc-ba9876543210')

      const bodyText = document.body.textContent ?? ''
      expect(bodyText).toContain('phone-a · 10.0.0.10')
      expect(bodyText).toContain('203.0.113.5:51820')
      expect(bodyText).toContain('PrivateKey = secret')
    } finally {
      wrapper.unmount()
    }
  })

  it('renders the unconfigured portal sentinel as an empty state', async () => {
    const getVpnPortalInfo = vi.fn(async () => ({
      vpn_type: 'null',
      client_config: '',
      connected_clients: [],
      clients: [],
    }))
    const wrapper = mountStatus({ get_vpn_portal_info: getVpnPortalInfo })

    try {
      const showButton = wrapper.findAll('button.v-btn')
        .find((button) => button.text().includes('show_vpn_portal_config'))
      expect(showButton).toBeTruthy()
      await showButton!.trigger('click')
      await flushPromises()

      const bodyText = document.body.textContent ?? ''
      expect(bodyText).toContain('vpn_portal_not_configured')
      expect(bodyText).not.toContain('vpn_portal_type: null')
    } finally {
      wrapper.unmount()
    }
  })
})
