<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { I18nUtils } from 'easytier-frontend-lib';
import { getInitialApiHost, cleanAndLoadApiHosts, saveApiHost } from "../modules/api-host"
import { useI18n } from 'vue-i18n'
import ApiClient, { Credential, RegisterData } from '../modules/api';

const { t } = useI18n()

const props = defineProps<{
    isRegistering: boolean;
}>();

const api = computed<ApiClient>(() => new ApiClient(apiHost.value));
const router = useRouter();

// 通知状态（替代 PrimeVue Toast）
const errorMessage = ref('');
const snackbar = ref(false);
const snackbarMessage = ref('');

const username = ref('');
const password = ref('');
const registerUsername = ref('');
const registerPassword = ref('');
const captcha = ref('');
const captchaSrc = computed(() => api.value.captcha_url());

// 密码可见性切换（替代 PrimeVue Password 的 toggleMask）
const showLoginPassword = ref(false);
const showRegisterPassword = ref(false);

const onSubmit = async () => {
    // Add your login logic here
    saveApiHost(apiHost.value);
    const credential: Credential = { username: username.value, password: password.value, };
    let ret = await api.value?.login(credential);
    if (ret.success) {
        localStorage.setItem('apiHost', btoa(apiHost.value));
        router.push({
            name: 'dashboard',
            params: { apiHost: btoa(apiHost.value) },
        });
    } else {
        errorMessage.value = `Login Failed: ${ret.message}`;
    }
};

const onRegister = async () => {
    saveApiHost(apiHost.value);
    const credential: Credential = { username: registerUsername.value, password: registerPassword.value };
    const registerReq: RegisterData = { credentials: credential, captcha: captcha.value };
    let ret = await api.value?.register(registerReq);
    if (ret.success) {
        errorMessage.value = '';
        snackbarMessage.value = `Register Success: ${ret.message}`;
        snackbar.value = true;
        router.push({ name: 'login' });
    } else {
        errorMessage.value = `Register Failed: ${ret.message}`;
    }
};

const apiHost = ref<string>(getInitialApiHost())
// 预加载已保存的 API 地址，使下拉菜单可直接打开（对应原 AutoComplete 的 dropdown 按钮行为）
const apiHostSuggestions = ref<Array<string>>(cleanAndLoadApiHosts().map((host) => host.value))
const apiHostSearch = (query: string) => {
    apiHostSuggestions.value = [];
    let hosts = cleanAndLoadApiHosts();
    if (query) {
        apiHostSuggestions.value.push(query);
    }
    hosts.forEach((host) => {
        apiHostSuggestions.value.push(host.value);
    });
}

// 打开下拉时重新加载已保存的 API 地址
const onApiHostMenu = (open: boolean) => {
    if (open) {
        apiHostSearch('');
    }
}

const oidcEnabled = ref(false);
const lastCheckedHost = ref('');
const oidcCheckTimer = ref<ReturnType<typeof setTimeout> | null>(null);
const checkOidcConfig = () => {
    if (oidcCheckTimer.value) clearTimeout(oidcCheckTimer.value);
    oidcCheckTimer.value = setTimeout(async () => {
        const host = apiHost.value;
        if (host === lastCheckedHost.value) return;

        const enabled = (await new ApiClient(host).getOidcConfig()).enabled;
        // If host changes while request is in-flight, do not overwrite UI state.
        if (apiHost.value !== host) return;

        lastCheckedHost.value = host;
        oidcEnabled.value = enabled;
    }, 300);
};

watch(apiHost, () => {
    checkOidcConfig();
});

// 切换登录/注册表单时清除过期的错误信息
watch(() => props.isRegistering, () => {
    errorMessage.value = '';
});

const onSsoLogin = () => {
    saveApiHost(apiHost.value);
    localStorage.setItem('apiHost', btoa(apiHost.value));
    window.location.href = api.value.oidcLoginUrl();
};

onMounted(() => {
    checkOidcConfig();
});

onBeforeUnmount(() => {
    if (oidcCheckTimer.value) {
        clearTimeout(oidcCheckTimer.value);
        oidcCheckTimer.value = null;
    }
});

</script>

