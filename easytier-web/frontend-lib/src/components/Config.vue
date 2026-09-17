<script setup lang="ts">
import { v4 as uuidv4 } from 'uuid'
import {
  addRow,
  DEFAULT_NETWORK_CONFIG,
  NetworkConfig,
  normalizeNetworkConfig,
  removeRow,
  type PortForwardConfig,
  type VpnPortalClientConfig,
  type VpnPortalConfig,
} from '../types/network'
import { computed, ref, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { useDisplay } from 'vuetify'
import AclManager from './acl/AclManager.vue'
import UrlListInput from './UrlListInput.vue'

const props = defineProps<{
  actionLabel?: string
  configInvalid?: boolean
  hostname?: string
  /** 首刷配置在途:true 时表单区以骨架占位,避免默认值表单闪现 */
  loading?: boolean
}>()

defineEmits(['runNetwork'])

// 触觉反馈:组件内局部实现,不动共享 utils(避免与其他 agent 冲突)
function vibrate(ms = 8) {
  try {
    navigator.vibrate?.(ms)
  } catch {
    /* ignore */
  }
}

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

// Listener addresses are dialled by clients, so server-side-only schemes
// (http/https/txt/srv service discovery) make no sense as listeners (#1967).
const listenerExcludedProtos = new Set(['http', 'https', 'txt', 'srv'])
const listenerProtos: { [proto: string]: number } = Object.fromEntries(
  Object.entries(protos).filter(([proto]) => !listenerExcludedProtos.has(proto)),
)

const inetItems = ref<string[]>([''])
const exitNodesItems = ref<string[]>([''])
const whitelistItems = ref<string[]>([''])

interface BoolFlag {
  field: keyof NetworkConfig
  help: string
  icon?: string
  group: 'path' | 'protocol' | 'p2p' | 'stack' | 'security'
}

const bool_flags: BoolFlag[] = [
  { field: 'latency_first', help: 'latency_first_help', icon: 'mdi-speedometer', group: 'path' },
  { field: 'relay_all_peer_rpc', help: 'relay_all_peer_rpc_help', icon: 'mdi-transit-connection', group: 'path' },
  { field: 'proxy_forward_by_system', help: 'proxy_forward_by_system_help', icon: 'mdi-swap-horizontal', group: 'path' },
  { field: 'use_smoltcp', help: 'use_smoltcp_help', icon: 'mdi-network', group: 'protocol' },
  { field: 'enable_kcp_proxy', help: 'enable_kcp_proxy_help', icon: 'mdi-rocket-launch', group: 'protocol' },
  { field: 'disable_kcp_input', help: 'disable_kcp_input_help', icon: 'mdi-cancel', group: 'protocol' },
  { field: 'enable_quic_proxy', help: 'enable_quic_proxy_help', icon: 'mdi-lightning-bolt', group: 'protocol' },
  { field: 'disable_quic_input', help: 'disable_quic_input_help', icon: 'mdi-cancel', group: 'protocol' },
  { field: 'multi_thread', help: 'multi_thread_help', icon: 'mdi-cpu-64-bit', group: 'protocol' },
  { field: 'disable_p2p', help: 'disable_p2p_help', icon: 'mdi-lan-disconnect', group: 'p2p' },
  { field: 'p2p_only', help: 'p2p_only_help', icon: 'mdi-lan-connect', group: 'p2p' },
  { field: 'lazy_p2p', help: 'lazy_p2p_help', icon: 'mdi-timer-sand', group: 'p2p' },
  { field: 'need_p2p', help: 'need_p2p_help', icon: 'mdi-vector-link', group: 'p2p' },
  { field: 'disable_tcp_hole_punching', help: 'disable_tcp_hole_punching_help', icon: 'mdi-shield-remove', group: 'p2p' },
  { field: 'disable_udp_hole_punching', help: 'disable_udp_hole_punching_help', icon: 'mdi-shield-remove', group: 'p2p' },
  { field: 'disable_sym_hole_punching', help: 'disable_sym_hole_punching_help', icon: 'mdi-shield-remove', group: 'p2p' },
  { field: 'disable_upnp', help: 'disable_upnp_help', icon: 'mdi-server-network-off', group: 'p2p' },
  { field: 'enable_udp_broadcast_relay', help: 'enable_udp_broadcast_relay_help', icon: 'mdi-broadcast', group: 'p2p' },
  { field: 'disable_ipv6', help: 'disable_ipv6_help', icon: 'mdi-ip', group: 'stack' },
  { field: 'ipv6_public_addr_auto', help: 'ipv6_public_addr_auto_help', icon: 'mdi-earth', group: 'stack' },
  { field: 'bind_device', help: 'bind_device_help', icon: 'mdi-router-wireless', group: 'stack' },
  { field: 'no_tun', help: 'no_tun_help', icon: 'mdi-shield-off', group: 'stack' },
  { field: 'enable_exit_node', help: 'enable_exit_node_help', icon: 'mdi-exit-run', group: 'stack' },
  { field: 'enable_magic_dns', help: 'enable_magic_dns_help', icon: 'mdi-dns', group: 'stack' },
  { field: 'disable_encryption', help: 'disable_encryption_help', icon: 'mdi-lock-open-outline', group: 'security' },
  { field: 'enable_private_mode', help: 'enable_private_mode_help', icon: 'mdi-incognito', group: 'security' },
]

const flagGroupOrder = ['path', 'protocol', 'p2p', 'stack', 'security'] as const
const flagGroups = computed(() => {
  return flagGroupOrder.map((key) => ({
    key,
    flags: bool_flags.filter((flag) => flag.group === key),
  }))
})

/* ---------------------------------------------------------------------------
 * 配置分三层(基础 / 高级 / 专家)
 *
 * 切换只做显隐:不跳页、不重载、不碰 curNetwork,字段一个都不删,只是不同时出现。
 * 字段归属是唯一事实来源,切换器计数与显隐都从 TIER_FIELD_KEYS 派生,避免两套定义漂移。
 * ------------------------------------------------------------------------- */
type ConfigTier = 'basic' | 'advanced' | 'expert'

const tierOrder: readonly ConfigTier[] = ['basic', 'advanced', 'expert']

// 缺 i18n 词条时的英文兜底(词条由 locale 维护者补齐,这里不硬编码写死文案)。
const tierLabels: Record<ConfigTier, string> = {
  basic: 'Basic',
  advanced: 'Advanced',
  expert: 'Expert',
}

// 高级层只吸收 KCP/QUIC 代理与线程/路径这类日常调优开关;其余开关全部下沉专家层。
const ADVANCED_FLAG_FIELDS: readonly (keyof NetworkConfig)[] = [
  'latency_first',
  'multi_thread',
  'enable_kcp_proxy',
  'disable_kcp_input',
  'enable_quic_proxy',
  'disable_quic_input',
]

const expertFlagFields = bool_flags
  .map((flag) => flag.field)
  .filter((field) => !ADVANCED_FLAG_FIELDS.includes(field))

const TIER_FIELD_KEYS: Record<ConfigTier, readonly string[]> = {
  // 能连上就够:网络名称 / 网络密钥 / 监听地址 / 对端地址
  basic: ['network_name', 'network_secret', 'listener_urls', 'peer_urls'],
  // 调优:地址、MTU、限速、代理、白名单、路由、SOCKS5 与代理开关
  advanced: [
    'virtual_ip',
    'hostname',
    'dev_name',
    'mtu',
    'instance_recv_bps_limit',
    'proxy_cidrs',
    'exit_nodes',
    'relay_network_whitelist',
    'manual_routes',
    'socks5',
    ...ADVANCED_FLAG_FIELDS,
  ],
  // 其余全部能力:端口转发、ACL、VPN 门户、映射监听与底层协议开关
  expert: [
    'vpn_portal',
    'mapped_listeners',
    'port_forwards',
    'acl',
    ...expertFlagFields,
  ],
}

const tierFieldIndex = new Map<string, ConfigTier>()
for (const tier of tierOrder) {
  for (const key of TIER_FIELD_KEYS[tier]) tierFieldIndex.set(key, tier)
}

const tierCounts: Record<ConfigTier, number> = {
  basic: TIER_FIELD_KEYS.basic.length,
  advanced: TIER_FIELD_KEYS.advanced.length,
  expert: TIER_FIELD_KEYS.expert.length,
}

const activeTier = ref<ConfigTier>('basic')
const activeTierLabelId = computed(() => `config-tier-${activeTier.value}`)

function setTier(tier: ConfigTier) {
  if (activeTier.value === tier) return
  activeTier.value = tier
  vibrate(8)
}

/** 字段是否属于当前层。未登记字段兜底进专家层,保证任何能力都不会永久消失。 */
function inTier(key: string): boolean {
  return (tierFieldIndex.get(key) ?? 'expert') === activeTier.value
}

const anyFlagVisible = computed(() => bool_flags.some((flag) => inTier(flag.field)))

function flagGroupVisible(group: string): boolean {
  return bool_flags.some((flag) => flag.group === group && inTier(flag.field))
}

// 折叠卡片里所有字段的归属;某段在当前层一个字段都没有时整段收起,避免空卡片。
const SECTION_FIELDS: Record<string, readonly string[]> = {
  basic: ['network_name', 'network_secret', 'virtual_ip', 'peer_urls'],
  advanced: [
    ...bool_flags.map((flag) => flag.field as string),
    'hostname',
    'proxy_cidrs',
    'vpn_portal',
    'listener_urls',
    'dev_name',
    'mtu',
    'instance_recv_bps_limit',
    'relay_network_whitelist',
    'manual_routes',
    'socks5',
    'exit_nodes',
    'mapped_listeners',
  ],
  port_forwards: ['port_forwards'],
  acl: ['acl'],
}

function sectionVisible(section: keyof typeof SECTION_FIELDS): boolean {
  return SECTION_FIELDS[section].some((key) => inTier(key))
}

/* ---------------------------------------------------------------------------
 * 字段级校验:错误必须说清"哪一段、为什么",并贴到输入框上(Vuetify 通过
 * error-messages 自动把 aria-describedby 指到消息节点)。
 * ------------------------------------------------------------------------- */
function ipv4Problem(raw: string | null | undefined): string | null {
  const value = (raw ?? '').trim()
  if (!value) return null
  const parts = value.split('.')
  if (parts.length !== 4) {
    return t(
      'validation.ipv4_segment_count',
      [String(parts.length)],
      'IPv4 needs 4 dot-separated segments, got {0}',
    )
  }
  for (let i = 0; i < parts.length; i++) {
    const segment = parts[i]
    if (!/^\d{1,3}$/.test(segment)) {
      return t(
        'validation.ipv4_segment_number',
        [String(i + 1), segment],
        'Segment {0} ("{1}") is not a 1-3 digit number',
      )
    }
    if (Number(segment) > 255) {
      return t(
        'validation.ipv4_segment_range',
        [String(i + 1), segment],
        'Segment {0} is {1}, outside 0-255',
      )
    }
  }
  return null
}

const virtualIpError = computed(() => {
  if (curNetwork.value.dhcp) return null
  return ipv4Problem(curNetwork.value.virtual_ipv4)
})

const networkLengthError = computed(() => {
  if (curNetwork.value.dhcp) return null
  const length = curNetwork.value.network_length
  if (length === null || length === undefined) return null
  if (!Number.isInteger(length) || length < 1 || length > 32) {
    return t('validation.prefix_range', [String(length)], 'Prefix length {0} is outside 1-32')
  }
  return null
})

const mtuError = computed(() => {
  const mtu = curNetwork.value.mtu
  if (mtu === null || mtu === undefined) return null
  if (!Number.isInteger(mtu) || mtu < 400 || mtu > 1380) {
    return t('validation.mtu_range', [String(mtu)], 'MTU {0} is outside 400-1380')
  }
  return null
})

function portProblem(value: unknown): string | null {
  if (value === '' || value === null || value === undefined) return null
  const port = Number(value)
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    return t('validation.port_range', [String(value)], 'Port {0} is outside 1-65535')
  }
  return null
}

