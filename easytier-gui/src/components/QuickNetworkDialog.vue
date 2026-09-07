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
    <v-card rounded="xl" class="et-dialog-card pa-3">
      <div class="d-flex align-center ga-3 px-3 pt-2">
        <div class="et-squircle" style="background: var(--et-accent-dim);">
          <v-icon size="20" color="primary">mdi-shield-plus-outline</v-icon>
        </div>
        <div>
          <div class="text-subtitle-1 font-weight-bold">
            {{ pt('dialog.create_network_title', '创建网络配置', 'Create Network Config') }}
          </div>
          <div class="text-caption text-medium-emphasis">
            {{ pt('dialog.create_hint', '加入现有虚拟网或新建独立网络', 'Join an existing mesh or create a new network') }}
          </div>
        </div>
      </div>

      <v-card-text class="d-flex flex-column ga-3 px-3 pt-4">
        <div>
          <label class="text-caption font-weight-medium mb-1 d-block text-medium-emphasis">
            {{ pt('dialog.network_name', '网络名称', 'Network name') }}
          </label>
          <v-text-field
            v-model="networkName"
            variant="outlined"
            density="compact"
            hide-details
            placeholder="easytier"
            prepend-inner-icon="mdi-label-outline"
          />
        </div>

        <div>
          <label class="text-caption font-weight-medium mb-1 d-block text-medium-emphasis">
            {{ pt('dialog.network_secret', '网络密码', 'Network secret') }}
          </label>
          <v-text-field
            v-model="networkSecret"
            variant="outlined"
            density="compact"
            hide-details
            type="password"
            prepend-inner-icon="mdi-lock-outline"
            :placeholder="pt('dialog.secret_placeholder', '相同密码加入同一网络', 'Same secret to join the same network')"
          />
        </div>

        <div>
          <div class="d-flex align-center justify-space-between mb-1">
            <label class="text-caption font-weight-medium text-medium-emphasis">
              {{ pt('dialog.peer_url', '公共引导节点 (选填)', 'Peer node (optional)') }}
            </label>
            <span
              v-if="!peerUrl"
              class="text-caption text-primary cursor-pointer font-weight-medium"
              style="font-size: 0.75rem;"
              @click="peerUrl = 'tcp://public.easytier.top:11010'"
            >
              {{ pt('dialog.use_official', '填入官方节点', 'Use official node') }}
            </span>
          </div>
          <v-text-field
            v-model="peerUrl"
            variant="outlined"
            density="compact"
            hide-details
            prepend-inner-icon="mdi-server-network"
            placeholder="tcp://public.easytier.top:11010"
          />
        </div>

        <div class="et-group pa-2 mt-1">
          <v-switch
            v-model="dhcp"
            color="primary"
            :label="pt('dialog.dhcp', '自动分配 IP (DHCP)', 'Auto assign IP (DHCP)')"
            hide-details
            inset
            density="compact"
          />
        </div>
      </v-card-text>

      <v-card-actions class="px-3 pb-2 pt-0">
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
