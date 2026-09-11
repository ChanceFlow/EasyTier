<script setup lang="ts">
import { computed, ref, watch } from 'vue'
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

const showSecret = ref(false)
const nameTouched = ref(false)
const secretTouched = ref(false)
const peerUrlTouched = ref(false)

const PEER_URL_PATTERN = /^(?:tcp|udp|ws|wss|wg|quic):\/\/\S+$/i

const nameError = computed(() =>
  nameTouched.value && !networkName.value.trim()
    ? t('quick_network.name_required', 'Network name is required')
    : '',
)
const secretError = computed(() =>
  secretTouched.value && !networkSecret.value.trim()
    ? t('quick_network.secret_required', 'Network secret is required — the same secret joins the same network')
    : '',
)
const peerUrlError = computed(() => {
  const value = peerUrl.value.trim()
  if (!value || !peerUrlTouched.value || PEER_URL_PATTERN.test(value))
    return ''
  // a soft warning only: an unknown scheme is flagged, but never hard-blocks
  return t('quick_network.peer_url_invalid', 'Use a supported scheme: tcp://, udp://, ws://, wss://, wg:// or quic://')
})
const formInvalid = computed(() => !networkName.value.trim() || !networkSecret.value.trim())

watch(() => props.modelValue, (visible) => {
  if (visible) {
    networkName.value = 'easytier'
    networkSecret.value = ''
    dhcp.value = true
    peerUrl.value = ''
    showSecret.value = false
    nameTouched.value = false
    secretTouched.value = false
    peerUrlTouched.value = false
  }
})

function submit() {
  if (props.loading || formInvalid.value)
    return
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
          <label for="quick-network-name" class="text-caption font-weight-medium mb-1 d-block text-medium-emphasis">
            {{ pt('dialog.network_name', '网络名称', 'Network name') }}
          </label>
          <v-text-field
            id="quick-network-name"
            v-model="networkName"
            variant="outlined"
            density="compact"
            hide-details="auto"
            placeholder="easytier"
            prepend-inner-icon="mdi-label-outline"
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            enterkeyhint="done"
            :error="!!nameError"
            :error-messages="nameError ? [nameError] : []"
            @blur="nameTouched = true"
          />
        </div>

        <div>
          <label for="quick-network-secret" class="text-caption font-weight-medium mb-1 d-block text-medium-emphasis">
            {{ pt('dialog.network_secret', '网络密码', 'Network secret') }}
          </label>
          <v-text-field
            id="quick-network-secret"
            v-model="networkSecret"
            :type="showSecret ? 'text' : 'password'"
            variant="outlined"
            density="compact"
            hide-details="auto"
            prepend-inner-icon="mdi-lock-outline"
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            enterkeyhint="done"
            :placeholder="pt('dialog.secret_placeholder', '相同密码加入同一网络', 'Same secret to join the same network')"
            :error="!!secretError"
            :error-messages="secretError ? [secretError] : []"
            @blur="secretTouched = true"
          >
            <!-- a real button (not :append-inner-icon) so aria-label /
                 aria-pressed land on the toggle itself -->
            <template #append-inner>
              <button
                type="button"
                class="et-field-icon-btn"
                :aria-label="showSecret ? t('quick_network.hide_secret', 'Hide secret') : t('quick_network.show_secret', 'Show secret')"
                :aria-pressed="showSecret"
                @click="showSecret = !showSecret"
              >
                <v-icon size="20">
                  {{ showSecret ? 'mdi-eye-off-outline' : 'mdi-eye-outline' }}
                </v-icon>
              </button>
            </template>
          </v-text-field>
        </div>

        <div>
          <div class="d-flex align-center justify-space-between mb-1">
            <label for="quick-network-peer" class="text-caption font-weight-medium text-medium-emphasis">
              {{ pt('dialog.peer_url', '公共引导节点 (选填)', 'Peer node (optional)') }}
            </label>
            <button
              v-if="!peerUrl"
              type="button"
              class="et-inline-btn text-caption text-primary font-weight-medium"
              style="font-size: 0.75rem;"
              :aria-label="t('quick_network.use_official_aria', 'Fill in the official public peer node')"
              @click="peerUrl = 'tcp://public.easytier.top:11010'"
            >
              {{ pt('dialog.use_official', '填入官方节点', 'Use official node') }}
            </button>
          </div>
          <v-text-field
            id="quick-network-peer"
            v-model="peerUrl"
            variant="outlined"
            density="compact"
            hide-details="auto"
            prepend-inner-icon="mdi-server-network"
            placeholder="tcp://public.easytier.top:11010"
            inputmode="url"
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            enterkeyhint="done"
            :error="!!peerUrlError"
            :error-messages="peerUrlError ? [peerUrlError] : []"
            @blur="peerUrlTouched = true"
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
          :disabled="props.loading || formInvalid"
          prepend-icon="mdi-plus"
          @click="submit"
        >
          {{ pt('hero.action_create', '创建网络', 'Create Network') }}
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<style scoped>
/* show/hide secret toggle rendered inside the field's append-inner slot */
.et-field-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  /* keep the compact field height while still offering a large tap target */
  margin-block: -4px;
  margin-inline-end: -4px;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

/* "use official node" is now a real button: reset the UA chrome, keep the
   previous caption look */
.et-inline-btn {
  padding: 2px 0;
  border: 0;
  background: none;
  font-family: inherit;
  cursor: pointer;
}
</style>