function portErrorMessages(value: unknown): string[] {
  const problem = portProblem(value)
  return problem ? [problem] : []
}

const errorSummary = computed(() => {
  const items: { id: string; label: string; message: string }[] = []
  if (virtualIpError.value) {
    items.push({ id: 'virtual_ip', label: t('virtual_ipv4'), message: virtualIpError.value })
  }
  if (networkLengthError.value) {
    items.push({ id: 'network_length', label: t('prefix_length', 'Prefix length'), message: networkLengthError.value })
  }
  if (mtuError.value) {
    items.push({ id: 'mtu', label: t('mtu'), message: mtuError.value })
  }
  return items
})

const errorSummaryEl = ref<HTMLElement | null>(null)

function focusField(id: string) {
  const el = document.getElementById(id)
  if (el instanceof HTMLElement) el.focus()
}

// 提交失败(宿主把 configInvalid 置真)后把焦点移到可聚焦的错误摘要,字段级错误保留。
watch(
  () => props.configInvalid,
  (invalid) => {
    if (invalid && errorSummary.value.length) {
      nextTick(() => errorSummaryEl.value?.focus())
    }
  },
)

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

// 端口转发行有增删:用下标当 key 会在删除中间行时把内容渲染到错误的行上。
// 与 VPN 客户端同一策略,按对象身份分配稳定 id。
const portForwardKeys = ref<WeakMap<PortForwardConfig, string>>(new WeakMap())
function portForwardViewKey(row: PortForwardConfig): string {
  let k = portForwardKeys.value.get(row)
  if (!k) {
    k = uuidv4()
    portForwardKeys.value.set(row, k)
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

// 局部确认弹窗(移动端可用,避免破坏性操作直接生效)
const confirmDialog = ref(false)
const confirmMessage = ref('')
const confirmAction = ref<() => void>(() => {})

function requireConfirm(message: string, action: () => void) {
  confirmMessage.value = message
  confirmAction.value = action
  confirmDialog.value = true
}

function runConfirm() {
  const action = confirmAction.value
  confirmDialog.value = false
  confirmAction.value = () => {}
  action()
}

function confirmRemoveVpnPortalClient(index: number) {
  requireConfirm(
    t('vpn_portal_remove_client_confirm', 'Remove this VPN portal client?'),
    () => removeVpnPortalClient(index),
  )
}

function confirmRemovePortForward(index: number) {
  requireConfirm(
    t('port_forwards_remove_confirm', 'Delete this port forward rule?'),
    () => removeRow(index, curNetwork.value.port_forwards),
  )
}

const showNetworkSecret = ref(false)
const showVpnKey = ref(false)
const basicPanel = ref<number | undefined>(0)

const activePreset = computed<'gaming' | 'compat' | 'secure' | 'default' | 'custom'>(() => {
  const n = curNetwork.value
  if (!n) return 'custom'
  if (n.latency_first && n.multi_thread && !n.disable_udp_hole_punching && !n.p2p_only) {
    return 'gaming'
  }
  if (n.enable_kcp_proxy && n.enable_quic_proxy) {
    return 'compat'
  }
  if (n.p2p_only && n.enable_private_mode) {
    return 'secure'
  }
  if (!n.latency_first && !n.p2p_only && !n.enable_private_mode && !n.enable_kcp_proxy && !n.enable_quic_proxy) {
    return 'default'
  }
  return 'custom'
})

function applyPreset(preset: 'gaming' | 'compat' | 'secure' | 'default') {
  vibrate(8)
  if (preset === 'gaming') {
    curNetwork.value.latency_first = true
    curNetwork.value.multi_thread = true
    curNetwork.value.disable_tcp_hole_punching = false
    curNetwork.value.disable_udp_hole_punching = false
    curNetwork.value.disable_p2p = false
    curNetwork.value.p2p_only = false
  } else if (preset === 'compat') {
    curNetwork.value.enable_kcp_proxy = true
    curNetwork.value.enable_quic_proxy = true
    curNetwork.value.multi_thread = true
    curNetwork.value.relay_all_peer_rpc = true
  } else if (preset === 'secure') {
    curNetwork.value.p2p_only = true
    curNetwork.value.enable_private_mode = true
    curNetwork.value.disable_encryption = false
    curNetwork.value.enable_udp_broadcast_relay = false
  } else if (preset === 'default') {
    curNetwork.value.latency_first = false
    curNetwork.value.p2p_only = false
    curNetwork.value.enable_private_mode = false
    curNetwork.value.enable_kcp_proxy = false
    curNetwork.value.enable_quic_proxy = false
    curNetwork.value.relay_all_peer_rpc = false
  }
}

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
    <!-- 首刷配置未回:4 个分组卡片形状的骨架(不渲染表单,避免测试/宿主语义混淆) -->
    <div v-if="loading" role="progressbar" aria-hidden="true" class="et-skeleton-stack">
      <v-skeleton-loader class="et-skeleton" type="article, list-item-two-line@2" boilerplate />
      <v-skeleton-loader class="et-skeleton" type="article" boilerplate />
      <v-skeleton-loader class="et-skeleton" type="article" boilerplate />
    </div>

    <template v-else>
    <!-- ============ PRESETS: SMART NETWORK OPTIMIZATION ============ -->
    <div class="et-preset-container mb-3 pa-3 rounded-xl">
      <div class="d-flex align-center justify-space-between mb-2">
        <div class="d-flex align-center ga-2">
          <v-icon color="primary" size="18">mdi-tune-vertical-variant</v-icon>
          <span class="text-caption font-weight-bold text-uppercase tracking-wider">{{ t('preset.section_title', 'Network optimization presets') }}</span>
        </div>
        <span class="text-caption text-medium-emphasis">{{ t('preset.section_hint', 'One-tap tuning of protocol and routing features') }}</span>
      </div>

      <div class="et-presets-grid">
        <button
          type="button"
          class="et-preset-chip"
          :class="{ 'is-active': activePreset === 'gaming' }"
          @click="applyPreset('gaming')"
        >
          <v-icon size="18">mdi-gamepad-variant-outline</v-icon>
          <div class="d-flex flex-column text-start min-w-0">
            <span class="et-preset-name font-weight-bold">{{ t('preset.gaming_name', 'Low latency / Gaming') }}</span>
            <span class="et-preset-desc truncate">{{ t('preset.gaming_desc', 'Latency first · Multi-thread · Force direct') }}</span>
          </div>
        </button>

        <button
          type="button"
          class="et-preset-chip"
          :class="{ 'is-active': activePreset === 'compat' }"
          @click="applyPreset('compat')"
        >
          <v-icon size="18">mdi-swap-horizontal</v-icon>
          <div class="d-flex flex-column text-start min-w-0">
            <span class="et-preset-name font-weight-bold">{{ t('preset.compat_name', 'Max traversal / Roaming') }}</span>
            <span class="et-preset-desc truncate">{{ t('preset.compat_desc', 'KCP + QUIC proxy · Wide-area relay') }}</span>
          </div>
        </button>

        <button
          type="button"
          class="et-preset-chip"
          :class="{ 'is-active': activePreset === 'secure' }"
          @click="applyPreset('secure')"
        >
          <v-icon size="18">mdi-shield-lock-outline</v-icon>
          <div class="d-flex flex-column text-start min-w-0">
            <span class="et-preset-name font-weight-bold">{{ t('preset.secure_name', 'Strict security / Private') }}</span>
            <span class="et-preset-desc truncate">{{ t('preset.secure_desc', 'Strict P2P · Private mode · Strong encryption') }}</span>
          </div>
        </button>

        <button
          type="button"
          class="et-preset-chip"
          :class="{ 'is-active': activePreset === 'default' }"
          @click="applyPreset('default')"
        >
          <v-icon size="18">mdi-tune</v-icon>
          <div class="d-flex flex-column text-start min-w-0">
            <span class="et-preset-name font-weight-bold">{{ t('preset.default_name', 'Standard balanced') }}</span>
            <span class="et-preset-desc truncate">{{ t('preset.default_desc', 'Recommended · Balances power and performance') }}</span>
          </div>
        </button>
      </div>
    </div>

    <!-- ============ TIER SWITCHER: 基础 / 高级 / 专家 ============ -->
    <div class="et-tiers" role="group" :aria-label="t('config_tier.label', 'Configuration tier')">
      <button
        v-for="tier in tierOrder"
        :id="`config-tier-${tier}`"
        :key="tier"
        type="button"
        class="et-tier"
        :aria-pressed="activeTier === tier"
        aria-controls="config-tier-fields"
        @click="setTier(tier)"
      >
        <span>{{ t(`config_tier.${tier}`, tierLabels[tier]) }}</span>
        <span class="et-tier__count" aria-hidden="true">{{ tierCounts[tier] }}</span>
      </button>
    </div>

    <div
      id="config-tier-fields"
      class="et-tier-fields"
      role="region"
      :aria-labelledby="activeTierLabelId"
    >
      <!-- 多错时的可聚焦摘要(role=alert);提交失败后焦点落到这里,字段级错误保留 -->
      <div
        v-if="errorSummary.length"
        ref="errorSummaryEl"
        class="et-error-summary"
        role="alert"
        tabindex="-1"
      >
        <p class="et-error-summary__title">{{ t('validation.summary', 'Fix these fields before running') }}</p>
        <ul class="et-error-summary__list">
          <li v-for="item in errorSummary" :key="item.id">
            <a class="et-error-summary__link" :href="`#${item.id}`" @click.prevent="focusField(item.id)">
              {{ item.label }} — {{ item.message }}
            </a>
          </li>
        </ul>
      </div>

    <!-- ============ SECTION 1: BASIC SETTINGS ============ -->
    <v-expansion-panels v-model="basicPanel" v-show="sectionVisible('basic')" variant="accordion" class="et-config-panel-group mb-3">
      <v-expansion-panel :title="t('basic_settings')" class="et-config-panel">
        <template #text>
          <div class="d-flex flex-column ga-4">
            <!-- Network name + secret -->
            <div v-show="inTier('network_name') || inTier('network_secret')" class="d-flex flex-column flex-sm-row ga-3">
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
            <div v-show="inTier('virtual_ip')" class="config-field">
              <div class="d-flex align-center justify-space-between mb-1">
                <label for="virtual_ip" class="config-label">{{ t('virtual_ipv4') }}</label>
                <div class="d-flex align-center ga-2">
                  <label for="virtual_ip_auto" class="text-caption">{{ t('virtual_ipv4_dhcp') }}</label>
                  <v-switch
                    id="virtual_ip_auto"
                    v-model="curNetwork.dhcp"
                    color="primary"
                    hide-details
                    inset
                    density="compact"
                    class="ma-0 pa-0"
                    @update:model-value="vibrate(8)"
                  />
                </div>
              </div>
              <div class="d-flex align-center ga-2">
                <v-text-field
                  id="virtual_ip"
                  v-model="curNetwork.virtual_ipv4"
                  :disabled="curNetwork.dhcp"
                  variant="outlined"
                  density="compact"
                  :hide-details="!virtualIpError"
                  :error-messages="virtualIpError ? [virtualIpError] : []"
                  placeholder="10.144.144.1"
                  class="flex-grow-1"
                />
                <span class="config-slash">/</span>
                <v-text-field
                  id="network_length"
                  :model-value="curNetwork.network_length"
                  :disabled="curNetwork.dhcp"
                  type="number"
                  min="1"
                  max="32"
                  variant="outlined"
                  density="compact"
                  :hide-details="!networkLengthError"
                  :error-messages="networkLengthError ? [networkLengthError] : []"
                  class="config-netlen"
                  @update:model-value="curNetwork.network_length = $event === '' ? 24 : Number($event)"
                />
              </div>
              <small v-if="curNetwork.dhcp" class="text-warning mt-1 d-block text-caption">
                {{ t('dhcp_experimental_warning') }}
              </small>
            </div>

            <!-- Initial nodes -->
            <div v-show="inTier('peer_urls')" class="config-field">
              <div class="d-flex align-center mb-1">
                <label for="initial_nodes" class="config-label">{{ t('initial_nodes') }}</label>
                <v-menu location="top" :close-on-content-click="true">
                  <template #activator="{ props: helpProps }">
                    <v-btn
                      v-bind="helpProps"
                      icon="mdi-help-circle-outline"
                      size="x-small"
                      variant="text"
                      density="comfortable"
                      class="ml-1 text-medium-emphasis"
                      :aria-label="t('web.common.help', 'Help')"
                    />
                  </template>
                  <v-card max-width="320" class="pa-3">
                    <p class="text-body-2 ma-0 text-pre-line" tabindex="0" role="note">{{ t('initial_nodes_help') }}</p>
                  </v-card>
                </v-menu>
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
    <v-expansion-panels v-show="sectionVisible('advanced')" variant="accordion" class="et-config-panel-group mb-3">
      <v-expansion-panel :title="t('advanced_settings')" class="et-config-panel">
        <template #text>
          <div class="d-flex flex-column ga-4">
            <!-- Feature Flags Switch List -->
            <div v-show="anyFlagVisible" class="config-field">
              <div class="config-label font-weight-bold mb-2">{{ t('flags_switch') }}</div>
              <div v-for="group in flagGroups" v-show="flagGroupVisible(group.key)" :key="group.key" class="mb-3">
                <div class="et-section-label px-1">{{ t(`flags_group.${group.key}`) }}</div>
                <div class="et-group">
                  <div v-for="flag in group.flags" v-show="inTier(flag.field)" :key="flag.field" class="et-row">
                    <div class="d-flex align-center ga-2 min-w-0 pr-2">
                      <v-icon v-if="flag.icon" size="18" color="primary" aria-hidden="true">{{ flag.icon }}</v-icon>
                      <div class="min-w-0">
                        <label :for="flag.field" class="flag-title text-body-2 d-block">{{ t(flag.field) }}</label>
                        <span class="flag-desc text-caption text-medium-emphasis d-block">{{ t(flag.help) }}</span>
                      </div>
                    </div>
                    <v-switch
                      v-model="curNetwork[flag.field]"
                      :id="flag.field"
                      color="primary"
                      hide-details
                      inset
                      density="compact"
                      class="ma-0 pa-0 flex-shrink-0"
                      @update:model-value="vibrate(8)"
                    />
                  </div>
                </div>
              </div>
            </div>

            <v-divider v-show="anyFlagVisible" class="my-1" />

            <!-- Hostname -->
            <div v-show="inTier('hostname')" class="config-field">
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
            <div v-show="inTier('proxy_cidrs')" class="config-field">
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
            <div v-show="inTier('vpn_portal')" class="config-field">
              <div class="d-flex align-center justify-space-between mb-2">
                <div class="d-flex align-center ga-2">
                  <v-icon color="primary" size="18">mdi-vpn</v-icon>
                  <label for="vpn_portal_enabled" class="config-label font-weight-bold">{{ t('vpn_portal_label') }}</label>
                </div>
                <v-switch id="vpn_portal_enabled" @update:model-value="vibrate(8)" v-model="vpnPortalEnabled" color="primary" hide-details inset density="compact" />
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
                        :menu-props="{ maxHeight: 240 }"
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
                      @click="confirmRemoveVpnPortalClient(index)"
                    />
                  </div>
                </div>
              </div>
            </div>

            <!-- Listener URLs -->
            <div v-show="inTier('listener_urls')" class="config-field">
              <label for="listener_urls" class="config-label mb-1 d-block">{{ t('listener_urls') }}</label>
              <UrlListInput id="listener_urls" v-model="curNetwork.listener_urls" :protos="listenerProtos" :add-label="t('add_listener_url')" placeholder="0.0.0.0" />
            </div>

            <!-- Dev name -->
            <div v-show="inTier('dev_name')" class="config-field">
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
            <div v-show="inTier('mtu')" class="config-field">
              <div class="d-flex align-center mb-1">
                <label for="mtu" class="config-label">{{ t('mtu') }}</label>
                <v-menu location="top" :close-on-content-click="true">
                  <template #activator="{ props: helpProps }">
                    <v-btn
                      v-bind="helpProps"
                      icon="mdi-help-circle-outline"
                      size="x-small"
                      variant="text"
                      density="comfortable"
                      class="ml-1 text-medium-emphasis"
                      :aria-label="t('web.common.help', 'Help')"
                    />
                  </template>
                  <v-card max-width="320" class="pa-3">
                    <p class="text-body-2 ma-0 text-pre-line" tabindex="0" role="note">{{ t('mtu_help') }}</p>
                  </v-card>
                </v-menu>
              </div>
              <v-text-field
                id="mtu"
                :model-value="curNetwork.mtu ?? ''"
                type="number"
                min="400"
                max="1380"
                variant="outlined"
                density="compact"
                :hide-details="!mtuError"
                :error-messages="mtuError ? [mtuError] : []"
                :placeholder="t('mtu_placeholder')"
                @update:model-value="curNetwork.mtu = $event === '' ? null : Number($event)"
              />
            </div>

            <!-- Instance recv bps limit -->
            <div v-show="inTier('instance_recv_bps_limit')" class="config-field">
              <div class="d-flex align-center mb-1">
                <label for="instance_recv_bps_limit" class="config-label">{{ t('instance_recv_bps_limit') }}</label>
                <v-menu location="top" :close-on-content-click="true">
                  <template #activator="{ props: helpProps }">
                    <v-btn
                      v-bind="helpProps"
                      icon="mdi-help-circle-outline"
                      size="x-small"
                      variant="text"
                      density="comfortable"
                      class="ml-1 text-medium-emphasis"
                      :aria-label="t('web.common.help', 'Help')"
                    />
                  </template>
                  <v-card max-width="320" class="pa-3">
                    <p class="text-body-2 ma-0 text-pre-line" tabindex="0" role="note">{{ t('instance_recv_bps_limit_help') }}</p>
                  </v-card>
                </v-menu>
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
            <div v-show="inTier('relay_network_whitelist')" class="config-field">
              <div class="d-flex align-center justify-space-between mb-1">
                <div class="d-flex align-center">
                  <label for="relay_network_whitelist" class="config-label">{{ t('relay_network_whitelist') }}</label>
                  <v-menu location="top" :close-on-content-click="true">
                    <template #activator="{ props: helpProps }">
                      <v-btn
                        v-bind="helpProps"
                        icon="mdi-help-circle-outline"
                        size="x-small"
                        variant="text"
                        density="comfortable"
                        class="ml-1 text-medium-emphasis"
                        :aria-label="t('web.common.help', 'Help')"
                      />
                    </template>
                    <v-card max-width="320" class="pa-3">
                      <p class="text-body-2 ma-0 text-pre-line" tabindex="0" role="note">{{ t('relay_network_whitelist_help') }}</p>
                    </v-card>
                  </v-menu>
                </div>
                <v-switch id="enable_relay_network_whitelist" :aria-label="t('relay_network_whitelist')" @update:model-value="vibrate(8)" v-model="curNetwork.enable_relay_network_whitelist" color="primary" hide-details inset density="compact" />
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
            <div v-show="inTier('manual_routes')" class="config-field">
              <div class="d-flex align-center justify-space-between mb-1">
                <div class="d-flex align-center">
                  <label for="routes" class="config-label">{{ t('manual_routes') }}</label>
                  <v-menu location="top" :close-on-content-click="true">
                    <template #activator="{ props: helpProps }">
                      <v-btn
                        v-bind="helpProps"
                        icon="mdi-help-circle-outline"
                        size="x-small"
                        variant="text"
                        density="comfortable"
                        class="ml-1 text-medium-emphasis"
                        :aria-label="t('web.common.help', 'Help')"
                      />
                    </template>
                    <v-card max-width="320" class="pa-3">
                      <p class="text-body-2 ma-0 text-pre-line" tabindex="0" role="note">{{ t('manual_routes_help') }}</p>
                    </v-card>
                  </v-menu>
                </div>
                <v-switch id="enable_manual_routes" :aria-label="t('manual_routes')" @update:model-value="vibrate(8)" v-model="curNetwork.enable_manual_routes" color="primary" hide-details inset density="compact" />
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
            <div v-show="inTier('socks5')" class="config-field">
              <div class="d-flex align-center justify-space-between mb-1">
                <div class="d-flex align-center">
                  <label for="socks5_port" class="config-label">{{ t('socks5') }}</label>
                  <v-menu location="top" :close-on-content-click="true">
                    <template #activator="{ props: helpProps }">
                      <v-btn
                        v-bind="helpProps"
                        icon="mdi-help-circle-outline"
                        size="x-small"
                        variant="text"
                        density="comfortable"
                        class="ml-1 text-medium-emphasis"
                        :aria-label="t('web.common.help', 'Help')"
                      />
                    </template>
                    <v-card max-width="320" class="pa-3">
                      <p class="text-body-2 ma-0 text-pre-line" tabindex="0" role="note">{{ t('socks5_help') }}</p>
                    </v-card>
                  </v-menu>
                </div>
                <v-switch id="enable_socks5" :aria-label="t('socks5')" @update:model-value="vibrate(8)" v-model="curNetwork.enable_socks5" color="primary" hide-details inset density="compact" />
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
            <div v-show="inTier('exit_nodes')" class="config-field">
              <div class="d-flex align-center mb-1">
                <label for="exit_nodes" class="config-label">{{ t('exit_nodes') }}</label>
                <v-menu location="top" :close-on-content-click="true">
                  <template #activator="{ props: helpProps }">
                    <v-btn
                      v-bind="helpProps"
                      icon="mdi-help-circle-outline"
                      size="x-small"
                      variant="text"
                      density="comfortable"
                      class="ml-1 text-medium-emphasis"
                      :aria-label="t('web.common.help', 'Help')"
                    />
                  </template>
                  <v-card max-width="320" class="pa-3">
                    <p class="text-body-2 ma-0 text-pre-line" tabindex="0" role="note">{{ t('exit_nodes_help') }}</p>
                  </v-card>
                </v-menu>
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
            <div v-show="inTier('mapped_listeners')" class="config-field">
              <div class="d-flex align-center mb-1">
                <label for="mapped_listeners" class="config-label">{{ t('mapped_listeners') }}</label>
                <v-menu location="top" :close-on-content-click="true">
                  <template #activator="{ props: helpProps }">
                    <v-btn
                      v-bind="helpProps"
                      icon="mdi-help-circle-outline"
                      size="x-small"
                      variant="text"
                      density="comfortable"
                      class="ml-1 text-medium-emphasis"
                      :aria-label="t('web.common.help', 'Help')"
                    />
                  </template>
                  <v-card max-width="320" class="pa-3">
                    <p class="text-body-2 ma-0 text-pre-line" tabindex="0" role="note">{{ t('mapped_listeners_help') }}</p>
                  </v-card>
                </v-menu>
              </div>
              <UrlListInput id="mapped_listeners" v-model="curNetwork.mapped_listeners" :protos="protos" :add-label="t('add_mapped_listener')" />
            </div>
          </div>
        </template>
      </v-expansion-panel>
    </v-expansion-panels>

    <!-- ============ SECTION 3: PORT FORWARDS ============ -->
    <v-expansion-panels v-show="sectionVisible('port_forwards')" variant="accordion" class="et-config-panel-group mb-3">
      <v-expansion-panel :title="t('port_forwards')" class="et-config-panel">
        <template #text>
          <div ref="portForwardContainer" class="d-flex flex-column ga-2">
            <div class="config-field">
              <div class="text-caption text-medium-emphasis mb-2">{{ t('port_forwards_help') }}</div>
              <div v-for="(row, index) in curNetwork.port_forwards" :key="portForwardViewKey(row)" class="pf-row mb-2">
                <!-- Wide screen view -->
                <div v-if="!isCompact" class="d-flex ga-2 align-center pf-row-wide">
                  <v-btn-toggle v-model="row.proto" density="compact" divided class="pf-proto">
                    <v-btn v-for="opt in portForwardProtocolOptions" :key="opt" :value="opt" size="x-small">{{ opt }}</v-btn>
                  </v-btn-toggle>
                  <div class="d-flex align-center ga-1 flex-grow-1">
                    <v-text-field v-model="row.bind_ip" :id="`pf_bind_ip_${index}`" :placeholder="t('port_forwards_bind_addr')" variant="outlined" density="compact" hide-details />
                    <span class="pf-sep">:</span>
                    <v-text-field
                      :id="`pf_bind_port_${index}`"
                      :model-value="row.bind_port"
                      type="number"
                      min="1"
                      max="65535"
                      variant="outlined"
                      density="compact"
                      :hide-details="!portProblem(row.bind_port)"
                      :error-messages="portErrorMessages(row.bind_port)"
                      class="pf-port-field"
                      @update:model-value="row.bind_port = $event === '' ? 1 : Number($event)"
                    />
                  </div>
                  <v-icon size="16" aria-hidden="true">mdi-arrow-right</v-icon>
                  <div class="d-flex align-center ga-1 flex-grow-1">
                    <v-text-field v-model="row.dst_ip" :id="`pf_dst_ip_${index}`" :placeholder="t('port_forwards_dst_addr')" variant="outlined" density="compact" hide-details />
                    <span class="pf-sep">:</span>
                    <v-text-field
                      :id="`pf_dst_port_${index}`"
                      :model-value="row.dst_port"
                      type="number"
                      min="1"
                      max="65535"
                      variant="outlined"
                      density="compact"
                      :hide-details="!portProblem(row.dst_port)"
                      :error-messages="portErrorMessages(row.dst_port)"
                      class="pf-port-field"
                      @update:model-value="row.dst_port = $event === '' ? 1 : Number($event)"
                    />
                  </div>
                  <v-btn icon="mdi-delete" color="error" variant="text" size="small" :aria-label="t('web.common.delete')" @click="confirmRemovePortForward(index)" />
                </div>
                <!-- Small screen view -->
                <div v-else class="pf-row-compact d-flex align-center justify-space-between pa-2 rounded-lg">
                  <span class="text-mono text-body-2 font-weight-medium min-w-0 truncate">{{ row.proto }}://{{ row.bind_ip }}:{{ row.bind_port }} → {{ row.dst_ip }}:{{ row.dst_port }}</span>
                  <div class="d-flex ga-1 shrink-0">
                    <v-btn icon="mdi-pencil" size="small" variant="text" :aria-label="t('web.common.edit')" @click="openPortForwardEditor(index)" />
                    <v-btn icon="mdi-delete" size="small" variant="text" color="error" :aria-label="t('web.common.delete')" @click="confirmRemovePortForward(index)" />
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
    <v-expansion-panels v-show="sectionVisible('acl')" variant="accordion" class="et-config-panel-group mb-3">
      <v-expansion-panel :title="t('acl.title')" class="et-config-panel">
        <template #text>
          <div v-if="curNetwork.acl" class="d-flex flex-column ga-2">
            <AclManager v-model="curNetwork.acl" />
          </div>
          <div v-else class="et-empty">
            <div class="et-empty__icon"><v-icon size="26" color="primary">mdi-shield-lock-outline</v-icon></div>
            <div class="et-empty__title">{{ t('acl.empty_title', 'Access control is off') }}</div>
            <div class="et-empty__hint">{{ t('acl.empty_hint', 'Enable ACL to define which traffic may cross the mesh') }}</div>
            <v-btn
              class="mt-3"
              color="primary"
              variant="tonal"
              rounded="pill"
              :prepend-icon="'mdi-shield-check-outline'"
              @click="curNetwork.acl = { acl_v1: { chains: [], group: { declares: [], members: [] } } }"
            >
              {{ t('acl.enabled') }}
            </v-btn>
          </div>
        </template>
      </v-expansion-panel>
    </v-expansion-panels>
    </div>
    </template>

    <!-- Edit port forward dialog (mobile) -->
    <v-dialog v-model="editingPortForward" max-width="480px" :fullscreen="smAndDown" transition="dialog-bottom-transition">
      <v-card :title="t('port_forwards')" rounded="xl" class="ios-dialog-sheet">
        <v-card-text v-if="editingPortForwardData">
          <div class="d-flex flex-column ga-3">
            <div>
              <label id="pf_edit_proto_label" class="config-label text-caption mb-1 d-block">{{ t('tunnel_proto') }}</label>
              <v-btn-toggle v-model="editingPortForwardData.proto" density="compact" divided class="w-100" aria-labelledby="pf_edit_proto_label">
                <v-btn v-for="opt in portForwardProtocolOptions" :key="opt" :value="opt" class="flex-grow-1">{{ opt }}</v-btn>
              </v-btn-toggle>
            </div>
            <div>
              <label for="pf_edit_bind_ip" class="config-label text-caption mb-1 d-block">{{ t('port_forwards_bind_addr') }}</label>
              <v-text-field id="pf_edit_bind_ip" v-model="editingPortForwardData.bind_ip" variant="outlined" density="compact" hide-details />
            </div>
            <div>
              <label for="pf_edit_bind_port" class="config-label text-caption mb-1 d-block">{{ t('port_forwards_bind_port') }}</label>
              <v-text-field id="pf_edit_bind_port" v-model="editingPortForwardData.bind_port" type="number" min="1" max="65535" variant="outlined" density="compact" :hide-details="!portProblem(editingPortForwardData.bind_port)" :error-messages="portErrorMessages(editingPortForwardData.bind_port)" />
            </div>
            <div>
              <label for="pf_edit_dst_ip" class="config-label text-caption mb-1 d-block">{{ t('port_forwards_dst_addr') }}</label>
              <v-text-field id="pf_edit_dst_ip" v-model="editingPortForwardData.dst_ip" variant="outlined" density="compact" hide-details />
            </div>
            <div>
              <label for="pf_edit_dst_port" class="config-label text-caption mb-1 d-block">{{ t('port_forwards_dst_port') }}</label>
              <v-text-field id="pf_edit_dst_port" v-model="editingPortForwardData.dst_port" type="number" min="1" max="65535" variant="outlined" density="compact" :hide-details="!portProblem(editingPortForwardData.dst_port)" :error-messages="portErrorMessages(editingPortForwardData.dst_port)" />
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

    <!-- Local confirm dialog (destructive actions, phone friendly) -->
    <v-dialog v-model="confirmDialog" max-width="420px" transition="dialog-bottom-transition">
      <v-card :title="t('web.common.confirm')" rounded="xl" class="ios-dialog-sheet">
        <v-card-text>{{ confirmMessage }}</v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="confirmDialog = false">{{ t('web.common.cancel') }}</v-btn>
          <v-btn color="error" variant="flat" rounded="pill" @click="runConfirm">{{ t('web.common.confirm') }}</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Sticky Bottom Run Bar (iOS floating button) -->
    <div class="et-sticky-run">
      <v-btn
        color="primary"
        size="large"
        variant="flat"
        rounded="pill"
        :prepend-icon="'mdi-play-circle-outline'"
        class="et-run-btn"
        :disabled="configInvalid || loading"
        @click="vibrate(12); $emit('runNetwork', curNetwork)"
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

/* ---------- 配置分层切换器 ---------- */
.et-tiers {
  display: flex;
  flex-wrap: wrap;
  gap: var(--et-space-2);
  margin-bottom: var(--et-space-4);
}

.et-tier {
  appearance: none;
  display: inline-flex;
  align-items: center;
  gap: var(--et-space-2);
  min-height: var(--et-touch);
  padding: var(--et-space-2) var(--et-space-4);
  border: 1px solid var(--et-control-border);
  border-radius: var(--et-radius-pill);
  background: var(--et-surface-2);
  color: var(--et-text-2);
  font: inherit;
  font-size: var(--et-font-body-sm);
  font-weight: var(--et-weight-medium);
  cursor: pointer;
  transition:
    background-color var(--et-dur-fast) var(--et-ease-hover),
    border-color var(--et-dur-fast) var(--et-ease-hover),
    color var(--et-dur-fast) var(--et-ease-hover);
}
.et-tier:hover {
  color: var(--et-text);
  border-color: var(--et-accent);
}
.et-tier:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: 2px;
}
.et-tier[aria-pressed='true'] {
  background: var(--et-accent-quiet);
  border-color: var(--et-accent);
  color: var(--et-accent);
}
.et-tier__count {
  font-family: var(--et-font-data);
  font-variant-numeric: var(--et-numeric);
  font-size: var(--et-font-micro);
  opacity: 0.8;
}

.et-tier-fields {
  display: block;
}

/* ---------- 可聚焦错误摘要 ---------- */
.et-error-summary {
  margin-bottom: var(--et-space-4);
  padding: var(--et-space-3) var(--et-space-4);
  border: 1px solid var(--et-danger);
  border-left-width: 4px;
  border-radius: var(--et-radius-sm);
  background: var(--et-danger-quiet);
  color: var(--et-text);
}
.et-error-summary:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: 2px;
}
.et-error-summary__title {
  margin: 0 0 var(--et-space-2);
  font-size: var(--et-font-body-sm);
  font-weight: var(--et-weight-semibold);
  color: var(--et-danger);
}
.et-error-summary__list {
  margin: 0;
  padding-left: var(--et-space-5);
  font-size: var(--et-font-body-sm);
}
.et-error-summary__link {
  color: inherit;
  text-decoration: underline;
}
.et-error-summary__link:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: 2px;
}

