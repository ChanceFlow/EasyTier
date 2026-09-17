<script setup lang="ts">
import { usePhoneText } from '~/composables/hero_text'

const props = defineProps<{ modelValue: boolean }>()
const emit = defineEmits<{
  (e: 'update:modelValue', v: boolean): void
}>()

const { pt } = usePhoneText()
const page = ref(0)
// stable ids double as the dot list keys and keep the page count single-sourced
const PAGE_IDS = ['intro', 'permissions', 'steps'] as const
const PAGES = PAGE_IDS.length

const SWIPE_MIN_DX = 48
let swipeStartX = 0
let swipeStartY = 0

function onTouchStart(e: TouchEvent) {
  const touch = e.touches[0]
  swipeStartX = touch?.clientX ?? 0
  swipeStartY = touch?.clientY ?? 0
}

function onTouchEnd(e: TouchEvent) {
  const touch = e.changedTouches[0]
  const dx = (touch?.clientX ?? 0) - swipeStartX
  const dy = (touch?.clientY ?? 0) - swipeStartY
  // a mostly-vertical drag is a scroll, never a page change
  if (Math.abs(dx) <= SWIPE_MIN_DX || Math.abs(dx) <= Math.abs(dy))
    return
  if (dx < 0 && page.value < PAGES - 1)
    page.value += 1
  else if (dx > 0 && page.value > 0)
    page.value -= 1
}

watch(() => props.modelValue, (open) => {
  if (open)
    page.value = 0
})

function finish() {
  localStorage.setItem('et_onboarded_v1', '1')
  emit('update:modelValue', false)
}

const headings = computed(() => [
  pt('onboard.skip', '跳过', 'Skip'),
  pt('onboard.next', '下一步', 'Next'),
  pt('onboard.start', '开始使用', 'Get started'),
  pt('onboard.back', '上一步', 'Back'),
])

const p1 = computed(() => ({
  title: pt('onboard.1.title', '一张属于你自己的网', 'Your own private network'),
  body: pt(
    'onboard.1.body',
    'EasyTier 把你的手机、电脑、NAS 直接连成加密的 P2P 内网——没有服务器中转，出门在外也像在同一个路由器下。',
    'EasyTier links your phone, laptop and NAS into one encrypted P2P network — no middleman server, so devices at home feel local wherever you are.',
  ),
}))

const p2Items = computed(() => [
  {
    icon: 'mdi-shield-lock-outline',
    title: pt('onboard.2.vpn.title', '建立 VPN 通道', 'Create a VPN tunnel'),
    body: pt('onboard.2.vpn.body', '系统需要授权，才能把流量送进虚拟网卡。', 'Android asks once so traffic can enter the virtual interface.'),
  },
  {
    icon: 'mdi-bell-outline',
    title: pt('onboard.2.notif.title', '常驻通知', 'Ongoing notification'),
    body: pt(
      'onboard.2.notif.body',
      '不是打扰：Android 只放行带前台服务的进程长期组网，通知就是你的实时链路状态。',
      'Not spam: Android only lets a foreground service keep the mesh alive — the notification is your live link status.',
    ),
  },
  {
    icon: 'mdi-cellphone-check',
    title: pt('onboard.2.bg.title', '后台运行', 'Run in background'),
    body: pt('onboard.2.bg.body', '切去别的 App，组网依然在线。', 'Switch to any other app — the mesh stays up.'),
  },
])

const p3Steps = computed(() => [
  { id: 'config', text: pt('onboard.3.step1', '创建或选择网络配置', 'Create or select a network config') },
  { id: 'credentials', text: pt('onboard.3.step2', '填写网络名与密码——相同凭据即同一张网', 'Enter network name and secret — same credentials, same mesh') },
  { id: 'connect', text: pt('onboard.3.step3', '点「连接」，等待节点出现', 'Tap Connect and watch peers arrive') },
])

// the hint names the control in words; the gear glyph is decorative next to it
const p3Hint = computed(() => ({
  before: pt('onboard.3.hint_before', '右上角的', 'The '),
  after: pt(
    'onboard.3.hint_after',
    '底部「设备 / 配置 / 动态」三个页签可查看节点、改配置与看历史事件。',
    ' Devices, Config and Activity tabs at the bottom show peers, settings and past events.',
  ),
}))
</script>

