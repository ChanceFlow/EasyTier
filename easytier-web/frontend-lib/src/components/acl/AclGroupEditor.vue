<script setup lang="ts">
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { GroupIdentity, GroupInfo, ensureGroupInfo } from '../../types/network';

const props = defineProps<{
  groupNames?: string[]
}>()

const group = defineModel<GroupInfo>({ required: true })
const emit = defineEmits(['rename-group'])

const { t } = useI18n()

const editingGroup = ref<GroupIdentity | null>(null)
const editingGroupIndex = ref(-1)
const showGroupDialog = ref(false)
const oldGroupName = ref('')

function groupInfo() {
  return ensureGroupInfo(group.value)
}

const members = computed({
  get: () => groupInfo().members,
  set: value => {
    groupInfo().members = value
  },
})

const declares = computed(() => groupInfo().declares)

function addGroup() {
  editingGroupIndex.value = -1
  editingGroup.value = {
    group_name: '',
    group_secret: '',
  }
  oldGroupName.value = ''
  showGroupDialog.value = true
}

function editGroup(index: number) {
  editingGroupIndex.value = index
  editingGroup.value = JSON.parse(JSON.stringify(groupInfo().declares[index]))
  oldGroupName.value = editingGroup.value?.group_name || ''
  showGroupDialog.value = true
}

function deleteGroup(index: number) {
  groupInfo().declares.splice(index, 1)
}

function saveGroup() {
  if (!editingGroup.value) return
  const newName = editingGroup.value.group_name

  if (editingGroupIndex.value === -1) {
    groupInfo().declares.push(editingGroup.value)
  } else {
    if (oldGroupName.value && oldGroupName.value !== newName) {
      // Sync in members
      groupInfo().members = groupInfo().members.map(m => m === oldGroupName.value ? newName : m)
      // Notify parent to sync in rules
      emit('rename-group', { oldName: oldGroupName.value, newName })
    }
    groupInfo().declares[editingGroupIndex.value] = editingGroup.value
  }
  showGroupDialog.value = false
}

</script>

<template>
  <div class="d-flex flex-column ga-6">
    <div class="d-flex flex-column ga-2">
      <div class="d-flex justify-space-between align-center">
        <div class="d-flex flex-column">
          <label class="font-weight-bold text-h6">{{ t('acl.group.declares') }}</label>
          <small class="acl-muted">{{ t('acl.group.help') }}</small>
        </div>
        <v-btn color="success" :prepend-icon="'mdi-plus'" @click="addGroup">{{ t('web.common.add') }}</v-btn>
      </div>

      <v-table density="comfortable" class="rounded-lg acl-table">
        <thead>
          <tr>
            <th>{{ t('acl.group.name') }}</th>
            <th>{{ t('acl.group.secret') }}</th>
            <th class="text-end" style="width: 8rem">{{ t('web.common.edit') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(item, index) in declares" :key="index">
            <td>{{ item.group_name }}</td>
            <td class="acl-secret">
              <v-text-field
                :model-value="item.group_secret"
                :type="'password'"
                hide-details
                density="compact"
                variant="outlined"
                readonly
                class="max-w-64"
              />
            </td>
            <td class="text-end">
              <div class="d-flex justify-end ga-1">
                <v-btn icon="mdi-pencil" variant="text" size="small" rounded @click="editGroup(index)" />
                <v-btn icon="mdi-delete" color="error" variant="text" size="small" rounded @click="deleteGroup(index)" />
              </div>
            </td>
          </tr>
        </tbody>
      </v-table>
    </div>

    <div class="d-flex flex-column ga-2">
      <label class="font-weight-bold text-h6">{{ t('acl.group.members') }}</label>
      <v-select
        v-model="members"
        :items="props.groupNames"
        multiple
        chips
        closable-chips
        density="compact"
        variant="outlined"
        :label="t('acl.group.members')"
        :placeholder="t('acl.group.members')"
        hide-details
      />
    </div>

    <!-- Group Identity Dialog -->
    <v-dialog v-model="showGroupDialog" max-width="400px">
      <v-card :title="t('acl.groups')">
        <v-card-text>
          <div v-if="editingGroup" class="d-flex flex-column ga-4 pt-2">
            <div class="d-flex flex-column ga-2">
              <label class="font-weight-bold">{{ t('acl.group.name') }}</label>
              <v-text-field v-model="editingGroup.group_name" variant="outlined" hide-details />
            </div>
            <div class="d-flex flex-column ga-2">
              <label class="font-weight-bold">{{ t('acl.group.secret') }}</label>
              <v-text-field
                v-model="editingGroup.group_secret"
                variant="outlined"
                hide-details
                :type="showGroupSecret ? 'text' : 'password'"
                :append-inner-icon="showGroupSecret ? 'mdi-eye-off' : 'mdi-eye'"
                @click:append-inner="showGroupSecret = !showGroupSecret"
              />
            </div>
          </div>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="showGroupDialog = false">{{ t('web.common.cancel') }}</v-btn>
          <v-btn color="primary" variant="flat" :prepend-icon="'mdi-content-save'" @click="saveGroup">{{ t('web.common.save') }}</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script lang="ts">
export default {
  data() {
    return {
      showGroupSecret: false,
    }
  },
}
</script>

<style scoped>
.acl-muted {
  color: var(--v-theme-onSurfaceVariant);
}
.acl-table {
  border: 1px solid var(--v-theme-outlineVariant);
  background: var(--v-theme-surface);
}
.acl-secret {
  max-width: 20rem;
}
</style>
