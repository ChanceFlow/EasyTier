<script setup lang="ts">
import { usePhoneText } from '~/composables/hero_text'

const props = defineProps<{ modelValue: boolean }>()
const emit = defineEmits<{
  (e: 'update:modelValue', v: boolean): void
}>()

const { pt } = usePhoneText()
const page = ref(0)
const PAGES = 3

const SWIPE_MIN_DX = 48
let swipeStartX = 0

function onTouchStart(e: TouchEvent) {
  swipeStartX = e.touches[0]?.clientX ?? 0
}

function onTouchEnd(e: TouchEvent) {
  const dx = (e.changedTouches[0]?.clientX ?? 0) - swipeStartX
  if (Math.abs(dx) < SWIPE_MIN_DX)
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
  pt('onboard.3.step1', '创建或选择网络配置', 'Create or select a network config'),
  pt('onboard.3.step2', '填写网络名与密码——相同凭据即同一张网', 'Enter network name and secret — same credentials, same mesh'),
  pt('onboard.3.step3', '点「连接」，等待节点出现', 'Tap Connect and watch peers arrive'),
])
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
    <v-card class="et-onboard">
      <div class="et-onboard-top">
        <v-spacer />
        <v-btn v-if="page < PAGES - 1" variant="text" rounded="pill" size="small" @click="finish">
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
                    <path d="M8.6 12.2l2.3 2.3 4.5-4.6" fill="none" style="stroke: #06231c" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
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
                  <div class="et-squircle" style="background: var(--et-accent-dim);">
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
                <div v-for="(step, i) in p3Steps" :key="i" class="et-onboard-step">
                  <span class="et-onboard-step-num mono">{{ i + 1 }}</span>
                  <span class="et-onboard-step-text">{{ step }}</span>
                </div>
              </div>
              <p class="et-onboard-hint">
                {{ pt('onboard.3.hint', '右上角 ⚙ 可切换语言与主题；组网配置在「高级控制台」里。', 'Switch language and theme via ⚙ at the top right; detailed config lives in the Advanced console.') }}
              </p>
            </div>
          </v-window-item>
        </v-window>
      </div>

      <div class="et-onboard-bottom safe-bottom">
        <div class="et-onboard-dots" aria-hidden="true">
          <span v-for="i in PAGES" :key="i" class="et-onboard-dot" :class="{ 'is-active': page === i - 1 }" />
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
.et-onboard {
  background: radial-gradient(900px 420px at 50% -10%, var(--et-accent-dim), transparent 60%), var(--et-bg) !important;
  display: flex;
  flex-direction: column;
}

.et-onboard-top {
  display: flex;
  padding: 8px 12px 0;
  min-height: 48px;
}

.et-onboard-body {
  flex: 1;
  min-height: 0;
  display: flex;
}

.et-onboard-window {
  flex: 1;
  width: 100%;
}

.et-onboard-page {
  height: 100%;
  max-width: 480px;
  margin: 0 auto;
  padding: 12px 28px 24px;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 10px;
}

@media (min-width: 720px) {
  .et-onboard-page {
    max-width: 560px;
  }
}

.et-onboard-title {
  font-size: 1.45rem;
  font-weight: 800;
  letter-spacing: -0.03em;
  line-height: 1.25;
}

.et-onboard-text {
  font-size: 0.95rem;
  line-height: 1.65;
  color: var(--et-text-secondary);
}

/* page 1 art: shield in soft signal-cyan rings */
.et-onboard-art {
  position: relative;
  width: 168px;
  height: 168px;
  margin: 0 auto 18px;
  display: grid;
  place-items: center;
}

.et-onboard-ring {
  position: absolute;
  border-radius: 50%;
  border: 1px solid var(--et-border);
}

.et-onboard-ring.r1 {
  inset: 18px;
  border-color: color-mix(in srgb, var(--et-accent) 22%, transparent);
}

.et-onboard-ring.r2 {
  inset: 0;
}

.et-onboard-shield {
  width: 84px;
  height: 84px;
  border-radius: 26px;
  display: grid;
  place-items: center;
  background: var(--et-surface-2);
  border: 1px solid var(--et-accent);
  box-shadow: 0 0 42px -10px var(--et-glow);
  position: relative;
  z-index: 1;
}

.et-onboard-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-top: 6px;
}

.et-onboard-item {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  background: var(--et-surface);
  border: 1px solid var(--et-border);
  border-radius: var(--et-radius);
  padding: 14px;
}

.et-onboard-item-title {
  font-size: 0.92rem;
}

.et-onboard-item-body {
  font-size: 0.8rem;
  line-height: 1.5;
  color: var(--et-text-secondary);
  margin-top: 2px;
}

.et-onboard-step {
  display: flex;
  align-items: center;
  gap: 14px;
  background: var(--et-surface);
  border: 1px solid var(--et-border);
  border-radius: var(--et-radius);
  padding: 14px 16px;
}

.et-onboard-step-num {
  width: 30px;
  height: 30px;
  flex-shrink: 0;
  border-radius: 10px;
  display: grid;
  place-items: center;
  background: var(--et-accent-dim);
  color: var(--et-accent);
  font-weight: 800;
  font-size: 0.95rem;
}

.et-onboard-step-text {
  font-size: 0.9rem;
  font-weight: 500;
  line-height: 1.45;
}

.et-onboard-hint {
  font-size: 0.78rem;
  color: var(--et-text-tertiary);
  margin-top: 8px;
}

.et-onboard-bottom {
  padding: 10px 20px 18px;
  max-width: 560px;
  width: 100%;
  margin: 0 auto;
}

.et-onboard-dots {
  display: flex;
  justify-content: center;
  gap: 6px;
  margin-bottom: 12px;
}

.et-onboard-dot {
  width: 6px;
  height: 6px;
  border-radius: 999px;
  background: var(--et-surface-3);
  transition:
    width 0.25s ease,
    background-color 0.25s ease;
}

.et-onboard-dot.is-active {
  width: 18px;
  background: var(--et-accent);
}
</style>
