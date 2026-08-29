<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { Utils } from 'easytier-frontend-lib';
import DeviceDetails from './DeviceDetails.vue';
import { useI18n } from 'vue-i18n'
import ApiClient from '../modules/api';

const { t } = useI18n()

declare const window: Window & typeof globalThis;

const props = defineProps({
    api: ApiClient,
});

const detailDialog = ref(false);
const selectedDevice = ref<Utils.DeviceInfo | null>(null);
// 从 localStorage 读取显示详情状态，默认为 false
const showDetailedView = ref(localStorage.getItem('deviceList.showDetailedView') === 'true');

// 监听显示详情状态变化，保存到 localStorage
watch(showDetailedView, (newValue) => {
    localStorage.setItem('deviceList.showDetailedView', newValue.toString());
});

const api = props.api;

const deviceList = ref<Array<Utils.DeviceInfo> | undefined>(undefined);

const selectedDeviceId = computed<string | undefined>(() => route.params.deviceId as string);

const route = useRoute();
const router = useRouter();

// 通知状态（替代 PrimeVue Toast）
const snackbar = ref(false);
const snackbarMessage = ref('');

const loadDevices = async () => {
    const resp = await api?.list_machines();
    let devices: Array<Utils.DeviceInfo> = [];
    for (const device of (resp || [])) {
        devices.push(Utils.buildDeviceInfo(device));
    }
    console.debug("device list", deviceList.value);
    deviceList.value = devices;
};

const periodFunc = new Utils.PeriodicTask(async () => {
    try {
        await loadDevices();
    } catch (e) {
        snackbarMessage.value = `Load Device List Failed: ${e}`;
        snackbar.value = true;
        console.error(e);
    }
}, 1000);

onMounted(async () => {
    periodFunc.start();
    // 初始化屏幕尺寸相关变量
    handleResize();
    window.addEventListener('resize', handleResize);
});

onUnmounted(() => {
    periodFunc.stop();
    window.removeEventListener('resize', handleResize);
});

const deviceManageVisible = computed<boolean>({
    get: () => !!selectedDeviceId.value,
    set: (value) => {
        if (!value) {
            router.push({ name: 'deviceList', params: { deviceId: undefined } });
        }
    }
});

const selectedDeviceHostname = computed<string | undefined>(() => {
    return deviceList.value?.find((device) => device.machine_id === selectedDeviceId.value)?.hostname;
});

// 处理设备管理
const handleDeviceManagement = (device: Utils.DeviceInfo) => {
    const instanceId = device.running_network_instances?.[0];
    router.push({
        name: 'deviceManagement',
        params: {
            deviceId: device.machine_id,
            instanceId: instanceId
        }
    });
};

// 显示设备详情
const showDeviceDetails = (device: Utils.DeviceInfo, _event: Event) => {
    selectedDevice.value = device;
    detailDialog.value = true;
};

// 检查是否为桌面设备
const isDesktop = ref(false);
// 检查是否为多卡片视图（一行可以放置多个卡片）
const isMultiCardView = ref(false);

// 视口宽度，用于响应式计算抽屉宽度
const windowWidth = ref(window.innerWidth);

// 抽屉布局相关
const drawerWidth = computed(() => {
    // 桌面端为 60% 宽度（最小 384px），移动端为全屏底部抽屉
    return isDesktop.value ? Math.max(384, Math.round(windowWidth.value * 0.6)) : 0;
});

const drawerPosition = computed(() => {
    return isDesktop.value ? 'right' : 'bottom';
});

const drawerHeight = computed(() => {
    return isDesktop.value ? undefined : '100%';
});

// 排序相关
const sortOptions = ref([
    { name: () => t('web.device.sort_by_hostname'), value: 'hostname', icon: 'mdi-home' },
    { name: () => t('web.device.sort_by_version'), value: 'version', icon: 'mdi-tag' },
    { name: () => t('web.device.sort_by_networks'), value: 'networks', icon: 'mdi-sitemap' }
]);
const selectedSortOption = ref(sortOptions.value[0]);
// 排序方向 (true为升序，false为降序)
const ascending = ref(true);

// 切换排序方向
const toggleSortDirection = () => {
    ascending.value = !ascending.value;
};

// 排序函数
const sortDevices = (devices: Array<Utils.DeviceInfo> | undefined) => {
    if (!devices) return [];

    const sortField = selectedSortOption.value.value;
    const direction = ascending.value ? 1 : -1;

    return [...devices].sort((a, b) => {
        let result = 0;

        switch (sortField) {
            case 'hostname':
                result = a.hostname.localeCompare(b.hostname);
                break;
            case 'version':
                result = a.easytier_version.localeCompare(b.easytier_version);
                break;
            case 'networks':
                result = a.running_network_count - b.running_network_count;
                break;
        }

        return result * direction;
    });
};

// 排序后的设备列表
const sortedDeviceList = computed(() => {
    return sortDevices(deviceList.value);
});

