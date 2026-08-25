import autoprefixer from 'autoprefixer'

// The GUI's own CSS is hand-written and gets autoprefixed here.
// CSS served from node_modules — most notably the shared lib's pre-built
// style.css (~7.4MB of Vuetify CSS, already prefixed by the lib's own build) —
// must NOT be re-processed: running autoprefixer (or tailwind) on it takes
// minutes of CPU and freezes the dev server. Tailwind is no longer used by
// this app (Vuetify provides the utility classes), so it is not loaded at all.
const ap = autoprefixer()

export default {
  plugins: [
    {
      postcssPlugin: 'autoprefixer-skip-node-modules',
      prepare(result) {
        const from = result.opts?.from ?? ''
        if (from.includes('/node_modules/')) {
          return {}
        }
        return ap.prepare(result)
      },
    },
  ],
}
