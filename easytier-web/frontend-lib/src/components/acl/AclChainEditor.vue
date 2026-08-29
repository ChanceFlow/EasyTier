<script setup lang="ts">
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { AclAction, AclChain, AclChainType, AclProtocol, AclRule, ensureAclChain, ensureAclRuleLists } from '../../types/network'
import AclRuleDialog from './AclRuleDialog.vue'

const props = defineProps<{
  groupNames?: string[]
}>()

const chain = defineModel<AclChain>({ required: true })

const { t } = useI18n()

function rules() {
  return ensureAclChain(chain.value).rules
}

watch(() => rules(), (newRules) => {
  if (!newRules) return
  const isSorted = newRules.every((rule, i) => i === 0 || (rule.priority || 0) <= (newRules[i - 1].priority || 0))
  if (!isSorted) {
    chain.value.rules.sort((a, b) => (b.priority || 0) - (a.priority || 0))
  }
}, { deep: true, immediate: true })

const actionOptions = [
  { label: () => t('acl.allow'), value: AclAction.Allow },
  { label: () => t('acl.drop'), value: AclAction.Drop },
]

const chainTypeOptions = [
  { label: () => t('acl.inbound'), value: AclChainType.Inbound },
  { label: () => t('acl.outbound'), value: AclChainType.Outbound },
  { label: () => t('acl.forward'), value: AclChainType.Forward },
]

const editingRule = ref<AclRule | null>(null)
const editingRuleIndex = ref(-1)
const showRuleDialog = ref(false)

// Drag reorder state (HTML5 DnD)
const dragIndex = ref<number | null>(null)
const dragOverIndex = ref<number | null>(null)

function getProtocolLabel(proto: AclProtocol) {
  switch (proto) {
    case AclProtocol.Any: return t('acl.any')
    case AclProtocol.TCP: return 'TCP'
    case AclProtocol.UDP: return 'UDP'
    case AclProtocol.ICMP: return 'ICMP'
    case AclProtocol.ICMPv6: return 'ICMPv6'
    default: return t('event.Unknown')
  }
}

function getActionLabel(action: AclAction) {
  switch (action) {
    case AclAction.Allow: return t('acl.allow')
    case AclAction.Drop: return t('acl.drop')
    default: return t('event.Unknown')
  }
}

function addRule() {
  editingRuleIndex.value = -1
  editingRule.value = {
    name: '',
    description: '',
    priority: rules().length,
    enabled: true,
    protocol: AclProtocol.Any,
    ports: [],
    source_ips: [],
    destination_ips: [],
    source_ports: [],
    action: AclAction.Allow,
    rate_limit: 0,
    burst_limit: 0,
    stateful: false,
    source_groups: [],
    destination_groups: [],
  }
  showRuleDialog.value = true
}

function editRule(index: number) {
  editingRuleIndex.value = index
  editingRule.value = ensureAclRuleLists(JSON.parse(JSON.stringify(rules()[index])))
  showRuleDialog.value = true
}

function deleteRule(index: number) {
  rules().splice(index, 1)
}

function saveRule(rule: AclRule) {
  const chainRules = rules()
  ensureAclRuleLists(rule)
  if (editingRuleIndex.value === -1) {
    chainRules.push(rule)
  } else {
    chainRules[editingRuleIndex.value] = rule
  }
  chainRules.sort((a, b) => (b.priority || 0) - (a.priority || 0))
}

function onDragStart(index: number) {
  dragIndex.value = index
  dragOverIndex.value = index
}

function onDragOver(index: number) {
  dragOverIndex.value = index
}

function onDrop() {
  const from = dragIndex.value
  const to = dragOverIndex.value
  if (from === null || to === null || from === to) {
    resetDrag()
    return
  }
  const chainRules = rules()
  const [moved] = chainRules.splice(from, 1)
  chainRules.splice(to, 0, moved)
  // Update priorities based on new order (higher priority at top)
  chainRules.forEach((rule, index) => {
    rule.priority = chainRules.length - index - 1
  })
  resetDrag()
}

function resetDrag() {
  dragIndex.value = null
  dragOverIndex.value = null
}
</script>

