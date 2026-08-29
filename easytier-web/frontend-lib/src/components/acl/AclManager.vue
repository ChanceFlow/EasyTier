<script setup lang="ts">
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { Acl, AclAction, AclChainType, ensureAclV1 } from '../../types/network'
import AclChainEditor from './AclChainEditor.vue'
import AclGroupEditor from './AclGroupEditor.vue'

const acl = defineModel<Acl>({ required: true })

const { t } = useI18n()

const activeTab = ref(0)
const menuOpen = ref(false)
const menuX = ref(0)
const menuY = ref(0)
const aclV1 = computed(() => ensureAclV1(acl.value))

function openMenu(e: Event) {
  menuX.value = (e as MouseEvent).clientX
  menuY.value = (e as MouseEvent).clientY
  menuOpen.value = true
}

function addChain(type: AclChainType) {
  let defaultName = ''
  switch (type) {
    case AclChainType.Inbound: defaultName = 'Inbound'; break;
    case AclChainType.Outbound: defaultName = 'Outbound'; break;
    case AclChainType.Forward: defaultName = 'Forward'; break;
  }

  aclV1.value.chains.push({
    name: defaultName,
    chain_type: type,
    description: '',
    enabled: true,
    rules: [],
    default_action: AclAction.Allow
  })

  activeTab.value = aclV1.value.chains.length - 1
  menuOpen.value = false
}

function removeChain(index: number) {
  if (window.confirm(t('acl.delete_chain_confirm'))) {
    aclV1.value.chains.splice(index, 1)
    if (activeTab.value >= aclV1.value.chains.length) {
      activeTab.value = Math.max(0, aclV1.value.chains.length)
    }
  }
}

function handleRenameGroup({ oldName, newName }: { oldName: string, newName: string }) {
  aclV1.value.chains.forEach(chain => {
    chain.rules.forEach(rule => {
      rule.source_groups = rule.source_groups.map(g => g === oldName ? newName : g)
      rule.destination_groups = rule.destination_groups.map(g => g === oldName ? newName : g)
    })
  })
}

const groupNames = computed(() => {
  return aclV1.value.group?.declares.map(g => g.group_name) || []
})

const tabs = computed(() => {
  const chains = aclV1.value.chains
  const result: { type: string, label: string, index: number }[] = []

  if (chains.length === 0) {
    result.push({ type: 'empty', label: t('acl.chains'), index: 0 })
  }
  else {
    chains.forEach((c, index) => {
      result.push({
        type: 'chain',
        label: c.name || `Chain ${index}`,
        index
      })
    })
  }

  result.push({ type: 'groups', label: t('acl.groups'), index: result.length })
  return result
})
</script>

<template>
  <div class="d-flex flex-column ga-4">
    <div class="d-flex align-center acl-tabs-row">
      <v-tabs v-model="activeTab" show-arrows density="comfortable" class="flex-grow-1">
        <v-tab v-for="tab in tabs" :key="tab.type + tab.index" :value="tab.index" class="acl-tab">
          <div class="d-flex align-center ga-1">
            <span class="whitespace-nowrap">{{ tab.label }}</span>
            <v-btn
              v-if="tab.type === 'chain'"
              icon="mdi-close"
              variant="text"
              color="error"
              size="x-small"
              density="comfortable"
              @click.stop="removeChain(tab.index)"
            />
          </div>
        </v-tab>
      </v-tabs>

      <v-btn icon="mdi-plus" variant="text" size="small" rounded @click="openMenu" />
      <v-menu v-model="menuOpen" :position-x="menuX" :position-y="menuY" location="bottom end">
        <v-list density="comfortable" min-width="160">
          <v-list-item @click="addChain(AclChainType.Inbound)">
            <v-list-item-title>{{ t('acl.inbound') }}</v-list-item-title>
          </v-list-item>
          <v-list-item @click="addChain(AclChainType.Outbound)">
            <v-list-item-title>{{ t('acl.outbound') }}</v-list-item-title>
          </v-list-item>
          <v-list-item @click="addChain(AclChainType.Forward)">
            <v-list-item-title>{{ t('acl.forward') }}</v-list-item-title>
          </v-list-item>
        </v-list>
      </v-menu>
    </div>

    <!-- Tab content -->
    <v-window v-model="activeTab" class="acl-window">
      <v-window-item v-for="tab in tabs" :key="'panel' + tab.type + tab.index" :value="tab.index">
        <!-- Empty State -->
        <div v-if="tab.type === 'empty'" class="acl-empty">
          <v-icon size="56" color="primary">mdi-shield-lock</v-icon>
          <div class="text-h6 font-weight-bold mb-2">{{ t('acl.chains') }}</div>
          <p class="text-body-2 acl-help">{{ t('acl.help') }}</p>
          <div class="d-flex flex-wrap ga-2 justify-center">
            <v-btn color="primary" variant="flat" :prepend-icon="'mdi-arrow-bottom-left'" @click="addChain(AclChainType.Inbound)">
              {{ t('acl.inbound') }}
            </v-btn>
            <v-btn color="primary" variant="flat" :prepend-icon="'mdi-arrow-top-right'" @click="addChain(AclChainType.Outbound)">
              {{ t('acl.outbound') }}
            </v-btn>
            <v-btn color="primary" variant="flat" :prepend-icon="'mdi-directions'" @click="addChain(AclChainType.Forward)">
              {{ t('acl.forward') }}
            </v-btn>
          </div>
        </div>

        <!-- Rule Chains -->
        <div v-if="tab.type === 'chain' && aclV1.chains[tab.index]" class="py-4">
          <AclChainEditor v-model="aclV1.chains[tab.index]" :group-names="groupNames" />
        </div>

        <!-- Group Management -->
        <div v-if="tab.type === 'groups'" class="py-4">
          <AclGroupEditor v-model="aclV1.group" :group-names="groupNames" @rename-group="handleRenameGroup" />
        </div>
      </v-window-item>
    </v-window>
  </div>
</template>

<style scoped>
.acl-tabs-row {
  border-bottom: 1px solid var(--v-theme-outlineVariant);
}
.acl-tab {
  text-transform: none;
}
.acl-empty {
  padding: 2rem 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border: 2px dashed var(--v-theme-outlineVariant);
  border-radius: 12px;
  background: var(--v-theme-surfaceContainerLow);
  gap: 4px;
}
.acl-help {
  color: var(--v-theme-onSurfaceVariant);
  max-width: 24rem;
  text-align: center;
  padding: 0 1rem;
  margin-bottom: 1.5rem;
}
.whitespace-nowrap {
  white-space: nowrap;
}
</style>
