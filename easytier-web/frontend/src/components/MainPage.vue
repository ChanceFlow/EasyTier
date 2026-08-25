<script setup lang="ts">
import { I18nUtils } from 'easytier-frontend-lib'
import { computed, onMounted, ref, onUnmounted, nextTick } from 'vue';
import { useDisplay } from 'vuetify';
import { useRoute, useRouter } from 'vue-router';
import ChangePassword from './ChangePassword.vue';
import Icon from '../assets/easytier.png'
import { useI18n } from 'vue-i18n'
import ApiClient from '../modules/api';

const { t } = useI18n()
const route = useRoute();
const router = useRouter();
const { smAndUp } = useDisplay()

const api = computed<ApiClient | undefined>(() => {
    try {
        return new ApiClient(atob(route.params.apiHost as string), () => {
            router.push({ name: 'login' });
        })
    } catch (e) {
        router.push({ name: 'login' });
    }
});

// ChangePassword is hosted in a v-dialog below (previously opened through
// PrimeVue's useDialog / DialogService).
const showChangePassword = ref(false);

const userMenuItems = ref([
    {
        label: t('web.main.change_password'),
        icon: 'mdi-key',
        command: () => {
            console.log('File');
            showChangePassword.value = true;
        },
    },
    {
        label: t('web.main.logout'),
        icon: 'mdi-logout',
        command: async () => {
            try {
                await api.value?.logout();
            } catch (e) {
                console.error("logout failed", e);
            }
            router.push({ name: 'login' });
        },
    },
])

const forceShowSideBar = ref(false)
const sidebarContentRef = ref<HTMLElement>()
const toggleButtonRef = ref()

// The navigation drawer is always shown on >= sm displays; on smaller
// screens it only shows while forceShowSideBar is true.
const drawerVisible = computed(() => smAndUp.value || forceShowSideBar.value)

const onDrawerUpdate = (value: boolean) => {
    if (value) {
        forceShowSideBar.value = true;
    } else {
        closeSidebar();
    }
}

const toggleButtonEl = computed<HTMLElement | undefined>(() => (toggleButtonRef.value as any)?.$el)

// 处理点击外部区域关闭侧边栏
const handleClickOutside = (event: Event) => {
    const target = event.target as HTMLElement;

    // 如果侧边栏是隐藏的，不需要处理
    if (!forceShowSideBar.value) return;

    // 检查点击是否在侧边栏内部或切换按钮上
    const isClickInsideSidebar = sidebarContentRef.value?.contains(target);
    const isClickOnToggleButton = toggleButtonEl.value?.contains(target);

    // 如果点击在侧边栏外部且不在切换按钮上，则关闭侧边栏
    if (!isClickInsideSidebar && !isClickOnToggleButton) {
        forceShowSideBar.value = false;
    }
};

// 切换侧边栏显示状态
const toggleSidebar = () => {
    forceShowSideBar.value = !forceShowSideBar.value;
};

// 点击背景遮罩关闭侧边栏
const closeSidebar = () => {
    forceShowSideBar.value = false;
};

onMounted(async () => {
    // 等待 DOM 渲染完成后添加事件监听器
    await nextTick();
    document.addEventListener('click', handleClickOutside);
});

onUnmounted(() => {
    document.removeEventListener('click', handleClickOutside);
});

</script>

<template>
    <!-- 顶部导航栏 (Frosted glass) -->
    <v-app-bar color="surface" flat border="b" class="main-app-bar">
        <v-app-bar-nav-icon v-if="!smAndUp" ref="toggleButtonRef" icon="mdi-menu" aria-haspopup="true"
            @click="toggleSidebar" />
        <a href="https://easytier.top" class="d-flex align-center ga-2 ms-2 text-decoration-none">
            <v-img :src="Icon" width="32" height="32" cover class="rounded-lg" />
            <span class="text-h6 font-weight-bold">EasyTier</span>
        </a>
        <v-spacer />
        <v-btn icon="mdi-translate" variant="text" size="small" @click="I18nUtils.toggleLanguage" />
        <v-menu>
            <template #activator="{ props: menuProps }">
                <v-btn v-bind="menuProps" class="ms-1" icon="mdi-account" variant="text" size="small" aria-haspopup="true" />
            </template>
            <v-list density="comfortable" min-width="200" rounded="xl">
                <v-list-item v-for="(item, index) in userMenuItems" :key="index" :prepend-icon="item.icon"
                    :title="item.label" @click="item.command" />
            </v-list>
        </v-menu>
    </v-app-bar>

    <!-- 侧边栏：桌面端常驻，移动端临时抽屉 -->
    <v-navigation-drawer :model-value="drawerVisible" :width="256" :mobile-breakpoint="600"
        @update:model-value="onDrawerUpdate">
        <div ref="sidebarContentRef" class="h-100 pa-3">
            <v-list nav density="comfortable">
                <v-list-item prepend-icon="mdi-chart-pie" :title="t('web.main.dashboard')" rounded="xl"
                    @click="router.push({ name: 'dashboard' })" />
                <v-list-item prepend-icon="mdi-server" :title="t('web.main.device_list')" rounded="xl"
                    @click="router.push({ name: 'deviceList' })" />
                <v-list-item prepend-icon="mdi-login" :title="t('web.main.login_page')" rounded="xl"
                    @click="router.push({ name: 'login' })" />
            </v-list>
        </div>
    </v-navigation-drawer>

    <v-main>
        <v-container fluid class="pa-4">
            <v-sheet class="pa-4 rounded-xl" border>
                <RouterView v-slot="{ Component }">
                    <component :is="Component" :api="api" />
                </RouterView>
            </v-sheet>
        </v-container>
    </v-main>

    <!-- 修改密码对话框 -->
    <v-dialog v-model="showChangePassword" max-width="480">
        <ChangePassword :api="api" @close="showChangePassword = false" />
    </v-dialog>
</template>

<style scoped>
.main-app-bar {
    backdrop-filter: blur(20px);
    background: rgba(var(--v-theme-surface), 0.85) !important;
}
</style>
