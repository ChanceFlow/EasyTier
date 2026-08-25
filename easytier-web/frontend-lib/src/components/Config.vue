<script setup lang="ts">
import { v4 as uuidv4 } from 'uuid'
import {
  addRow,
  DEFAULT_NETWORK_CONFIG,
  NetworkConfig,
  normalizeNetworkConfig,
  removeRow,
  type VpnPortalClientConfig,
  type VpnPortalConfig,
} from '../types/network'
import { computed, ref, onMounted, onUnmounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useDisplay } from 'vuetify'
import AclManager from './acl/AclManager.vue'
import UrlListInput from './UrlListInput.vue'

const props = defineProps<{
  actionLabel?: string
  configInvalid?: boolean
  hostname?: string
}>()

defineEmits(['runNetwork'])

const curNetwork = defineModel('curNetwork', {
  type: Object as () => NetworkConfig,
  default: DEFAULT_NETWORK_CONFIG,
})

const { t } = useI18n()
const { smAndDown } = useDisplay()

const protos: { [proto: string]: number } = {
  tcp: 11010,
  udp: 11010,
  wg: 11011,
  ws: 11011,
  wss: 11012,
  quic: 11012,
  faketcp: 11013,
  http: 80,
  https: 443,
  txt: 0,
  srv: 0,
}

const inetItems = ref<string[]>([''])
const exitNodesItems = ref<string[]>([''])
const whitelistItems = ref<string[]>([''])

interface BoolFlag {
  field: keyof NetworkConfig
  help: string
  icon?: string
}

const bool_flags: BoolFlag[] = [
  { field: 'latency_first', help: 'latency_first_help', icon: 'mdi-speedometer' },
  { field: 'use_smoltcp', help: 'use_smoltcp_help', icon: 'mdi-network' },
  { field: 'disable_ipv6', help: 'disable_ipv6_help', icon: 'mdi-ip' },
  { field: 'ipv6_public_addr_auto', help: 'ipv6_public_addr_auto_help', icon: 'mdi-earth' },
  { field: 'enable_kcp_proxy', help: 'enable_kcp_proxy_help', icon: 'mdi-rocket-launch' },
  { field: 'disable_kcp_input', help: 'disable_kcp_input_help', icon: 'mdi-cancel' },
  { field: 'enable_quic_proxy', help: 'enable_quic_proxy_help', icon: 'mdi-lightning-bolt' },
  { field: 'disable_quic_input', help: 'disable_quic_input_help', icon: 'mdi-cancel' },
  { field: 'disable_p2p', help: 'disable_p2p_help', icon: 'mdi-lan-disconnect' },
  { field: 'p2p_only', help: 'p2p_only_help', icon: 'mdi-lan-connect' },
  { field: 'lazy_p2p', help: 'lazy_p2p_help', icon: 'mdi-timer-sand' },
  { field: 'bind_device', help: 'bind_device_help', icon: 'mdi-router-wireless' },
  { field: 'no_tun', help: 'no_tun_help', icon: 'mdi-shield-off' },
  { field: 'enable_exit_node', help: 'enable_exit_node_help', icon: 'mdi-exit-run' },
  { field: 'relay_all_peer_rpc', help: 'relay_all_peer_rpc_help', icon: 'mdi-transit-connection' },
  { field: 'need_p2p', help: 'need_p2p_help', icon: 'mdi-vector-link' },
  { field: 'multi_thread', help: 'multi_thread_help', icon: 'mdi-cpu-64-bit' },
  { field: 'proxy_forward_by_system', help: 'proxy_forward_by_system_help', icon: 'mdi-swap-horizontal' },
  { field: 'disable_encryption', help: 'disable_encryption_help', icon: 'mdi-lock-open-outline' },
  { field: 'disable_tcp_hole_punching', help: 'disable_tcp_hole_punching_help', icon: 'mdi-shield-remove' },
  { field: 'disable_udp_hole_punching', help: 'disable_udp_hole_punching_help', icon: 'mdi-shield-remove' },
  { field: 'enable_udp_broadcast_relay', help: 'enable_udp_broadcast_relay_help', icon: 'mdi-broadcast' },
  { field: 'disable_upnp', help: 'disable_upnp_help', icon: 'mdi-server-network-off' },
  { field: 'disable_sym_hole_punching', help: 'disable_sym_hole_punching_help', icon: 'mdi-shield-remove' },
  { field: 'enable_magic_dns', help: 'enable_magic_dns_help', icon: 'mdi-dns' },
  { field: 'enable_private_mode', help: 'enable_private_mode_help', icon: 'mdi-incognito' },
]

