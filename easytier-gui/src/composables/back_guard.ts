/**
 * Android back-button bridge for overlays.
 *
 * The native shell (MainActivity) asks this page to `goBack()` whenever the
 * WebView still has history, and only sends the task to the background when it
 * has none (so the VPN keeps running, upstream #2546). Vuetify renders every
 * dialog / bottom sheet / menu through `v-overlay`, whose active state is the
 * `.v-overlay--active` class (verified in vuetify 3.13.2,
 * `lib/components/VOverlay/VOverlay.js`: `'v-overlay--active': isActive.value`).
 *
 * To make that first back press close an overlay instead of backgrounding the
 * app, this guard keeps the WebView history depth in sync with the number of
 * active overlays: one pushed history entry per open overlay. A hardware back
 * then becomes a real `popstate`, which we translate into the Escape keydown
 * Vuetify already listens for on `window` (it closes its globally topmost
 * overlay). Closing an overlay via the scrim / Escape / a close button does not
 * touch history, so we issue one `history.back()` per closed overlay to keep
 * the stack balanced.
 *
 * Degrades to a no-op when the DOM / history / MutationObserver APIs are absent
 * (SSR, happy-dom, test runners).
 */

/** Class Vuetify 3.13.2 toggles on the root element of every active overlay. */
const OVERLAY_ACTIVE_CLASS = 'v-overlay--active'

/** Marker stored in the history entries this guard pushes. */
const GUARD_STATE_KEY = '__etOverlayGuard'

let installed = false

export function installBackGuard(): void {
  if (installed) {
    return
  }
  if (typeof window === 'undefined' || typeof document === 'undefined') {
    return
  }
  if (typeof MutationObserver === 'undefined') {
    return
  }

  const history = window.history
  if (
    !history
    || typeof history.pushState !== 'function'
    || typeof history.back !== 'function'
  ) {
    return
  }

  const target: HTMLElement | null = document.body ?? document.documentElement
  if (!target) {
    return
  }

  installed = true

  /** Number of overlays last observed as active. */
  let overlayCount = 0
  /** Guard history entries we believe are still ahead of the base entry. */
  let pushedEntries = 0
  /** A `history.back()` we started whose `popstate` has not arrived yet. */
  let syntheticBackInFlight = false
  /** Further `history.back()` trips queued behind the in-flight one. */
  let syntheticBacksQueued = 0
  /** Overlay decrements already paid for by a real (hardware/browser) popstate. */
  let popstateHandled = 0
  let popstateResetScheduled = false

  const countActiveOverlays = (): number => {
    try {
      return document.querySelectorAll(`.${OVERLAY_ACTIVE_CLASS}`).length
    }
    catch {
      return 0
    }
  }

  /**
   * Vuetify registers its Escape handler on `window`; a keydown dispatched on
   * `document` bubbles up to it and closes the globally topmost overlay.
   */
  const closeTopOverlay = (): void => {
    try {
      document.dispatchEvent(new KeyboardEvent('keydown', {
        key: 'Escape',
        code: 'Escape',
        bubbles: true,
        cancelable: true,
      }))
    }
    catch {
      // KeyboardEvent constructor unavailable: leave the overlay alone.
    }
  }

  const drainSyntheticBacks = (): void => {
    if (syntheticBackInFlight || syntheticBacksQueued <= 0) {
      return
    }
    syntheticBacksQueued -= 1
    syntheticBackInFlight = true
    try {
      history.back()
    }
    catch {
      syntheticBackInFlight = false
    }
  }

  // A popstate-triggered close is applied to the DOM in a Vue microtask. Drop a
  // stale allowance on the next macrotask so it can never absorb an unrelated
  // later close.
  const schedulePopstateReset = (): void => {
    if (popstateResetScheduled) {
      return
    }
    popstateResetScheduled = true
    window.setTimeout(() => {
      popstateResetScheduled = false
      popstateHandled = 0
    }, 0)
  }

  const syncOverlayCount = (): void => {
    const next = countActiveOverlays()

    if (next > overlayCount) {
      // Never drop the values vue-router (or anything else) already stored in
      // `history.state`: spreading keeps its `position`/`current` bookkeeping
      // intact so our push does not look like a route change.
      const opened = next - overlayCount
      for (let i = 0; i < opened; i += 1) {
        pushedEntries += 1
        try {
          const previous = history.state
          const baseState = previous && typeof previous === 'object' ? previous : {}
          history.pushState({ ...baseState, [GUARD_STATE_KEY]: pushedEntries }, '')
        }
        catch {
          pushedEntries -= 1
        }
      }
    }
    else if (next < overlayCount) {
      let closed = overlayCount - next

      // Closes caused by the Escape we sent from a popstate were already paid
      // for: the browser consumed that guard entry during goBack().
      const alreadyPaid = Math.min(closed, popstateHandled)
      popstateHandled -= alreadyPaid
      closed -= alreadyPaid

      // UI closes (scrim / Escape key / close button) never touch history, so
      // rewind one entry per overlay to keep the stack balanced.
      const toRewind = Math.min(closed, pushedEntries)
      if (toRewind > 0) {
        pushedEntries -= toRewind
        syntheticBacksQueued += toRewind
        drainSyntheticBacks()
      }
    }

    overlayCount = next
  }

  const onPopState = (): void => {
    if (syntheticBackInFlight) {
      // This traversal is the balance-back we started ourselves: consume it and
      // never treat it as a user back (which would close another overlay).
      syntheticBackInFlight = false
      drainSyntheticBacks()
      return
    }

    if (overlayCount > 0) {
      // Real hardware/gesture/browser back: the traversal already consumed one
      // guard entry, so close the top overlay and remember that the upcoming
      // DOM decrement must not rewind history a second time.
      pushedEntries = Math.max(0, pushedEntries - 1)
      popstateHandled += 1
      schedulePopstateReset()
      closeTopOverlay()
    }
  }

  const observer = new MutationObserver(() => {
    syncOverlayCount()
  })
  observer.observe(target, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['class'],
  })

  window.addEventListener('popstate', onPopState)

  // Adopt an overlay that is somehow already open when we install.
  syncOverlayCount()
}
