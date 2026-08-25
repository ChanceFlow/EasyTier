<script setup lang="ts">
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { AclAction, AclProtocol, AclRule, ensureAclRuleLists } from '../../types/network';

const props = defineProps<{
  visible: boolean
  groupNames?: string[]
}>()

const emit = defineEmits(['update:visible', 'save'])

const rule = defineModel<AclRule>('rule', { required: true })

const { t } = useI18n()

const protocolOptions = [
  { label: () => t('acl.any'), value: AclProtocol.Any },
  { label: 'TCP', value: AclProtocol.TCP },
  { label: 'UDP', value: AclProtocol.UDP },
  { label: 'ICMP', value: AclProtocol.ICMP },
  { label: 'ICMPv6', value: AclProtocol.ICMPv6 },
]

const actionOptions = [
  { label: () => t('acl.allow'), value: AclAction.Allow },
  { label: () => t('acl.drop'), value: AclAction.Drop },
]

const showPorts = computed(() => {
  return rule.value.protocol === AclProtocol.TCP || rule.value.protocol === AclProtocol.UDP || rule.value.protocol === AclProtocol.Any
})

watch(() => rule.value, ensureAclRuleLists, { immediate: true })

function close() {
  emit('update:visible', false)
}

function save() {
  emit('save', rule.value)
  close()
}

// Suggestions for IP/Port AutoComplete — v-combobox is free-input so no suggestions needed
</script>