// 保存resize事件处理函数的引用，以便正确移除
const handleResize = () => {
    windowWidth.value = window.innerWidth;
    isDesktop.value = window.innerWidth >= 768;
    // 当容器宽度足够放置两个或更多卡片时，视为多卡片视图
    isMultiCardView.value = window.innerWidth >= 650;
};

</script>

<style scoped>
/* 卡片容器 */
.card-container {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 1rem;
    width: 100%;
    position: relative;
    /* 确保子元素的绝对定位相对于此容器 */
}

/* 卡片内详情区域 */
.card-details {
    background-color: rgb(var(--v-theme-surfaceContainerLow));
    border-top: 1px solid rgb(var(--v-theme-outlineVariant));
}

/* 卡片内详情内容的特定样式 */
:deep(.card-details-content) {
    padding: 0.15rem 0.1rem;
}

:deep(.card-details-content .detail-label) {
    font-size: 0.9rem;
}

:deep(.card-details-content .detail-value) {
    font-size: 0.85rem;
}

/* 设备详情弹窗 */
.device-details-popover {
    min-width: 280px;
    max-width: 350px;
}

.popover-header {
    background-color: rgb(var(--v-theme-surfaceContainerLow));
    border-bottom: 1px solid rgb(var(--v-theme-outlineVariant));
}

/* Popover 详情内容的特定样式 */
:deep(.popover-details-content) {
    padding: 0.25rem 0.2rem;
    max-width: 320px;
}

:deep(.popover-details-content .detail-label) {
    font-size: 0.8rem;
}

:deep(.popover-details-content .detail-value) {
    font-size: 0.8rem;
}

:deep(.popover-details-content .machine-id-value) {
    font-size: 0.7rem;
}

/* 动画效果 */
@keyframes fadeIn {
    from {
        opacity: 0;
        transform: translateY(-10px);
    }

    to {
        opacity: 1;
        transform: translateY(0);
    }
}

.fade-in {
    animation: fadeIn 0.3s ease-out;
}

/* 抽屉关闭按钮 */
.drawer-fab-close-btn {
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.18);
}

/* 位置样式 */
.location-icon {
    color: rgb(var(--v-theme-error));
    opacity: 0.8;
}

.location-text {
    font-size: 0.875rem;
    line-height: 1.25rem;
    opacity: 0.9;
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
}

.location-separator {
    opacity: 0.5;
    font-weight: 300;
    margin: 0 0.1rem;
}

/* 移动端卡片样式 */
@media (max-width: 768px) {
    .card-container {
        grid-template-columns: 1fr;
    }
}
</style>