const portForwardProtocolOptions = ref(["tcp", "udp"]);
const editingPortForward = ref(false);
const editingPortForwardIndex = ref(-1);
const editingPortForwardData = ref<any>();

function openPortForwardEditor(index: number) {
  editingPortForwardIndex.value = index;
  editingPortForwardData.value = JSON.parse(JSON.stringify(curNetwork.value.port_forwards[index]));
  editingPortForward.value = true;
}

function addPortForward() {
  addRow(curNetwork.value.port_forwards)
  if (isCompact.value) {
    openPortForwardEditor(curNetwork.value.port_forwards.length - 1)
  }
}

function savePortForward() {
  curNetwork.value.port_forwards[editingPortForwardIndex.value] = editingPortForwardData.value;
  editingPortForward.value = false;
}

const portForwardContainer = ref<HTMLElement | null>(null);
const isCompact = ref(false);
const UINT64_MAX = (1n << 64n) - 1n

onMounted(() => {
  const checkWidth = () => {
    if (portForwardContainer.value) {
      isCompact.value = portForwardContainer.value.clientWidth < 600;
    }
  };

  checkWidth();
  window.addEventListener('resize', checkWidth);

  onUnmounted(() => {
    window.removeEventListener('resize', checkWidth);
  });
});

const instanceRecvBpsLimitInput = computed({
  get() {
    const limit = curNetwork.value.instance_recv_bps_limit
    return limit === undefined || limit === null || limit === 0 || limit === '0' ? '' : String(limit)
  },
  set(val: string) {
    const trimmed = (val ?? '').trim()
    if (trimmed === '' || trimmed === '0') {
      curNetwork.value.instance_recv_bps_limit = null
      return
    }
    if (!/^\d+$/.test(trimmed)) {
      return
    }
    try {
      const parsed = BigInt(trimmed)
      if (parsed > UINT64_MAX) {
        return
      }
      if (parsed === 0n) {
        curNetwork.value.instance_recv_bps_limit = null
      } else if (parsed <= BigInt(Number.MAX_SAFE_INTEGER)) {
        curNetwork.value.instance_recv_bps_limit = Number(trimmed)
      } else {
        curNetwork.value.instance_recv_bps_limit = trimmed
      }
    } catch {
      // ignore
    }
  },
})

const vpnPortalClientKeys = ref<WeakMap<VpnPortalClientConfig, string>>(new WeakMap())
function vpnPortalClientViewKey(client: VpnPortalClientConfig): string {
  let k = vpnPortalClientKeys.value.get(client)
  if (!k) {
    k = uuidv4()
    vpnPortalClientKeys.value.set(client, k)
  }
  return k
}

const vpnPortalConfig = computed<VpnPortalConfig>(() => {
  if (!curNetwork.value.vpn_portal_config) {
    curNetwork.value.vpn_portal_config = {
      wireguard_listen: '',
      wireguard_private_key: '',
      clients: [],
    }
  }
  return curNetwork.value.vpn_portal_config
})

const vpnPortalEnabled = computed({
  get() {
    return !!curNetwork.value.vpn_portal_config
  },
  set(val: boolean) {
    if (val) {
      if (!curNetwork.value.vpn_portal_config) {
        curNetwork.value.vpn_portal_config = {
          wireguard_listen: '0.0.0.0:22022',
          clients: [],
        }
      }
    } else {
      curNetwork.value.vpn_portal_config = undefined
    }
  },
})

const vpnPortalPrivateKey = computed({
  get() {
    return vpnPortalConfig.value.wireguard_private_key ?? ''
  },
  set(val: string) {
    vpnPortalConfig.value.wireguard_private_key = val
  },
})

const vpnPortalGroupOptions = computed(() => {
  return curNetwork.value.acl?.acl_v1?.group?.declares?.map((g) => g.group_name) ?? []
})

function addVpnPortalClient() {
  vpnPortalConfig.value.clients.push({
    name: '',
    virtual_ip: '',
    groups: [],
  })
}

function removeVpnPortalClient(index: number) {
  vpnPortalConfig.value.clients.splice(index, 1)
}

const showNetworkSecret = ref(false)
const showVpnKey = ref(false)

watch(
  curNetwork,
  (val) => {
    if (val) {
      normalizeNetworkConfig(val)
    }
  },
  { immediate: true, deep: true },
)

</script>