<template>
  <v-dialog
    :model-value="props.modelValue"
    fullscreen
    persistent
    :scrim="true"
    transition="dialog-bottom-transition"
    @update:model-value="emit('update:modelValue', $event)"
  >
    <v-card class="et-onboard" @keydown.esc.stop.prevent="finish">
      <div class="et-onboard-top">
        <v-spacer />
        <!-- the dialog is persistent, so this is the guaranteed way out on
             every page (Esc is wired to the same exit; the last page keeps its
             primary CTA as well) -->
        <v-btn
          class="et-onboard-skip"
          variant="text"
          rounded="pill"
          size="small"
          :aria-label="headings[0]"
          @click="finish"
        >
          {{ headings[0] }}
        </v-btn>
      </div>

      <div class="et-onboard-body" @touchstart.passive="onTouchStart" @touchend.passive="onTouchEnd">
        <v-window v-model="page" class="et-onboard-window">
          <!-- ============ 1 · what is easytier ============ -->
          <v-window-item :value="0">
            <div class="et-onboard-page">
              <div class="et-onboard-art" aria-hidden="true">
                <span class="et-onboard-ring r1" />
                <span class="et-onboard-ring r2" />
                <div class="et-onboard-shield">
                  <svg viewBox="0 0 24 24" width="46" height="46">
                    <path d="M12 2 4 5v6c0 5.25 3.4 9.74 8 11 4.6-1.26 8-5.75 8-11V5l-8-3Z" style="fill: var(--et-accent)" />
                    <path d="M8.6 12.2l2.3 2.3 4.5-4.6" fill="none" style="stroke: var(--et-on-accent)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                </div>
              </div>
              <h2 class="et-onboard-title">
                {{ p1.title }}
              </h2>
              <p class="et-onboard-text">
                {{ p1.body }}
              </p>
            </div>
          </v-window-item>

          <!-- ============ 2 · permissions ============ -->
          <v-window-item :value="1">
            <div class="et-onboard-page">
              <h2 class="et-onboard-title">
                {{ pt('onboard.2.title', '三个权限，换一路畅通', 'Three things we ask for') }}
              </h2>
              <div class="et-onboard-list">
                <div v-for="item in p2Items" :key="item.title" class="et-onboard-item">
                  <div class="et-squircle" style="background: var(--et-accent-quiet);">
                    <v-icon size="18" color="primary">
                      {{ item.icon }}
                    </v-icon>
                  </div>
                  <div class="min-w-0">
                    <div class="font-weight-bold et-onboard-item-title">
                      {{ item.title }}
                    </div>
                    <div class="et-onboard-item-body">
                      {{ item.body }}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </v-window-item>

          <!-- ============ 3 · three steps ============ -->
          <v-window-item :value="2">
            <div class="et-onboard-page">
              <h2 class="et-onboard-title">
                {{ pt('onboard.3.title', '三步上手', 'Up and running in 3 steps') }}
              </h2>
              <div class="et-onboard-list">
                <div v-for="(step, idx) in p3Steps" :key="step.id" class="et-onboard-step">
                  <span class="et-onboard-step-num mono" aria-hidden="true">{{ idx + 1 }}</span>
                  <span class="et-onboard-step-text">{{ step.text }}</span>
                </div>
              </div>
              <p class="et-onboard-hint">
                <span>{{ p3Hint.before }}</span>
                <v-icon
                  class="et-onboard-hint-icon"
                  size="14"
                  aria-hidden="true"
                >
                  mdi-cog-outline
                </v-icon>
                <span>{{ p3Hint.after }}</span>
              </p>
            </div>
          </v-window-item>
        </v-window>
      </div>

      <div class="et-onboard-bottom">
        <div class="et-onboard-dots" aria-hidden="true">
          <span
            v-for="(pageId, pageIdx) in PAGE_IDS"
            :key="pageId"
            class="et-onboard-dot"
            :class="{ 'is-active': page === pageIdx }"
          />
        </div>
        <div class="d-flex align-center ga-3">
          <v-btn v-if="page > 0" variant="text" rounded="pill" size="large" @click="page -= 1">
            {{ headings[3] }}
          </v-btn>
          <v-spacer />
          <v-btn
            v-if="page < PAGES - 1"
            color="primary"
            variant="flat"
            rounded="pill"
            size="large"
            append-icon="mdi-arrow-right"
            @click="page += 1"
          >
            {{ headings[1] }}
          </v-btn>
          <v-btn v-else color="primary" variant="flat" rounded="pill" size="large" prepend-icon="mdi-shield-check-outline" @click="finish">
            {{ headings[2] }}
          </v-btn>
        </div>
      </div>
    </v-card>
  </v-dialog>
</template>

<style scoped>
/* .v-card/.v-sheet paint their own background at the same specificity as a
   single class, so the compound selector is what wins — no !important. */
.et-onboard.v-card {
  background: radial-gradient(900px 420px at 50% -10%, var(--et-accent-quiet), transparent 60%), var(--et-bg);
  display: flex;
  flex-direction: column;
}

.et-onboard-top {
  display: flex;
  /* fullscreen surface: the skip button must clear the notch/island */
  padding: calc(var(--et-space-2) + var(--et-safe-top)) var(--et-space-3) 0;
  min-height: var(--et-touch);
}

/* the skip escape hatch is a real v-btn; keep it at the platform touch floor
   even at size="small" */
.et-onboard-skip.v-btn {
  min-height: var(--et-touch);
  padding-inline: var(--et-space-4);
}

