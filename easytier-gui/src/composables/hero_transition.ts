import { ref } from 'vue'

export type HeroDesiredState = 'idle' | 'connecting' | 'disconnecting'

export interface HeroTransitionOptions {
  timeoutMs?: number
  onTimeout?: (state: 'connecting' | 'disconnecting') => void
}

export function createHeroTransition(options: HeroTransitionOptions = {}) {
  const timeoutMs = options.timeoutMs ?? 15000
  const desired = ref<HeroDesiredState>('idle')
  let timer: ReturnType<typeof setTimeout> | null = null

  function clearTimer() {
    if (timer) {
      clearTimeout(timer)
      timer = null
    }
  }

  function startConnecting() {
    clearTimer()
    desired.value = 'connecting'
    timer = setTimeout(() => {
      if (desired.value === 'connecting') {
        desired.value = 'idle'
        timer = null
        options.onTimeout?.('connecting')
      }
    }, timeoutMs)
  }

  function startDisconnecting() {
    clearTimer()
    desired.value = 'disconnecting'
    timer = setTimeout(() => {
      if (desired.value === 'disconnecting') {
        desired.value = 'idle'
        timer = null
        options.onTimeout?.('disconnecting')
      }
    }, timeoutMs)
  }

  function handleConnectedChange(connected: boolean): 'connected' | 'disconnected' | null {
    if (desired.value === 'connecting' && connected) {
      clearTimer()
      desired.value = 'idle'
      return 'connected'
    }
    if (desired.value === 'disconnecting' && !connected) {
      clearTimer()
      desired.value = 'idle'
      return 'disconnected'
    }
    return null
  }

  function reset() {
    clearTimer()
    desired.value = 'idle'
  }

  return {
    desired,
    startConnecting,
    startDisconnecting,
    handleConnectedChange,
    reset,
  }
}