.v-expansion-panel.et-config-panel {
  background: var(--et-surface-1);
  border: 1px solid var(--et-border);
  border-radius: var(--et-radius-lg);
}

.et-config-panel :deep(.v-expansion-panel-title) {
  min-height: var(--et-touch);
  font-weight: var(--et-weight-semibold);
}

.config-label {
  font-size: var(--et-font-body-sm);
  font-weight: var(--et-weight-semibold);
  color: var(--et-text);
}

.config-slash {
  font-size: var(--et-font-body);
  font-weight: var(--et-weight-semibold);
  color: var(--et-text-2);
}

.config-netlen {
  max-width: 5rem;
}

.flag-title {
  font-weight: var(--et-weight-semibold);
}

.flag-desc {
  font-size: var(--et-font-micro);
  line-height: var(--et-leading-tight);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.vpn-portal-section {
  background: var(--et-surface-2);
  border-radius: var(--et-radius-md);
}

.vpn-client-row {
  background: var(--et-surface-1);
  border: 1px solid var(--et-border);
}

.pf-row-compact {
  background: var(--et-surface-2);
  border: 1px solid var(--et-border);
  min-height: var(--et-touch-min);
}

.pf-sep {
  color: var(--et-text-2);
}

.pf-port-field {
  max-width: 6rem;
}

.v-card.et-dialog-sheet,
.v-card.ios-dialog-sheet {
  background: var(--et-surface-1);
}

.et-sticky-run {
  position: sticky;
  bottom: 0;
  left: 0;
  right: 0;
  padding: var(--et-space-3) 0 calc(var(--et-space-3) + var(--et-safe-bottom));
  background: linear-gradient(to top, var(--et-bg) 80%, transparent);
  backdrop-filter: blur(var(--et-space-4));
  -webkit-backdrop-filter: blur(var(--et-space-4));
  z-index: var(--et-z-sticky);
  display: flex;
  justify-content: center;
}

.et-run-btn {
  width: 100%;
  max-width: 24rem;
  min-height: var(--et-touch);
  font-weight: var(--et-weight-semibold);
  font-size: var(--et-font-body);
  box-shadow: 0 var(--et-space-2) var(--et-space-6) var(--et-glow);
}

/* ---------- 骨架 ---------- */
.v-skeleton-loader.et-skeleton {
  background: transparent;
  width: 100%;
}

.et-skeleton-stack {
  display: flex;
  flex-direction: column;
  gap: var(--et-space-3);
  padding: var(--et-space-1) var(--et-space-1) var(--et-space-4);
}

/* ---------- 空态 ---------- */
.et-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: var(--et-space-8) var(--et-space-5);
  color: var(--et-text-2);
}

