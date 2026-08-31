<script setup lang="ts">
import { ref, watch } from 'vue'
import { useDisplay } from 'vuetify'
import { usePhoneText } from '~/composables/hero_text'

const props = defineProps<{
  modelValue: boolean
  loading?: boolean
}>()

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void
  (e: 'create', form: { name: string, secret: string, dhcp: boolean, peerUrl: string }): void
}>()

const { pt } = usePhoneText()
const { t } = useI18n()
const { smAndDown: mobileUI } = useDisplay()

const networkName = ref('easytier')
const networkSecret = ref('')
const dhcp = ref(true)
const peerUrl = ref('')

watch(() => props.modelValue, (visible) => {
  if (visible) {
    networkName.value = 'easytier'
    networkSecret.value = ''
    dhcp.value = true
    peerUrl.value = ''
  }
})

function submit() {
  emit('create', {
    name: networkName.value.trim() || 'easytier',
    secret: networkSecret.value.trim(),
    dhcp: dhcp.value,
    peerUrl: peerUrl.value.trim(),
  })
}
</script>

<template>
  <v-dialog
    :model-value="props.modelValue"
    max-width="480px"
    :fullscreen="mobileUI"
    @update:model-value="emit('update:modelValue', $event)"
  >
    <v-card rounded="xl" class="et-dialog-card pa-2">
      <v-card-title class="text-subtitle-1 font-weight-bold pt-3 px-4">
        {{ pt('dialog.create_network_title', '创建网络配置', 'Create Network Config') }}
      </v-card-title>
      <v-card-text class="d-flex flex-column ga-3 px-4 pt-2">
        <div>
          <label class="text-caption font-weight-medium mb-1 d-block">
            {{ pt('dialog.network_name', '网络名称', 'Network name') }}
          </label>
          <v-text-field
            v-model="networkName"
            variant="outlined"
            density="comfortable"
            hide-details
            placeholder="easytier"
          />
        </div>

        <div>
          <label class="text-caption font-weight-medium mb-1 d-block">
            {{ pt('dialog.network_secret', '网络密码', 'Network secret') }}
          </label>
          <v-text-field
            v-model="networkSecret"
            variant="outlined"
            density="comfortable"
            hide-details
            type="password"
            :placeholder="pt('dialog.secret_placeholder', '相同密码加入同一网络', 'Same secret to join the same network')"
          />
        </div>

        <div>
          <label class="text-caption font-weight-medium mb-1 d-block">
            {{ pt('dialog.peer_url', '公共节点 (选填)', 'Peer node (optional)') }}
          </label>
          <v-text-field
            v-model="peerUrl"
            variant="outlined"
            density="comfortable"
            hide-details
            placeholder="tcp://public.easytier.top:11010"
          />
        </div>

        <v-switch
          v-model="dhcp"
          color="primary"
          :label="pt('dialog.dhcp', '自动分配 IP (DHCP)', 'Auto assign IP (DHCP)')"
          hide-details
          density="comfortable"
        />
      </v-card-text>
      <v-card-actions class="px-4 pb-3">
        <v-spacer />
        <v-btn
          variant="text"
          rounded="pill"
          :disabled="props.loading"
          @click="emit('update:modelValue', false)"
        >
          {{ t('web.common.cancel') }}
        </v-btn>
        <v-btn
          color="primary"
          variant="flat"
          rounded="pill"
          :loading="props.loading"
          prepend-icon="mdi-plus"
          @click="submit"
        >
          {{ pt('hero.action_create', '创建网络', 'Create Network') }}
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>
