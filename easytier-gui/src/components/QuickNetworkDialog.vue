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
const PEER_URL_SCHEMES = 'tcp:// · udp:// · ws:// · wss:// · wg:// · quic://'

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
  // name the exact segment that is wrong (MASTER §4: say which part failed,
  // not just "invalid format")
  const scheme = /^([a-z][a-z0-9+.-]*):\/\//i.exec(value)?.[1]
  if (scheme) {
    return pt(
      'quick_network.peer_url_scheme',
      `不支持的协议「${scheme}://」，可用：${PEER_URL_SCHEMES}`,
      `Unsupported scheme “${scheme}://” — use ${PEER_URL_SCHEMES}`,
    )
  }
  return pt(
    'quick_network.peer_url_missing_scheme',
    `缺少协议前缀，需要写成 协议://主机:端口，例如 tcp://public.easytier.top:11010（可用：${PEER_URL_SCHEMES}）`,
    `Missing the scheme — write scheme://host:port, e.g. tcp://public.easytier.top:11010 (supported: ${PEER_URL_SCHEMES})`,
  )
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
    <v-card rounded="xl" class="et-dialog-card et-quick-card pa-3">
      <div class="d-flex align-center ga-3 px-3 pt-2">
        <div class="et-squircle" style="background: var(--et-accent-quiet);">
          <v-icon size="20" color="primary">
            mdi-shield-plus-outline
          </v-icon>
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
            :aria-invalid="nameError ? 'true' : 'false'"
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
            :aria-invalid="secretError ? 'true' : 'false'"
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
              class="et-inline-btn text-primary font-weight-medium"
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
            :aria-invalid="peerUrlError ? 'true' : 'false'"
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
/* MASTER §4 输入框: the control border is --et-control-border (>= 3:1), not
   Vuetify's 38 %-opacity theme outline; the focus ring is a 2px --et-focus
   outline (>= 3:1 on both surfaces). Field errors stay red and are declared
   last so they win over the focused state. */
.et-quick-card :deep(.v-field--variant-outlined .v-field__outline) {
  color: var(--et-control-border);
  --v-field-border-opacity: 1;
}

.et-quick-card :deep(.v-field--variant-outlined.v-field--focused .v-field__outline) {
  color: var(--et-focus);
}

.et-quick-card :deep(.v-field--variant-outlined.v-field--error .v-field__outline) {
  color: var(--et-danger);
}

/* show/hide secret toggle rendered inside the field's append-inner slot */
.et-field-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: var(--et-touch-min);
  height: var(--et-touch-min);
  /* keep the compact field height while still offering a large tap target */
  margin-block: calc(var(--et-space-1) * -1);
  margin-inline-end: calc(var(--et-space-1) * -1);
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

.et-field-icon-btn:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: 2px;
  border-radius: var(--et-radius-sm);
}

/* "use official node" is now a real button: reset the UA chrome, keep the
   previous caption look */
.et-inline-btn {
  padding: var(--et-space-1) 0;
  border: 0;
  background: none;
  font-family: inherit;
  font-size: var(--et-font-caption);
  cursor: pointer;
}

.et-inline-btn:focus-visible {
  outline: 2px solid var(--et-focus);
  outline-offset: 2px;
  border-radius: var(--et-radius-xs);
}
</style>
