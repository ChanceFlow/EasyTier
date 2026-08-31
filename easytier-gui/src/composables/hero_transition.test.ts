import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createHeroTransition } from './hero_transition'

describe('hero_transition state machine', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('transitions to connecting and completes on connected=true', () => {
    const transition = createHeroTransition({ timeoutMs: 15000 })
    expect(transition.desired.value).toBe('idle')

    transition.startConnecting()
    expect(transition.desired.value).toBe('connecting')

    const result = transition.handleConnectedChange(true)
    expect(result).toBe('connected')
    expect(transition.desired.value).toBe('idle')
  })

  it('ignores connected=false while in connecting state', () => {
    const transition = createHeroTransition({ timeoutMs: 15000 })
    transition.startConnecting()

    const result = transition.handleConnectedChange(false)
    expect(result).toBeNull()
    expect(transition.desired.value).toBe('connecting')
  })

  it('transitions to disconnecting and completes on connected=false', () => {
    const transition = createHeroTransition({ timeoutMs: 15000 })
    transition.startDisconnecting()
    expect(transition.desired.value).toBe('disconnecting')

    const result = transition.handleConnectedChange(false)
    expect(result).toBe('disconnected')
    expect(transition.desired.value).toBe('idle')
  })

  it('triggers onTimeout callback after timeout period when connecting', () => {
    const onTimeout = vi.fn()
    const transition = createHeroTransition({ timeoutMs: 15000, onTimeout })

    transition.startConnecting()
    expect(transition.desired.value).toBe('connecting')

    vi.advanceTimersByTime(14999)
    expect(transition.desired.value).toBe('connecting')
    expect(onTimeout).not.toHaveBeenCalled()

    vi.advanceTimersByTime(1)
    expect(transition.desired.value).toBe('idle')
    expect(onTimeout).toHaveBeenCalledWith('connecting')
  })

  it('triggers onTimeout callback after timeout period when disconnecting', () => {
    const onTimeout = vi.fn()
    const transition = createHeroTransition({ timeoutMs: 15000, onTimeout })

    transition.startDisconnecting()
    expect(transition.desired.value).toBe('disconnecting')

    vi.advanceTimersByTime(15000)
    expect(transition.desired.value).toBe('idle')
    expect(onTimeout).toHaveBeenCalledWith('disconnecting')
  })

  it('cancels timer and resets to idle when reset is called', () => {
    const onTimeout = vi.fn()
    const transition = createHeroTransition({ timeoutMs: 15000, onTimeout })

    transition.startConnecting()
    expect(transition.desired.value).toBe('connecting')

    transition.reset()
    expect(transition.desired.value).toBe('idle')

    vi.advanceTimersByTime(20000)
    expect(onTimeout).not.toHaveBeenCalled()
  })
})