<template>
  <div class="config-root">
    <!-- ============ SECTION 1: BASIC SETTINGS ============ -->
    <v-expansion-panels variant="accordion" class="ios-config-panel-group mb-3">
      <v-expansion-panel :title="t('basic_settings')" class="ios-config-panel">
        <template #text>
          <div class="d-flex flex-column ga-4">
            <!-- Network name + secret -->
            <div class="d-flex flex-column flex-sm-row ga-3">
              <div class="flex-grow-1">
                <label for="network_name" class="config-label mb-1 d-block">{{ t('network_name') }}</label>
                <v-text-field
                  id="network_name"
                  v-model="curNetwork.network_name"
                  variant="outlined"
                  density="compact"
                  hide-details
                  placeholder="mesh-network"
                />
              </div>
              <div class="flex-grow-1">
                <label for="network_secret" class="config-label mb-1 d-block">{{ t('network_secret') }}</label>
                <v-text-field
                  id="network_secret"
                  v-model="curNetwork.network_secret"
                  variant="outlined"
                  density="compact"
                  hide-details
                  :type="showNetworkSecret ? 'text' : 'password'"
                  :append-inner-icon="showNetworkSecret ? 'mdi-eye-off' : 'mdi-eye'"
                  @click:append-inner="showNetworkSecret = !showNetworkSecret"
                />
              </div>
            </div>

            <!-- Virtual IPv4 + Prefix Length + DHCP -->
            <div class="config-field">
              <div class="d-flex align-center justify-space-between mb-1">
                <label for="virtual_ip" class="config-label">{{ t('virtual_ipv4') }}</label>
                <div class="d-flex align-center ga-1">
                  <v-checkbox
                    id="virtual_ip_auto"
                    v-model="curNetwork.dhcp"
                    color="primary"
                    hide-details
                    density="compact"
                    class="ma-0 pa-0"
                  />
                  <label for="virtual_ip_auto" class="text-caption cursor-pointer">{{ t('virtual_ipv4_dhcp') }}</label>
                </div>
              </div>
              <div class="d-flex align-center ga-2">
                <v-text-field
                  id="virtual_ip"
                  v-model="curNetwork.virtual_ipv4"
                  :disabled="curNetwork.dhcp"
                  variant="outlined"
                  density="compact"
                  hide-details
                  placeholder="10.144.144.1"
                  class="flex-grow-1"
                />
                <span class="config-slash">/</span>
                <v-text-field
                  :model-value="curNetwork.network_length"
                  :disabled="curNetwork.dhcp"
                  type="number"
                  min="1"
                  max="32"
                  variant="outlined"
                  density="compact"
                  hide-details
                  class="config-netlen"
                  style="max-width: 80px;"
                  @update:model-value="curNetwork.network_length = $event === '' ? 24 : Number($event)"
                />
              </div>
              <small v-if="curNetwork.dhcp" class="text-warning mt-1 d-block text-caption">
                {{ t('dhcp_experimental_warning') }}
              </small>
            </div>

            <!-- Initial nodes -->
            <div class="config-field">
              <div class="d-flex align-center mb-1">
                <label for="initial_nodes" class="config-label">{{ t('initial_nodes') }}</label>
                <v-tooltip :text="t('initial_nodes_help')" location="top">
                  <template #activator="{ props: tooltipProps }">
                    <v-icon v-bind="tooltipProps" size="small" class="ml-1 text-medium-emphasis">mdi-help-circle-outline</v-icon>
                  </template>
                </v-tooltip>
              </div>
              <UrlListInput
                id="initial_nodes"
                v-model="curNetwork.peer_urls"
                :protos="protos"
                default-url="tcp://:11010"
                :add-label="t('add_initial_node')"
                :placeholder="t('initial_node_placeholder')"
              />
            </div>
          </div>
        </template>
      </v-expansion-panel>
    </v-expansion-panels>

    <!-- ============ SECTION 2: ADVANCED SETTINGS ============ -->
    <v-expansion-panels variant="accordion" class="ios-config-panel-group mb-3">
      <v-expansion-panel :title="t('advanced_settings')" class="ios-config-panel">
        <template #text>
          <div class="d-flex flex-column ga-4">
            <!-- Feature Flags Switch List -->
            <div class="config-field">
              <div class="config-label font-weight-bold mb-2">{{ t('flags_switch') }}</div>
              <div class="flags-ios-grid">
                <div v-for="flag in bool_flags" :key="flag.field" class="flag-ios-row">
                  <div class="d-flex align-center justify-space-between w-100">
                    <div class="d-flex align-center ga-2 min-w-0 pr-2">
                      <v-icon v-if="flag.icon" size="18" color="primary">{{ flag.icon }}</v-icon>
                      <div class="min-w-0">
                        <label :for="flag.field" class="flag-title text-body-2 font-weight-medium d-block truncate">{{ t(flag.field) }}</label>
                        <span class="flag-desc text-caption text-medium-emphasis truncate d-block">{{ t(flag.help) }}</span>
                      </div>
                    </div>
                    <v-checkbox
                      v-model="curNetwork[flag.field]"
                      :id="flag.field"
                      color="primary"
                      hide-details
                      density="compact"
                      class="ma-0 pa-0 flex-shrink-0"
                    />
                  </div>
                </div>
              </div>
            </div>

            <v-divider class="my-1" />

            <!-- Hostname -->
            <div class="config-field">
              <label for="hostname" class="config-label mb-1 d-block">{{ t('hostname') }}</label>
              <v-text-field
                id="hostname"
                v-model="curNetwork.hostname"
                variant="outlined"
                density="compact"
                hide-details
                :placeholder="t('hostname_placeholder', [props.hostname])"
              />
            </div>

            <!-- Proxy CIDRs -->
            <div class="config-field">
              <label for="subnet-proxy" class="config-label mb-1 d-block">{{ t('proxy_cidrs') }}</label>
              <v-combobox
                id="subnet-proxy"
                v-model="curNetwork.proxy_cidrs"
                :items="inetItems"
                multiple
                chips
                closable-chips
                variant="outlined"
                density="compact"
                hide-details
                :placeholder="t('chips_placeholder', ['10.0.0.0/24'])"
              />
            </div>

            <!-- VPN Portal (WireGuard) - SWITCH 0 -->
            <div class="config-field">
              <div class="d-flex align-center justify-space-between mb-2">
                <div class="d-flex align-center ga-2">
                  <v-icon color="primary" size="18">mdi-vpn</v-icon>
                  <label class="config-label font-weight-bold">VPN Portal (WireGuard)</label>
                </div>
                <v-switch v-model="vpnPortalEnabled" color="primary" hide-details density="compact" />
              </div>
              <div v-if="vpnPortalEnabled" class="d-flex flex-column ga-3 vpn-portal-section pa-3 rounded-lg">
                <div class="d-flex flex-column flex-sm-row ga-3">
                  <div class="flex-grow-1">
                    <label for="vpn_portal_wireguard_listen" class="config-label text-caption mb-1 d-block">{{ t('vpn_portal_wireguard_listen') }}</label>
                    <v-text-field
                      id="vpn_portal_wireguard_listen"
                      v-model="vpnPortalConfig.wireguard_listen"
                      variant="outlined"
                      density="compact"
                      hide-details
                      :placeholder="t('vpn_portal_wireguard_listen_placeholder')"
                    />
                  </div>
                  <div class="flex-grow-1">
                    <label for="vpn_portal_wireguard_private_key" class="config-label text-caption mb-1 d-block">{{ t('vpn_portal_wireguard_private_key') }}</label>
                    <v-text-field
                      id="vpn_portal_wireguard_private_key"
                      v-model="vpnPortalPrivateKey"
                      variant="outlined"
                      density="compact"
                      hide-details
                      :placeholder="t('vpn_portal_wireguard_private_key_placeholder')"
                      :type="showVpnKey ? 'text' : 'password'"
                      :append-inner-icon="showVpnKey ? 'mdi-eye-off' : 'mdi-eye'"
                      @click:append-inner="showVpnKey = !showVpnKey"
                    />
                  </div>
                </div>

                <div class="d-flex align-center justify-space-between pt-2">
                  <label class="config-label font-weight-medium">{{ t('vpn_portal_clients') }}</label>
                  <v-btn
                    size="small"
                    variant="tonal"
                    color="primary"
                    rounded="pill"
                    :prepend-icon="'mdi-plus'"
                    :disabled="vpnPortalConfig.clients.length >= 64"
                    @click="addVpnPortalClient"
                  >
                    {{ t('vpn_portal_add_client') }}
                  </v-btn>
                </div>

                <div v-if="vpnPortalConfig.clients.length === 0" class="text-caption text-medium-emphasis text-center py-3">
                  {{ t('vpn_portal_no_clients') }}
                </div>
                <div
                  v-for="(client, index) in vpnPortalConfig.clients"
                  :key="vpnPortalClientViewKey(client)"
                  class="vpn-client-row pa-2 rounded-lg"
                >
                  <div class="d-flex flex-column flex-sm-row ga-2 w-100">
                    <div class="flex-grow-1">
                      <v-text-field
                        :id="`vpn_portal_client_name_${index}`"
                        v-model="client.name"
                        variant="outlined"
                        density="compact"
                        hide-details
                        :placeholder="t('vpn_portal_client_name_placeholder')"
                      />
                    </div>
                    <div class="flex-grow-1">
                      <v-text-field
                        :id="`vpn_portal_client_virtual_ip_${index}`"
                        v-model="client.virtual_ip"
                        variant="outlined"
                        density="compact"
                        hide-details
                        :placeholder="t('vpn_portal_client_virtual_ip_placeholder')"
                      />
                    </div>
                    <div class="flex-grow-1">
                      <v-select
                        :id="`vpn_portal_client_groups_${index}`"
                        v-model="client.groups"
                        :items="vpnPortalGroupOptions"
                        multiple
                        chips
                        closable-chips
                        variant="outlined"
                        density="compact"
                        hide-details
                        :menu-props="{ attach: '.config-root', maxHeight: 240 }"
                        :placeholder="t('vpn_portal_client_groups_placeholder')"
                      />
                    </div>
                    <v-btn
                      icon="mdi-delete"
                      color="error"
                      variant="text"
                      size="small"
                      class="align-self-center"
                      :aria-label="t('vpn_portal_remove_client')"
                      @click="removeVpnPortalClient(index)"
                    />
                  </div>
                </div>
              </div>
            </div>

            <!-- Listener URLs -->
            <div class="config-field">
              <label for="listener_urls" class="config-label mb-1 d-block">{{ t('listener_urls') }}</label>
              <UrlListInput v-model="curNetwork.listener_urls" :protos="protos" :add-label="t('add_listener_url')" placeholder="0.0.0.0" />
            </div>

            <!-- Dev name -->
            <div class="config-field">
              <label for="dev_name" class="config-label mb-1 d-block">{{ t('dev_name') }}</label>
              <v-text-field
                id="dev_name"
                v-model="curNetwork.dev_name"
                variant="outlined"
                density="compact"
                hide-details
                :placeholder="t('dev_name_placeholder')"
              />
            </div>

            <!-- MTU -->
            <div class="config-field">
              <div class="d-flex align-center mb-1">
                <label for="mtu" class="config-label">{{ t('mtu') }}</label>
                <v-tooltip :text="t('mtu_help')" location="top">
                  <template #activator="{ props: tooltipProps }">
                    <v-icon v-bind="tooltipProps" size="small" class="ml-1 text-medium-emphasis">mdi-help-circle-outline</v-icon>
                  </template>
                </v-tooltip>
              </div>
              <v-text-field
                id="mtu"
                :model-value="curNetwork.mtu ?? ''"
                type="number"
                min="400"
                max="1380"
                variant="outlined"
                density="compact"
                hide-details
                :placeholder="t('mtu_placeholder')"
                @update:model-value="curNetwork.mtu = $event === '' ? null : Number($event)"
              />
            </div>

            <!-- Instance recv bps limit -->
            <div class="config-field">
              <div class="d-flex align-center mb-1">
                <label for="instance_recv_bps_limit" class="config-label">{{ t('instance_recv_bps_limit') }}</label>
                <v-tooltip :text="t('instance_recv_bps_limit_help')" location="top">
                  <template #activator="{ props: tooltipProps }">
                    <v-icon v-bind="tooltipProps" size="small" class="ml-1 text-medium-emphasis">mdi-help-circle-outline</v-icon>
                  </template>
                </v-tooltip>
              </div>
              <v-text-field
                id="instance_recv_bps_limit"
                v-model="instanceRecvBpsLimitInput"
                type="text"
                inputmode="numeric"
                pattern="[0-9]*"
                variant="outlined"
                density="compact"
                hide-details
                :placeholder="t('instance_recv_bps_limit_placeholder')"
              />
            </div>

            <!-- Relay network whitelist - SWITCH 1 -->
            <div class="config-field">
              <div class="d-flex align-center justify-space-between mb-1">
                <div class="d-flex align-center">
                  <label for="relay_network_whitelist" class="config-label">{{ t('relay_network_whitelist') }}</label>
                  <v-tooltip :text="t('relay_network_whitelist_help')" location="top">
                    <template #activator="{ props: tooltipProps }">
                      <v-icon v-bind="tooltipProps" size="small" class="ml-1 text-medium-emphasis">mdi-help-circle-outline</v-icon>
                    </template>
                  </v-tooltip>
                </div>
                <v-switch v-model="curNetwork.enable_relay_network_whitelist" color="primary" hide-details density="compact" />
              </div>
              <div v-if="curNetwork.enable_relay_network_whitelist" class="mt-2">
                <v-combobox
                  id="relay_network_whitelist"
                  v-model="curNetwork.relay_network_whitelist"
                  :items="whitelistItems"
                  multiple
                  chips
                  closable-chips
                  variant="outlined"
                  density="compact"
                  hide-details
                  :placeholder="t('relay_network_whitelist')"
                />
              </div>
            </div>

            <!-- Manual routes - SWITCH 2 -->
            <div class="config-field">
              <div class="d-flex align-center justify-space-between mb-1">
                <div class="d-flex align-center">
                  <label for="routes" class="config-label">{{ t('manual_routes') }}</label>
                  <v-tooltip :text="t('manual_routes_help')" location="top">
                    <template #activator="{ props: tooltipProps }">
                      <v-icon v-bind="tooltipProps" size="small" class="ml-1 text-medium-emphasis">mdi-help-circle-outline</v-icon>
                    </template>
                  </v-tooltip>
                </div>
                <v-switch v-model="curNetwork.enable_manual_routes" color="primary" hide-details density="compact" />
              </div>
              <div v-if="curNetwork.enable_manual_routes" class="mt-2">
                <v-combobox
                  id="routes"
                  v-model="curNetwork.routes"
                  :items="inetItems"
                  multiple
                  chips
                  closable-chips
                  variant="outlined"
                  density="compact"
                  hide-details
                  :placeholder="t('chips_placeholder', ['192.168.0.0/16'])"
                />
              </div>
            </div>

            <!-- SOCKS5 - SWITCH 3 -->
            <div class="config-field">
              <div class="d-flex align-center justify-space-between mb-1">
                <div class="d-flex align-center">
                  <label for="socks5_port" class="config-label">{{ t('socks5') }}</label>
                  <v-tooltip :text="t('socks5_help')" location="top">
                    <template #activator="{ props: tooltipProps }">
                      <v-icon v-bind="tooltipProps" size="small" class="ml-1 text-medium-emphasis">mdi-help-circle-outline</v-icon>
                    </template>
                  </v-tooltip>
                </div>
                <v-switch v-model="curNetwork.enable_socks5" color="primary" hide-details density="compact" />
              </div>
              <div v-if="curNetwork.enable_socks5" class="mt-2">
                <v-text-field
                  id="socks5_port"
                  :model-value="curNetwork.socks5_port"
                  type="number"
                  min="0"
                  max="65535"
                  variant="outlined"
                  density="compact"
                  hide-details
                  @update:model-value="curNetwork.socks5_port = $event === '' ? 0 : Number($event)"
                />
              </div>
            </div>

            <!-- Exit nodes -->
            <div class="config-field">
              <div class="d-flex align-center mb-1">
                <label for="exit_nodes" class="config-label">{{ t('exit_nodes') }}</label>
                <v-tooltip :text="t('exit_nodes_help')" location="top">
                  <template #activator="{ props: tooltipProps }">
                    <v-icon v-bind="tooltipProps" size="small" class="ml-1 text-medium-emphasis">mdi-help-circle-outline</v-icon>
                  </template>
                </v-tooltip>
              </div>
              <v-combobox
                id="exit_nodes"
                v-model="curNetwork.exit_nodes"
                :items="exitNodesItems"
                multiple
                chips
                closable-chips
                variant="outlined"
                density="compact"
                hide-details
                :placeholder="t('chips_placeholder', ['192.168.8.8'])"
              />
            </div>

            <!-- Mapped listeners -->
            <div class="config-field">
              <div class="d-flex align-center mb-1">
                <label for="mapped_listeners" class="config-label">{{ t('mapped_listeners') }}</label>
                <v-tooltip :text="t('mapped_listeners_help')" location="top">
                  <template #activator="{ props: tooltipProps }">
                    <v-icon v-bind="tooltipProps" size="small" class="ml-1 text-medium-emphasis">mdi-help-circle-outline</v-icon>
                  </template>
                </v-tooltip>
              </div>
              <UrlListInput v-model="curNetwork.mapped_listeners" :protos="protos" :add-label="t('add_mapped_listener')" />
            </div>
          </div>
        </template>
      </v-expansion-panel>
    </v-expansion-panels>

    <!-- ============ SECTION 3: PORT FORWARDS ============ -->
    <v-expansion-panels variant="accordion" class="ios-config-panel-group mb-3">
      <v-expansion-panel :title="t('port_forwards')" class="ios-config-panel">
        <template #text>
          <div ref="portForwardContainer" class="d-flex flex-column ga-2">
            <div class="config-field">
              <div class="text-caption text-medium-emphasis mb-2">{{ t('port_forwards_help') }}</div>
              <div v-for="(row, index) in curNetwork.port_forwards" :key="index" class="pf-row mb-2">
                <!-- Wide screen view -->
                <div v-if="!isCompact" class="d-flex ga-2 align-center pf-row-wide">
                  <v-btn-toggle v-model="row.proto" density="compact" divided class="pf-proto">
                    <v-btn v-for="opt in portForwardProtocolOptions" :key="opt" :value="opt" size="x-small">{{ opt }}</v-btn>
                  </v-btn-toggle>
                  <div class="d-flex align-center ga-1 flex-grow-1">
                    <v-text-field v-model="row.bind_ip" :placeholder="t('port_forwards_bind_addr')" variant="outlined" density="compact" hide-details />
                    <span>:</span>
                    <v-text-field
                      :model-value="row.bind_port"
                      type="number"
                      min="1"
                      max="65535"
                      variant="outlined"
                      density="compact"
                      hide-details
                      style="max-width: 90px;"
                      @update:model-value="row.bind_port = $event === '' ? 1 : Number($event)"
                    />
                  </div>
                  <v-icon size="16">mdi-arrow-right</v-icon>
                  <div class="d-flex align-center ga-1 flex-grow-1">
                    <v-text-field v-model="row.dst_ip" :placeholder="t('port_forwards_dst_addr')" variant="outlined" density="compact" hide-details />
                    <span>:</span>
                    <v-text-field
                      :model-value="row.dst_port"
                      type="number"
                      min="1"
                      max="65535"
                      variant="outlined"
                      density="compact"
                      hide-details
                      style="max-width: 90px;"
                      @update:model-value="row.dst_port = $event === '' ? 1 : Number($event)"
                    />
                  </div>
                  <v-btn icon="mdi-delete" color="error" variant="text" size="small" @click="removeRow(index, curNetwork.port_forwards)" />
                </div>
                <!-- Small screen view -->
                <div v-else class="pf-row-compact d-flex align-center justify-space-between pa-2 rounded-lg">
                  <span class="text-mono text-body-2 font-weight-medium">{{ row.proto }}://{{ row.bind_ip }}:{{ row.bind_port }} → {{ row.dst_ip }}:{{ row.dst_port }}</span>
                  <div class="d-flex ga-1">
                    <v-btn icon="mdi-pencil" size="small" variant="text" @click="openPortForwardEditor(index)" />
                    <v-btn icon="mdi-delete" size="small" variant="text" color="error" @click="removeRow(index, curNetwork.port_forwards)" />
                  </div>
                </div>
              </div>

              <div class="d-flex justify-end mt-2">
                <v-btn color="primary" variant="tonal" size="small" rounded="pill" :prepend-icon="'mdi-plus'" @click="addPortForward">
                  {{ t('port_forwards_add_btn') }}
                </v-btn>
              </div>
            </div>
          </div>
        </template>
      </v-expansion-panel>
    </v-expansion-panels>

    <!-- ============ SECTION 4: ACL ============ -->
    <v-expansion-panels variant="accordion" class="ios-config-panel-group mb-3">
      <v-expansion-panel :title="t('acl.title')" class="ios-config-panel">
        <template #text>
          <div v-if="curNetwork.acl" class="d-flex flex-column ga-2">
            <AclManager v-model="curNetwork.acl" />
          </div>
          <div v-else class="d-flex justify-center pa-4">
            <v-btn
              color="primary"
              variant="tonal"
              rounded="pill"
              @click="curNetwork.acl = { acl_v1: { chains: [], group: { declares: [], members: [] } } }"
            >
              {{ t('acl.enabled') }}
            </v-btn>
          </div>
        </template>
      </v-expansion-panel>
    </v-expansion-panels>

    <!-- Edit port forward dialog (mobile) -->
    <v-dialog v-model="editingPortForward" max-width="480px" :fullscreen="smAndDown">
      <v-card :title="t('port_forwards')" rounded="xl" class="ios-dialog-sheet">
        <v-card-text v-if="editingPortForwardData">
          <div class="d-flex flex-column ga-3">
            <div>
              <label class="config-label text-caption mb-1 d-block">{{ t('tunnel_proto') }}</label>
              <v-btn-toggle v-model="editingPortForwardData.proto" density="compact" divided class="w-100">
                <v-btn v-for="opt in portForwardProtocolOptions" :key="opt" :value="opt" class="flex-grow-1">{{ opt }}</v-btn>
              </v-btn-toggle>
            </div>
            <div>
              <label class="config-label text-caption mb-1 d-block">{{ t('port_forwards_bind_addr') }}</label>
              <v-text-field v-model="editingPortForwardData.bind_ip" variant="outlined" density="compact" hide-details />
            </div>
            <div>
              <label class="config-label text-caption mb-1 d-block">Bind Port</label>
              <v-text-field v-model="editingPortForwardData.bind_port" type="number" min="1" max="65535" variant="outlined" density="compact" hide-details />
            </div>
            <div>
              <label class="config-label text-caption mb-1 d-block">{{ t('port_forwards_dst_addr') }}</label>
              <v-text-field v-model="editingPortForwardData.dst_ip" variant="outlined" density="compact" hide-details />
            </div>
            <div>
              <label class="config-label text-caption mb-1 d-block">Destination Port</label>
              <v-text-field v-model="editingPortForwardData.dst_port" type="number" min="1" max="65535" variant="outlined" density="compact" hide-details />
            </div>
          </div>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="editingPortForward = false">{{ t('web.common.cancel') }}</v-btn>
          <v-btn color="primary" variant="flat" rounded="pill" @click="savePortForward">{{ t('web.common.save') }}</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Sticky Bottom Run Bar (iOS floating button) -->
    <div class="ios-sticky-run-bar">
      <v-btn
        color="primary"
        size="large"
        variant="flat"
        rounded="pill"
        :prepend-icon="'mdi-play-circle-outline'"
        class="ios-run-btn"
        :disabled="configInvalid"
        @click="$emit('runNetwork', curNetwork)"
      >
        {{ actionLabel || t('run_network') }}
      </v-btn>
    </div>
  </div>
