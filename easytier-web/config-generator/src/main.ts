import { createApp } from 'vue'
import EasytierFrontendLib from 'easytier-frontend-lib'
import 'easytier-frontend-lib/style.css'
import App from './App.vue'

createApp(App)
  .use(EasytierFrontendLib) // installs i18n + vuetify + shared components
  .mount('#app')