.et-onboard-body {
  flex: 1;
  min-height: 0;
  display: flex;
  overflow: hidden;
}

.et-onboard-window {
  flex: 1;
  width: 100%;
}

.et-onboard-window :deep(.v-window__container),
.et-onboard-window :deep(.v-window-item) {
  height: 100%;
}

.et-onboard-page {
  height: 100%;
  min-height: 0;
  max-width: 480px;
  margin: 0 auto;
  padding: var(--et-space-4) var(--et-space-6) var(--et-space-6);
  display: flex;
  flex-direction: column;
  justify-content: center;
  /* safe: falls back to flex-start when the content overflows, so large
     system fonts / landscape stay scrollable instead of clipping the top */
  justify-content: safe center;
  gap: var(--et-gap-stack);
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  overscroll-behavior: contain;
}

@media (min-width: 720px) {
  .et-onboard-page {
    max-width: 560px;
  }
}

.et-onboard-title {
  font-size: var(--et-font-display-fluid);
  font-weight: var(--et-weight-semibold);
  letter-spacing: -0.02em;
  line-height: var(--et-leading-tight);
}

.et-onboard-text {
  font-size: var(--et-font-body);
  line-height: var(--et-leading-loose);
  color: var(--et-text-2);
}

/* page 1 art: shield in soft signal rings (flat surfaces, no neon halo) */
.et-onboard-art {
  position: relative;
  width: 168px;
  height: 168px;
  margin: 0 auto var(--et-space-4);
  display: grid;
  place-items: center;
}

.et-onboard-ring {
  position: absolute;
  border-radius: 50%;
  border: 1px solid var(--et-border);
}

.et-onboard-ring.r1 {
  inset: var(--et-space-4);
  border-color: color-mix(in srgb, var(--et-accent) 22%, transparent);
}

.et-onboard-ring.r2 {
  inset: 0;
}

.et-onboard-shield {
  width: 84px;
  height: 84px;
  border-radius: var(--et-radius-xl);
  display: grid;
  place-items: center;
  background: var(--et-surface-2);
  border: 1px solid var(--et-accent);
  position: relative;
  z-index: var(--et-z-base);
}

.et-onboard-list {
  display: flex;
  flex-direction: column;
  gap: var(--et-space-3);
  margin-top: var(--et-space-2);
}

.et-onboard-item {
  display: flex;
  align-items: flex-start;
  gap: var(--et-space-3);
  background: var(--et-surface-1);
  border: 1px solid var(--et-border);
  border-radius: var(--et-radius-md);
  padding: var(--et-pad-card);
}

.et-onboard-item-title {
  font-size: var(--et-font-body);
}

.et-onboard-item-body {
  font-size: var(--et-font-body-sm);
  line-height: var(--et-leading-normal);
  color: var(--et-text-2);
  margin-top: var(--et-space-1);
}

.et-onboard-step {
  display: flex;
  align-items: center;
  gap: var(--et-space-3);
  background: var(--et-surface-1);
  border: 1px solid var(--et-border);
  border-radius: var(--et-radius-md);
  padding: var(--et-space-3) var(--et-pad-card);
}

.et-onboard-step-num {
  width: var(--et-space-8);
  height: var(--et-space-8);
  flex-shrink: 0;
  border-radius: var(--et-radius-sm);
  display: grid;
  place-items: center;
  background: var(--et-accent-quiet);
  color: var(--et-accent);
  font-weight: var(--et-weight-semibold);
  font-size: var(--et-font-body-sm);
}

.et-onboard-step-text {
  font-size: var(--et-font-body);
  font-weight: var(--et-weight-medium);
  line-height: var(--et-leading-normal);
}

.et-onboard-hint {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: var(--et-space-1);
  font-size: var(--et-font-caption);
  line-height: var(--et-leading-normal);
  color: var(--et-text-3);
  margin-top: var(--et-space-2);
}

.et-onboard-hint-icon {
  color: var(--et-text-2);
  flex: 0 0 auto;
}

.et-onboard-bottom {
  /* fullscreen surface, bottom bar: keep the primary CTA above the gesture bar */
  padding: var(--et-space-3) var(--et-space-5) calc(var(--et-space-5) + var(--et-safe-bottom));
  max-width: 560px;
  width: 100%;
  margin: 0 auto;
}

.et-onboard-dots {
  display: flex;
  justify-content: center;
  gap: var(--et-space-2);
  margin-bottom: var(--et-space-3);
}

.et-onboard-dot {
  width: var(--et-space-2);
  height: var(--et-space-2);
  border-radius: var(--et-radius-pill);
  background: var(--et-surface-3);
  transition:
    width var(--et-dur-base) var(--et-ease-standard),
    background-color var(--et-dur-base) var(--et-ease-standard);
}

.et-onboard-dot.is-active {
  width: var(--et-space-5);
  background: var(--et-accent);
}
</style>