<template>
    <v-main>
        <v-container fluid class="d-flex align-center justify-center pa-4" style="min-height: 100dvh;">
            <v-card class="w-100 position-relative px-6 py-8 login-card" max-width="420" rounded="xl" elevation="6">
                <v-btn icon="mdi-translate" variant="text" size="small" class="position-absolute"
                    style="top: 16px; right: 16px; z-index: 10;" :aria-label="t('web.main.language')"
                    @click="I18nUtils.toggleLanguage" />

                <div class="text-center mb-6">
                    <v-avatar color="primary" size="56" class="mb-3 rounded-2xl elevation-2">
                        <v-icon size="32" color="white">mdi-shield-outline</v-icon>
                    </v-avatar>
                    <h2 class="text-h5 font-weight-bold">
                        EasyTier
                    </h2>
                    <p class="text-caption text-medium-emphasis">
                        {{ isRegistering ? t('web.login.register') : t('web.login.login') }}
                    </p>
                </div>

                <v-alert v-if="errorMessage" type="error" variant="tonal" density="compact" class="mb-4 rounded-lg"
                    closable @click:close="errorMessage = ''">
                    {{ errorMessage }}
                </v-alert>

                <div class="mb-4">
                    <v-combobox id="api-host" v-model="apiHost" :items="apiHostSuggestions" no-filter
                        :label="t('web.login.api_host')" @update:search="apiHostSearch"
                        @update:menu="onApiHostMenu" />
                </div>

                <form v-if="!isRegistering" @submit.prevent="onSubmit" class="d-flex flex-column ga-3">
                    <v-text-field id="username" v-model="username" :label="t('web.login.username')" required />
                    <v-text-field id="password" v-model="password" :label="t('web.login.password')" required
                        :type="showLoginPassword ? 'text' : 'password'"
                        :append-inner-icon="showLoginPassword ? 'mdi-eye-off' : 'mdi-eye'"
                        @click:append-inner="showLoginPassword = !showLoginPassword" />
                    <v-btn type="submit" block color="primary" size="large" rounded="pill" class="font-weight-bold">
                        {{ t('web.login.login') }}
                    </v-btn>
                    <v-btn type="button" block variant="tonal" color="secondary" rounded="pill"
                        @click="saveApiHost(apiHost); $router.replace({ name: 'register' })">
                        {{ t('web.login.register') }}
                    </v-btn>
                    <v-btn v-if="oidcEnabled" type="button" block variant="tonal" color="info" rounded="pill" @click="onSsoLogin">
                        {{ t('web.login.sso_login') }}
                    </v-btn>
                </form>

                <form v-else @submit.prevent="onRegister" class="d-flex flex-column ga-3">
                    <v-text-field id="register-username" v-model="registerUsername" :label="t('web.login.username')"
                        required />
                    <v-text-field id="register-password" v-model="registerPassword"
                        :label="t('web.login.password')" required
                        :type="showRegisterPassword ? 'text' : 'password'"
                        :append-inner-icon="showRegisterPassword ? 'mdi-eye-off' : 'mdi-eye'"
                        @click:append-inner="showRegisterPassword = !showRegisterPassword" />
                    <v-text-field id="captcha" v-model="captcha" :label="t('web.login.captcha')" required />
                    <img :src="captchaSrc" alt="Captcha" class="my-2 rounded-lg" style="height: 48px; object-fit: contain;" />
                    <v-btn type="submit" block color="primary" size="large" rounded="pill" class="font-weight-bold">
                        {{ t('web.login.register') }}
                    </v-btn>
                    <v-btn type="button" block variant="tonal" color="secondary" rounded="pill"
                        @click="saveApiHost(apiHost); $router.replace({ name: 'login' })">
                        {{ t('web.login.back_to_login') }}
                    </v-btn>
                </form>
            </v-card>
        </v-container>
    </v-main>

    <v-snackbar v-model="snackbar" color="success" :timeout="2000" location="bottom" rounded="pill">
        {{ snackbarMessage }}
    </v-snackbar>
</template>

<style scoped>
.login-card {
    background: var(--v-theme-surfaceContainerLow);
    border: 1px solid rgba(var(--v-theme-outlineVariant), 0.35);
}
</style>