</template>

<style scoped>
.config-root {
  width: 100%;
  position: relative;
}

.ios-config-panel {
  background: var(--ios-surface) !important;
  border: 1px solid var(--ios-border);
  border-radius: 14px !important;
}

.config-label {
  font-size: 0.8125rem;
  font-weight: var(--fw-medium);
  color: var(--ios-text);
}

.config-slash {
  font-size: 1.125rem;
  font-weight: var(--fw-bold);
  color: var(--ios-text-secondary);
}

.flags-ios-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 0.5rem;
}

@media (min-width: 600px) {
  .flags-ios-grid {
    grid-template-columns: 1fr 1fr;
  }
}

.flag-ios-row {
  background: var(--ios-surface-secondary);
  border-radius: 12px;
  padding: 0.5rem 0.75rem;
}

.flag-title {
  font-weight: var(--fw-medium) !important;
}

.flag-desc {
  font-size: 0.725rem;
  font-weight: var(--fw-regular);
}

.vpn-portal-section {
  background: var(--ios-surface-secondary);
  border-radius: 12px;
}

.vpn-client-row {
  background: var(--ios-surface);
  border: 1px solid var(--ios-border);
}

.pf-row-compact {
  background: var(--ios-surface-secondary);
  border: 1px solid var(--ios-border);
}

.ios-dialog-sheet {
  background: var(--ios-surface) !important;
}

/* Sticky Run Bar (iOS Translucent Floating CTA) */
.ios-sticky-run-bar {
  position: sticky;
  bottom: 0;
  left: 0;
  right: 0;
  padding: 0.75rem 0 calc(0.75rem + env(safe-area-inset-bottom));
  background: linear-gradient(to top, var(--ios-bg) 80%, transparent);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  z-index: 10;
  display: flex;
  justify-content: center;
}

.ios-run-btn {
  width: 100%;
  max-width: 24rem;
  height: 50px;
  font-weight: var(--fw-bold);
  font-size: 0.9375rem;
  letter-spacing: 0.02em;
  box-shadow: 0 4px 20px rgba(10, 132, 255, 0.4);
}

.truncate {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.text-mono {
  font-family: var(--font-mono);
}
</style>