<template>
    <div class="d-flex flex-column ga-4">
        <!-- 标题和工具栏 -->
        <div>
            <h1 class="text-h5 font-weight-bold">{{ t('web.device.list') }}</h1>
        </div>

        <v-sheet class="d-flex flex-wrap align-center ga-3 pa-3" rounded="lg" border>
            <span class="text-body-2 text-medium-emphasis d-none d-sm-inline">{{ t('web.device.sort_by') }}：</span>
            <v-select v-model="selectedSortOption" :items="sortOptions" return-object
                style="min-width: 150px; max-width: 240px;">
                <template #selection="{ item }">
                    <div class="d-flex align-center ga-2">
                        <v-icon size="18" :icon="item.raw.icon" />
                        <span>{{ item.raw.name() }}</span>
                    </div>
                </template>
                <template #item="{ props: itemProps, item }">
                    <v-list-item v-bind="itemProps" :title="item.raw.name()">
                        <template #prepend>
                            <v-icon size="18" :icon="item.raw.icon" />
                        </template>
                    </v-list-item>
                </template>
            </v-select>
            <v-tooltip :text="ascending ? t('web.device.sort_direction_asc') : t('web.device.sort_direction_desc')"
                location="top">
                <template #activator="{ props: tooltipProps }">
                    <v-btn v-bind="tooltipProps" :icon="ascending ? 'mdi-sort-ascending' : 'mdi-sort-descending'"
                        variant="text" color="secondary" @click="toggleSortDirection" />
                </template>
            </v-tooltip>
            <v-divider vertical inset class="d-none d-sm-flex mx-2" />
            <v-spacer />
            <div class="d-flex align-center ga-2">
                <v-switch id="detailed-view" v-model="showDetailedView" color="primary" hide-details density="compact"
                    :label="t('web.device.show_detailed_view')" />
            </div>
        </v-sheet>

        <div v-if="deviceList === undefined" class="w-100 d-flex justify-center py-8">
            <v-progress-circular indeterminate color="primary" size="48" />
        </div>

        <div v-if="deviceList !== undefined">
            <!-- 卡片视图 (适用于所有屏幕尺寸) -->
            <div class="card-container">
                <v-card v-for="device in sortedDeviceList" :key="device.machine_id" class="device-card"
                    rounded="lg" elevation="2">
                    <!-- 卡片头部 -->
                    <div class="pa-3 d-flex flex-column ga-2">
                        <!-- 上部区域：设备名称和版本徽章 -->
                        <div class="d-flex justify-space-between align-center">
                            <!-- 设备名称 -->
                            <div class="font-weight-bold text-truncate card-title" :title="device.hostname">
                                {{ device.hostname }}
                            </div>

                            <!-- 版本徽章 -->
                            <v-tooltip :text="`EasyTier ${device.easytier_version}`" location="top">
                                <template #activator="{ props: tooltipProps }">
                                    <v-chip v-bind="tooltipProps" size="x-small" color="primary">
                                        v{{ device.easytier_version.split('-')[0] }}
                                    </v-chip>
                                </template>
                            </v-tooltip>
                        </div>

                        <!-- 下部区域：IP地址和操作按钮 -->
                        <div class="d-flex justify-space-between align-center">
                            <!-- IP地址和位置信息 -->
                            <div class="text-body-2 text-truncate d-flex align-center ga-1 card-subtitle"
                                style="max-width: 60%;"
                                :title="device.location ? `${device.location.country}${device.location.region ? ' · ' + device.location.region : ''}${device.location.city ? ' · ' + device.location.city : ''}` : t('web.device.unknown_location')">
                                <v-icon size="16" class="location-icon" icon="mdi-map-marker" />
                                <span class="location-text">
                                    <template v-if="device.location">
                                        {{ device.location.country }}
                                        <template v-if="device.location.region">
                                            <span class="location-separator">·</span>
                                            {{ device.location.region }}
                                        </template>
                                        <template v-if="device.location.city">
                                            <span class="location-separator">·</span>
                                            {{ device.location.city }}
                                        </template>
                                    </template>
                                    <template v-else>
                                        {{ t('web.device.unknown_location') }}
                                    </template>
                                </span>
                            </div>

                            <!-- 操作按钮组 -->
                            <div class="d-flex align-center ga-1">
                                <!-- 网络数量徽章 -->
                                <v-tooltip :text="t('web.device.network_count')" location="top">
                                    <template #activator="{ props: tooltipProps }">
                                        <v-chip v-bind="tooltipProps" size="x-small" color="primary" variant="tonal">
                                            {{ device.running_network_count }}
                                        </v-chip>
                                    </template>
                                </v-tooltip>

                                <!-- 详情按钮 -->
                                <v-tooltip v-if="!showDetailedView" :text="t('web.device.show_detailed_view')"
                                    location="top">
                                    <template #activator="{ props: tooltipProps }">
                                        <v-btn v-bind="tooltipProps" icon="mdi-information" size="small"
                                            variant="text" color="info" @click="showDeviceDetails(device, $event)" />
                                    </template>
                                </v-tooltip>

                                <!-- 设置按钮 -->
                                <v-btn icon="mdi-cog" size="small" variant="tonal" color="secondary" rounded="circle"
                                    :title="`Manage ${device.hostname}`" @click="handleDeviceManagement(device)" />
                            </div>
                        </div>
                    </div>

                    <!-- 详情区域 - 当开启详情显示时展示 -->
                    <div v-if="showDetailedView" class="card-details fade-in">
                        <DeviceDetails :device="device" containerClass="card-details-content" :compact="true" />
                    </div>
                </v-card>
            </div>
        </div>

        <!-- 全局设备详情弹窗 -->
        <v-dialog v-model="detailDialog" max-width="380">
            <v-card v-if="selectedDevice" rounded="lg">
                <div class="d-flex align-center ga-2 px-4 py-3 popover-header">
                    <v-icon icon="mdi-information" />
                    <span class="font-weight-bold">设备详情</span>
                    <v-spacer />
                    <v-btn icon="mdi-close" size="small" variant="text" @click="detailDialog = false" />
                </div>
                <v-card-text class="device-details-popover">
                    <DeviceDetails :device="selectedDevice" containerClass="popover-details-content"
                        :compact="true" />
                </v-card-text>
            </v-card>
        </v-dialog>

        <!-- 设备管理抽屉：桌面端右侧抽屉，移动端全屏底部抽屉 -->
        <!-- order=-1 使抽屉及其遮罩位于应用栏/侧边栏之上（对应原 PrimeVue Drawer 的模态遮罩） -->
        <v-navigation-drawer v-model="deviceManageVisible" :location="drawerPosition" :width="drawerWidth"
            :style="isDesktop ? undefined : { height: drawerHeight }" :rounded="isDesktop ? undefined : 't-xl'"
            :aria-label="`Manage ${selectedDeviceHostname}`" :order="-1" temporary disable-route-watcher
            touchless>
            <div class="device-manage-drawer position-relative h-100">
                <RouterView v-slot="{ Component }">
                    <component :is="Component" :api="api" :deviceList="deviceList" @update="loadDevices" />
                </RouterView>
                <v-btn icon="mdi-close" color="error" size="52" elevation="8" rounded="circle"
                    class="drawer-fab-close-btn" style="position: absolute; right: 1.5rem; bottom: 1.5rem; z-index: 10;"
                    @click="deviceManageVisible = false" />
            </div>
        </v-navigation-drawer>

        <v-snackbar v-model="snackbar" color="error" :timeout="2000" location="bottom">
            {{ snackbarMessage }}
        </v-snackbar>
    </div>
</template>
