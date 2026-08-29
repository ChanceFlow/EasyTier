import { createApp } from 'vue'
import 'easytier-frontend-lib/style.css'
import './style.css'
import App from './App.vue'
import EasytierFrontendLib from 'easytier-frontend-lib'
import { I18nUtils } from 'easytier-frontend-lib'
// Vuetify components/directives are registered globally on the app; the
// shared Vuetify instance itself (Material 3 theme, defaults, display) is
// installed by the EasytierFrontendLib plugin.
import * as vuetifyComponents from 'vuetify/components'
import * as vuetifyDirectives from 'vuetify/directives'

import { createRouter, createWebHashHistory } from 'vue-router'
import MainPage from './components/MainPage.vue'
import Login from './components/Login.vue'
import DeviceList from './components/DeviceList.vue'
import DeviceManagement from './components/DeviceManagement.vue'
import Dashboard from './components/Dashboard.vue'

const routes = [
    {
        path: '/auth', children: [
            {
                name: 'login',
                path: '',
                component: Login,
                alias: 'login',
                props: { isRegistering: false }
            },
            {
                name: 'register',
                path: 'register',
                component: Login,
                props: { isRegistering: true }
            }
        ]
    },
    {
        path: '/h/:apiHost', component: MainPage, children: [
            {
                path: '',
                alias: 'dashboard',
                name: 'dashboard',
                component: Dashboard,
            },
            {
                path: 'deviceList',
                name: 'deviceList',
                component: DeviceList,
                children: [
                    {
                        path: 'device/:deviceId/:instanceId?',
                        name: 'deviceManagement',
                        component: DeviceManagement,
                    }
                ]
            },
        ]
    },
    {
        path: '/:pathMatch(.*)*', name: 'notFound', redirect: () => {
            let apiHost = localStorage.getItem('apiHost');
            if (apiHost) {
                return { name: 'dashboard', params: { apiHost: apiHost } }
            } else {
                return { name: 'login' }
            }
        }
    }
]

const router = createRouter({
    history: createWebHashHistory(),
    routes,
})

const app = createApp(App)

// Use i18n
app.use(I18nUtils.i18n)

// Register all Vuetify components/directives globally (used both by this app
// and by components from easytier-frontend-lib, which resolve them at
// runtime). EasytierFrontendLib installs Vuetify itself, so this only adds
// the global component registrations on the same app.
for (const key in vuetifyComponents) {
    app.component(key, (vuetifyComponents as Record<string, any>)[key])
}
for (const key in vuetifyDirectives) {
    app.directive(key, (vuetifyDirectives as Record<string, any>)[key])
}

// EasytierFrontendLib installs Vuetify (Material 3 theme) and registers the
// shared components (Config, Status, RemoteManagement, ...).
app.use(router).use(EasytierFrontendLib).mount('#app')