.et-empty__icon {
  width: var(--et-space-16);
  height: var(--et-space-16);
  border-radius: var(--et-radius-lg);
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--et-accent-quiet);
  margin-bottom: var(--et-space-3);
  flex-shrink: 0;
}

.et-empty__title {
  font-size: var(--et-font-body);
  font-weight: var(--et-weight-semibold);
  color: var(--et-text);
}

.et-empty__hint {
  font-size: var(--et-font-body-sm);
  line-height: var(--et-leading-normal);
  max-width: 18rem;
  margin-top: var(--et-space-1);
}

/* ---------- 按压反馈:分组开关行 + 折叠面板标题 ---------- */
@media (prefers-reduced-motion: no-preference) {
  .et-config-panel :deep(.v-expansion-panel-title) {
    transition:
      background-color var(--et-dur-fast) var(--et-ease-hover),
      opacity var(--et-dur-fast) var(--et-ease-hover);
  }

  .et-config-panel :deep(.v-expansion-panel-title):active {
    background-color: var(--et-surface-2);
  }

  .et-skeleton :deep(.v-skeleton-loader__bone::after) {
    background: linear-gradient(
      90deg,
      transparent,
      color-mix(in srgb, var(--et-accent) 10%, transparent),
      transparent
    );
  }
}

