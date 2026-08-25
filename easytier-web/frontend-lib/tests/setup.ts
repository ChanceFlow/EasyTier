import { vi } from 'vitest'
import '../src/style.css'

class ResizeObserverStub {
  observe() {}
  unobserve() {}
  disconnect() {}
}

vi.stubGlobal('ResizeObserver', ResizeObserverStub)

if (typeof globalThis.visualViewport === 'undefined') {
  vi.stubGlobal('visualViewport', {
    width: 0,
    height: 0,
    offsetLeft: 0,
    offsetTop: 0,
    pageLeft: 0,
    pageTop: 0,
    scale: 1,
    onresize: null,
    onscroll: null,
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() { return true },
  })
}

// happy-dom lacks IntersectionObserver which Vuetify menus may use
if (typeof globalThis.IntersectionObserver === 'undefined') {
  class IntersectionObserverStub {
    observe() {}
    unobserve() {}
    disconnect() {}
    takeRecords() { return [] }
  }
  vi.stubGlobal('IntersectionObserver', IntersectionObserverStub)
}
