import EasyTierFrontendLib, { I18nUtils } from 'easytier-frontend-lib';
// Note: import from 'vue-router' (not 'vue-router/auto') — the /auto specifier
// resolves to an empty type stub in vue-router's exports map, which breaks
// vue-tsc. At runtime both specifiers resolve to the same module.
import { createRouter, createWebHistory } from 'vue-router';
import { routes } from 'vue-router/auto-routes';
import App from '~/App.vue';

import 'easytier-frontend-lib/style.css';
import '~/styles.css';

// Dev-only browser preview: install a mock Tauri runtime so the GUI boots in a
// plain browser (used with `vite` without the Tauri webview).
if (import.meta.env.DEV && !window.__TAURI_INTERNALS__) {
  const { installTauriMock } = await import('~/tauri-mock')
  installTauriMock()
}


if (import.meta.env.PROD) {
  document.addEventListener('keydown', (event) => {
    if (
      event.key === 'F5'
      || (event.ctrlKey && event.key === 'r')
      || (event.metaKey && event.key === 'r')
    ) {
      event.preventDefault()
    }
  })

  document.addEventListener('contextmenu', (event) => {
    event.preventDefault()
  })
}

async function main() {
  await I18nUtils.loadLanguageAsync(localStorage.getItem('lang') || 'en')

  const app = createApp(App)

  const router = createRouter({
    history: createWebHistory(),
    routes,
  })

  app.use(router)
  app.use(createPinia())
  app.use(EasyTierFrontendLib) // installs i18n + vuetify + shared components
  app.mount('#app')
}

main()