<template>
  <v-dialog :model-value="visible" @update:model-value="emit('update:visible', $event)" max-width="600px">
    <v-card :title="t('acl.edit_rule')">
      <v-card-text class="d-flex flex-column ga-4">
        <div class="d-flex ga-4 align-center">
          <div class="d-flex flex-column ga-2 flex-grow-1">
            <label class="font-weight-bold">{{ t('acl.rule.name') }}</label>
            <v-text-field v-model="rule.name" variant="outlined" hide-details />
          </div>
          <div class="d-flex flex-column ga-2">
            <label class="font-weight-bold">{{ t('acl.rule.enabled') }}</label>
            <v-switch v-model="rule.enabled" color="primary" hide-details />
          </div>
        </div>

        <div class="d-flex flex-column ga-2">
          <label class="font-weight-bold">{{ t('acl.rule.description') }}</label>
          <v-text-field v-model="rule.description" variant="outlined" hide-details />
        </div>

        <div class="d-flex ga-4 flex-wrap">
          <div class="d-flex flex-column ga-2 flex-grow-1">
            <label class="font-weight-bold">{{ t('acl.rule.action') }}</label>
            <v-btn-toggle v-model="rule.action" density="comfortable" divided class="align-self-start">
              <v-btn v-for="opt in actionOptions" :key="opt.value" :value="opt.value">
                {{ typeof opt.label === 'function' ? opt.label() : opt.label }}
              </v-btn>
            </v-btn-toggle>
          </div>
          <div class="d-flex flex-column ga-2 flex-grow-1">
            <label class="font-weight-bold">{{ t('acl.rule.protocol') }}</label>
            <v-btn-toggle v-model="rule.protocol" density="comfortable" divided class="align-self-start">
              <v-btn v-for="opt in protocolOptions" :key="opt.value" :value="opt.value">
                {{ typeof opt.label === 'function' ? opt.label() : opt.label }}
              </v-btn>
            </v-btn-toggle>
          </div>
        </div>

        <!-- Match section -->
        <v-expansion-panels variant="accordion">
          <v-expansion-panel :title="t('acl.rules')">
            <template #text>
              <div class="d-flex flex-column ga-4">
                <div class="d-flex flex-column ga-2">
                  <label class="font-weight-bold">{{ t('acl.rule.src_ips') }}</label>
                  <v-combobox
                    v-model="rule.source_ips"
                    multiple
                    chips
                    closable-chips
                    variant="outlined"
                    density="compact"
                    hide-details
                    :placeholder="t('chips_placeholder', ['10.126.126.0/24'])"
                  />
                </div>
                <div class="d-flex flex-column ga-2">
                  <label class="font-weight-bold">{{ t('acl.rule.dst_ips') }}</label>
                  <v-combobox
                    v-model="rule.destination_ips"
                    multiple
                    chips
                    closable-chips
                    variant="outlined"
                    density="compact"
                    hide-details
                    :placeholder="t('chips_placeholder', ['10.126.126.2/32'])"
                  />
                </div>

                <div v-if="showPorts" class="d-flex ga-4 flex-wrap">
                  <div class="d-flex flex-column ga-2 flex-grow-1">
                    <label class="font-weight-bold">{{ t('acl.rule.src_ports') }}</label>
                    <v-combobox
                      v-model="rule.source_ports"
                      multiple
                      chips
                      closable-chips
                      variant="outlined"
                      density="compact"
                      hide-details
                      placeholder="e.g. 80, 1000-2000"
                    />
                  </div>
                  <div class="d-flex flex-column ga-2 flex-grow-1">
                    <label class="font-weight-bold">{{ t('acl.rule.dst_ports') }}</label>
                    <v-combobox
                      v-model="rule.ports"
                      multiple
                      chips
                      closable-chips
                      variant="outlined"
                      density="compact"
                      hide-details
                      placeholder="e.g. 80, 1000-2000"
                    />
                  </div>
                </div>
              </div>
            </template>
          </v-expansion-panel>
        </v-expansion-panels>

        <!-- Advanced settings -->
        <v-expansion-panels variant="accordion">
          <v-expansion-panel :title="t('advanced_settings')">
            <template #text>
              <div class="d-flex flex-column ga-4">
                <div class="d-flex align-center ga-2">
                  <v-checkbox v-model="rule.stateful" color="primary" hide-details class="mt-0" />
                  <label class="font-weight-bold">{{ t('acl.rule.stateful') }}</label>
                </div>

                <div class="d-flex ga-4 flex-wrap">
                  <div class="d-flex flex-column ga-2 flex-grow-1">
                    <label class="font-weight-bold">{{ t('acl.rule.rate_limit') }}</label>
                    <v-text-field
                      :model-value="rule.rate_limit"
                      type="number"
                      variant="outlined"
                      density="compact"
                      hide-details
                      :placeholder="'0 = no limit'"
                      @update:model-value="rule.rate_limit = $event === '' ? 0 : Number($event)"
                    />
                  </div>
                  <div class="d-flex flex-column ga-2 flex-grow-1">
                    <label class="font-weight-bold">{{ t('acl.rule.burst_limit') }}</label>
                    <v-text-field
                      :model-value="rule.burst_limit"
                      type="number"
                      variant="outlined"
                      density="compact"
                      hide-details
                      :placeholder="'0 = no limit'"
                      @update:model-value="rule.burst_limit = $event === '' ? 0 : Number($event)"
                    />
                  </div>
                </div>

                <div class="d-flex flex-column ga-2">
                  <label class="font-weight-bold">{{ t('acl.rule.src_groups') }}</label>
                  <v-select
                    v-model="rule.source_groups"
                    :items="props.groupNames"
                    multiple
                    chips
                    closable-chips
                    variant="outlined"
                    density="compact"
                    hide-details
                    :placeholder="t('acl.rule.src_groups')"
                  />
                </div>
                <div class="d-flex flex-column ga-2">
                  <label class="font-weight-bold">{{ t('acl.rule.dst_groups') }}</label>
                  <v-select
                    v-model="rule.destination_groups"
                    :items="props.groupNames"
                    multiple
                    chips
                    closable-chips
                    variant="outlined"
                    density="compact"
                    hide-details
                    :placeholder="t('acl.rule.dst_groups')"
                  />
                </div>
              </div>
            </template>
          </v-expansion-panel>
        </v-expansion-panels>
      </v-card-text>

      <v-card-actions>
        <v-spacer />
        <v-btn variant="text" @click="close">{{ t('web.common.cancel') }}</v-btn>
        <v-btn color="primary" variant="flat" :prepend-icon="'mdi-content-save'" @click="save">{{ t('web.common.save') }}</v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>