<template>
  <div class="d-flex flex-column ga-6">
    <!-- Chain Metadata Section -->
    <div class="acl-meta-grid">
      <div class="d-flex flex-column ga-2">
        <label class="font-weight-bold text-body-2">{{ t('acl.chain.name') }}</label>
        <v-text-field v-model="chain.name" variant="outlined" density="compact" hide-details />
      </div>
      <div class="d-flex flex-column ga-2">
        <label class="font-weight-bold text-body-2">{{ t('acl.rule.description') }}</label>
        <v-text-field v-model="chain.description" variant="outlined" density="compact" hide-details />
      </div>

      <div class="d-flex align-center flex-wrap ga-6 acl-meta-row">
        <div class="d-flex align-center ga-2">
          <label class="font-weight-bold text-body-2">{{ t('acl.rule.enabled') }}</label>
          <v-switch v-model="chain.enabled" color="primary" hide-details />
        </div>
        <div class="d-flex align-center ga-2">
          <label class="font-weight-bold text-body-2">{{ t('acl.chain.type') }}</label>
          <v-select
            :model-value="chain.chain_type"
            :items="chainTypeOptions"
            :item-title="opt => typeof opt.label === 'function' ? opt.label() : opt.label"
            item-value="value"
            variant="outlined"
            density="compact"
            hide-details
            class="max-w-40"
            @update:model-value="chain.chain_type = $event"
          />
        </div>
        <div class="d-flex align-center ga-2 ml-auto">
          <label class="font-weight-bold text-body-2">{{ t('acl.default_action') }}</label>
          <v-btn-toggle v-model="chain.default_action" density="comfortable" divided>
            <v-btn v-for="opt in actionOptions" :key="opt.value" :value="opt.value">
              {{ typeof opt.label === 'function' ? opt.label() : opt.label }}
            </v-btn>
          </v-btn-toggle>
        </div>
      </div>
    </div>

    <div class="d-flex flex-row align-center ga-4 justify-space-between">
      <h4 class="text-subtitle-1 font-weight-bold">{{ t('acl.rules') }}</h4>
      <v-btn color="success" :prepend-icon="'mdi-plus'" size="small" @click="addRule">{{ t('acl.add_rule') }}</v-btn>
    </div>

    <!-- Rules table with drag-to-reorder -->
    <v-table density="comfortable" class="rounded-lg acl-table">
      <thead>
        <tr>
          <th style="width: 3rem">#</th>
          <th style="width: 2.5rem">{{ t('acl.rule.enabled') }}</th>
          <th>{{ t('acl.rule.name') }}</th>
          <th>{{ t('acl.match') }}</th>
          <th>{{ t('acl.rule.action') }}</th>
          <th class="text-end" style="width: 6rem">{{ t('web.common.edit') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="(rule, index) in rules()"
          :key="index"
          :draggable="true"
          class="acl-row"
          :class="{ 'acl-row-dragover': dragOverIndex === index, 'acl-row-dragging': dragIndex === index }"
          @dragstart="onDragStart(index)"
          @dragover.prevent="onDragOver(index)"
          @drop.prevent="onDrop"
          @dragend="resetDrag"
        >
          <td class="acl-drag-handle" title="drag to reorder">
            <v-icon size="small">mdi-drag-horizontal-variant</v-icon>
          </td>
          <td>
            <v-icon size="small" :color="rule.enabled ? 'success' : 'error'">
              {{ rule.enabled ? 'mdi-check-circle' : 'mdi-close-circle' }}
            </v-icon>
          </td>
          <td>{{ rule.name }}</td>
          <td>
            <div class="d-flex flex-column ga-2 py-1">
              <div class="d-flex align-center ga-2">
                <span class="acl-proto-badge">{{ getProtocolLabel(rule.protocol) }}</span>
              </div>
              <div class="d-flex flex-column acl-match-row">
                <div class="d-flex align-center ga-1 acl-src-dst">
                  <span class="acl-label">Src</span>
                  <div class="d-flex flex-wrap ga-1 align-center">
                    <span v-for="ip in rule.source_ips" :key="ip" class="acl-ip">{{ ip }}</span>
                    <span v-for="grp in rule.source_groups" :key="grp" class="acl-group">@{{ grp }}</span>
                    <span v-if="rule.source_ports.length" class="acl-port">:{{ rule.source_ports.join(',') }}</span>
                    <span v-if="!rule.source_ips.length && !rule.source_groups.length" class="acl-any">*</span>
                  </div>
                </div>
                <v-icon size="small" class="my-1 acl-arrow">mdi-arrow-right</v-icon>
                <div class="d-flex align-center ga-1 acl-src-dst">
                  <span class="acl-label">Dst</span>
                  <div class="d-flex flex-wrap ga-1 align-center">
                    <span v-for="ip in rule.destination_ips" :key="ip" class="acl-ip">{{ ip }}</span>
                    <span v-for="grp in rule.destination_groups" :key="grp" class="acl-group">@{{ grp }}</span>
                    <span v-if="rule.ports.length" class="acl-port">:{{ rule.ports.join(',') }}</span>
                    <span v-if="!rule.destination_ips.length && !rule.destination_groups.length" class="acl-any">*</span>
                  </div>
                </div>
              </div>
            </div>
          </td>
          <td>
            <span :class="rule.action === AclAction.Allow ? 'acl-allow' : 'acl-drop'">
              {{ getActionLabel(rule.action) }}
            </span>
          </td>
          <td class="text-end">
            <div class="d-flex justify-end ga-1">
              <v-btn icon="mdi-pencil" variant="text" size="small" rounded @click="editRule(index)" />
              <v-btn icon="mdi-delete" color="error" variant="text" size="small" rounded @click="deleteRule(index)" />
            </div>
          </td>
        </tr>
        <tr v-if="rules().length === 0">
          <td colspan="6" class="text-center acl-no-rules">
            {{ t('acl.rules') }} — 
          </td>
        </tr>
      </tbody>
    </v-table>

    <AclRuleDialog v-if="showRuleDialog && editingRule" v-model:visible="showRuleDialog" v-model:rule="editingRule"
      :group-names="props.groupNames" @save="saveRule" />
  </div>
</template>

<style scoped>
.acl-meta-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 1rem;
  padding: 1rem;
  background: var(--v-theme-surfaceContainerLow);
  border-radius: 12px;
  border: 1px solid var(--v-theme-outlineVariant);
}
@media (min-width: 768px) {
  .acl-meta-grid {
    grid-template-columns: 1fr 1fr;
  }
  .acl-meta-row {
    grid-column: span 2;
    border-top: 1px solid var(--v-theme-outlineVariant);
    padding-top: 0.75rem;
    margin-top: 0.5rem;
  }
}
.acl-table {
  border: 1px solid var(--v-theme-outlineVariant);
  background: var(--v-theme-surface);
}
.acl-row {
  cursor: default;
}
.acl-row-dragover {
  outline: 2px dashed var(--v-theme-primary);
  outline-offset: -2px;
}
.acl-row-dragging {
  opacity: 0.4;
}
.acl-drag-handle {
  cursor: grab;
  color: var(--v-theme-onSurfaceVariant);
}
.acl-proto-badge {
  padding: 2px 8px;
  background: var(--v-theme-primaryContainer);
  color: var(--v-theme-onPrimaryContainer);
  border-radius: 6px;
  font-size: 0.65rem;
  font-weight: bold;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.acl-match-row {
  flex-direction: row;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
}
@media (min-width: 640px) {
  .acl-match-row {
    flex-direction: row;
  }
}
.acl-src-dst {
  min-width: 0;
  flex-wrap: wrap;
}
.acl-label {
  font-size: 0.6rem;
  font-weight: bold;
  text-transform: uppercase;
  color: var(--v-theme-onSurfaceVariant);
  width: 1.75rem;
}
.acl-ip {
  font-family: "Roboto Mono", ui-monospace, monospace;
  font-size: 0.75rem;
  background: var(--v-theme-surfaceContainerHighest);
  padding: 1px 6px;
  border-radius: 4px;
}
.acl-group {
  font-size: 0.75rem;
  font-weight: bold;
  color: #9d5cff;
}
.acl-port {
  font-size: 0.75rem;
  color: var(--v-theme-primary);
  font-family: "Roboto Mono", ui-monospace, monospace;
}
.acl-any {
  color: var(--v-theme-onSurfaceVariant);
}
.acl-arrow {
  color: var(--v-theme-outline);
  transform: rotate(90deg);
}
@media (min-width: 640px) {
  .acl-arrow {
    transform: none;
  }
}
.acl-allow {
  color: var(--v-theme-success);
}
.acl-drop {
  color: var(--v-theme-error);
  font-weight: bold;
}
.acl-no-rules {
  color: var(--v-theme-onSurfaceVariant);
  padding: 1rem;
}
</style>