.truncate {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.text-mono {
  font-family: var(--et-font-data);
}

/* ---------- 智能网络预设卡片 ---------- */
.et-preset-container {
  background: var(--et-surface-1);
  border: 1px solid var(--et-border);
}

.et-presets-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(11rem, 1fr));
  gap: var(--et-space-2);
}

.et-preset-chip {
  display: flex;
  align-items: center;
  gap: var(--et-space-2);
  min-height: var(--et-touch);
  padding: var(--et-space-2) var(--et-space-3);
  border-radius: var(--et-radius-sm);
  background: var(--et-surface-2);
  border: 1px solid var(--et-control-border);
  color: var(--et-text-2);
  font: inherit;
  cursor: pointer;
  text-align: left;
  transition:
    background-color var(--et-dur-base) var(--et-ease-hover),
    border-color var(--et-dur-base) var(--et-ease-hover),
    color var(--et-dur-base) var(--et-ease-hover),
    box-shadow var(--et-dur-base) var(--et-ease-hover);
}
.et-preset-chip:hover {
  border-color: var(--et-accent);
  background: var(--et-surface-3);
}
.et-preset-chip:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: 2px;
}
.et-preset-chip.is-active {
  background: var(--et-accent-quiet);
  border-color: var(--et-accent);
  color: var(--et-accent);
  box-shadow: 0 0 var(--et-space-3) var(--et-glow);
}
.et-preset-name {
  font-size: var(--et-font-caption);
  line-height: var(--et-leading-tight);
}
.et-preset-desc {
  font-size: var(--et-font-micro);
  color: var(--et-text-3);
  margin-top: var(--et-space-1);
}
.et-preset-chip.is-active .et-preset-desc {
  color: var(--et-accent);
}
</style>
