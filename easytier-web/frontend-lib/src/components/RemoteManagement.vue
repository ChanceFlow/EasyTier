<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import * as Api from '../modules/api';
import * as Utils from '../modules/utils';
import * as NetworkTypes from '../types/network';
import Config from './Config.vue';
import Status from './Status.vue';
import ConfigEditDialog from './ConfigEditDialog.vue';
import HumanEvent from './HumanEvent.vue';
import { useTimeAgo } from '@vueuse/core';

const { t } = useI18n()

const props = withDefaults(defineProps<{
    api: Api.RemoteClient;
    newConfigGenerator?: () => NetworkTypes.NetworkConfig;
    pauseAutoRefresh?: boolean;
    /** 移动端 Hero 的权威连接态(VPN 感知):传入时覆盖 Status 的 RPC running。 */
    connectedOverride?: boolean;
    /** 移动端:Status 的电源球只读,只作为 Hero 的镜像。 */
    hidePowerToggle?: boolean;
}>(), {
    // 必须显式 undefined:Boolean prop 若没有 default,Vue 会在缺省时转成 false,
    // 转发给 Status 后会吞掉 RPC running 状态,桌面/测试行为就会变。
    connectedOverride: undefined,
    hidePowerToggle: false,
});

const instanceId = defineModel('instanceId', {
    type: String as () => string | undefined,
    required: false,
})

const emits = defineEmits(['update']);

// 触觉反馈:navigator.vibrate 存在则轻震一下,失败静默(组件内局部实现,避免动共享 utils)
function vibrate(ms = 8) {
    try {
        navigator.vibrate?.(ms);
    } catch {
        /* ignore */
    }
}

const toast = ref(false)
const toastMessage = ref('')
const toastColor = ref('success')

function showToast(message: string, color: 'success' | 'error' | 'info' = 'success') {
    toastMessage.value = message
    toastColor.value = color
    toast.value = true
}

const configFile = ref<HTMLInputElement | null>(null);

const curNetworkInfo = ref<NetworkTypes.NetworkInstance | null>(null);
// 记录 curNetworkInfo 当前对应的实例 id:仅当选中实例真的变化时才清空,静默轮询不清,避免骨架闪烁
const infoLoadedInstanceId = ref<string | null>(null);

const showConfigEditDialog = ref(false);
const isEditingNetwork = ref(false);
const currentNetworkConfig = ref<NetworkTypes.NetworkConfig | undefined>(undefined);

const listInstanceIdResponse = ref<Api.ListNetworkInstanceIdResponse | undefined>(undefined);

// ---- 加载状态:initialLoadDone=实例列表首刷已回;isRefreshing=后续静默轮询中 ----
const initialLoadDone = ref(false);
const isRefreshing = ref(false);
// Config 面板专属:当前网络配置在途
const configLoading = ref(false);

const isRunning = (instanceId: string) => {
    return (listInstanceIdResponse.value?.running_inst_ids ?? []).map(Utils.UuidToStr).includes(instanceId);
}

const networkMetaCache = ref<Record<string, Api.NetworkMeta>>({});
const loadNetworkMetas = async (instanceIds: string[]) => {
    const missingIds = instanceIds.filter(id => !networkMetaCache.value[id]);

    if (missingIds.length === 0) return;

    try {
        const response = await props.api.get_network_metas(missingIds);
        Object.assign(networkMetaCache.value, response.metas ?? {});
    } catch (e) {
        console.error("Failed to load network metas", e);
    }
};
const onLazyLoadNetworkMetas = async () => {
    const instanceIds = instanceList.value.map(item => item.uuid);
    await loadNetworkMetas(instanceIds);
};
const currentNetworkMeta = computed(() => {
    if (!instanceId.value) {
        return undefined;
    }
    return networkMetaCache.value[instanceId.value];
});
const currentNetworkControl = {
    remoteSave: computed(() => {
        return Api.ConfigFilePermission.isRemoveSaveable(currentNetworkMeta.value?.config_permission ?? 0);
    }),
    editable: computed(() => {
        return Api.ConfigFilePermission.isEditable(currentNetworkMeta.value?.config_permission ?? 0);
    }),
    deletable: computed(() => {
        return Api.ConfigFilePermission.isDeletable(currentNetworkMeta.value?.config_permission ?? 0);
    })
}

const instanceList = ref<Array<{ uuid: string; meta?: Api.NetworkMeta }>>([]);
const updateInstanceList = () => {
    let insts = new Set<string>();
    let t = listInstanceIdResponse.value;
    if (t) {
        (t.running_inst_ids ?? []).forEach((u) => insts.add(Utils.UuidToStr(u)));
        (t.disabled_inst_ids ?? []).forEach((u) => insts.add(Utils.UuidToStr(u)));
    }

    const newList = Array.from(insts).map((instance: string) => {
        return {
            uuid: instance,
            meta: networkMetaCache.value[instance]
        };
    });

    if (JSON.stringify(newList) !== JSON.stringify(instanceList.value)) {
        instanceList.value = newList;
    }
}
watch(listInstanceIdResponse, updateInstanceList, { deep: false });
watch(networkMetaCache, updateInstanceList, { deep: true });
watch(instanceList, async (newVal) => {
    if (newVal) {
        const instanceIds = new Set(newVal.map(item => item.uuid));
        Object.keys(networkMetaCache.value).forEach(id => {
            if (!instanceIds.has(id)) {
                delete networkMetaCache.value[id];
            }
        });
    }
});

const selectedInstanceId = computed({
    get() {
        return instanceList.value.find((instance) => instance.uuid === instanceId.value);
    },
    set(value: any) {
        instanceId.value = value ? value.uuid : undefined;
    }
});
watch(selectedInstanceId, async (newVal, oldVal) => {
    const instanceChanged = newVal?.uuid !== oldVal?.uuid;
    if (instanceChanged) {
        // 切换了网络:立刻丢弃上一个网络的 hostname / 虚拟 IP / 对端列表,让界面回落到骨架
        curNetworkInfo.value = null;
        infoLoadedInstanceId.value = null;
    }
    // 新建/编辑流程会先清空选择,此时 newVal 为空:不能走 loadCurrentNetworkConfig(),
    // 否则它第一行就把 newNetwork() 刚赋值的默认配置清成 undefined。
    if (instanceChanged && newVal && (networkIsDisabled.value || isEditingNetwork.value)) {
        await loadCurrentNetworkConfig();
    } else {
        await loadCurrentNetworkInfo();
    }

    if (newVal?.uuid && !networkMetaCache.value[newVal.uuid]) {
        await loadNetworkMetas([newVal.uuid]);
    }
});

const needShowNetworkStatus = computed(() => {
    if (!selectedInstanceId.value) {
        return false;
    }
    if (isEditingNetwork.value) {
        return false;
    }
    return true;
})

// ---- 移动端底部原生 Tab ----
const mobileTab = ref<'home' | 'devices' | 'config' | 'activity'>('home');
watch(mobileTab, async (newTab) => {
    if (newTab === 'config' && !currentNetworkConfig.value) {
        await loadCurrentNetworkConfig();
    }
});

// ---- 移动端网络切换 Bottom Sheet ----
const networkSheetOpen = ref(false);

const heroIsRunning = computed(() => {
    // 移动端:已提供 Hero 的权威隧道态时,顶部网络卡片镜像它,而不是 RPC running
    // (运行中的进程 ≠ 隧道真的通)。缺省(undefined)时保持原有 RPC 语义,桌面不变。
    if (props.connectedOverride !== undefined && selectedInstanceId.value) {
        return props.connectedOverride
    }
    return !!selectedInstanceId.value && isRunning(selectedInstanceId.value.uuid);
});

const heroNetworkName = computed(() => {
    const sel = selectedInstanceId.value;
    if (!sel) {
        return t('web.device_management.network');
    }
    return sel.meta?.network_name ?? sel.uuid;
});

function openNetworkSheet() {
    if (isEditingNetwork.value) {
        return;
    }
    onLazyLoadNetworkMetas();
    networkSheetOpen.value = true;
}

function sheetSelectNetwork(item: { uuid: string }) {
    networkSheetOpen.value = false;
    onSelectNetwork(item.uuid);
}

function sheetCreateNew() {
    networkSheetOpen.value = false;
    newNetwork();
}

const networkIsDisabled = computed(() => {
    if (!selectedInstanceId.value) {
        return false;
    }
    return (listInstanceIdResponse.value?.disabled_inst_ids ?? []).map(Utils.UuidToStr).includes(selectedInstanceId.value?.uuid);
});
watch(networkIsDisabled, async (newVal, oldVal) => {
    if (newVal !== oldVal && newVal === true) {
        await loadCurrentNetworkConfig();
    }
});

const loadCurrentNetworkConfig = async () => {
    currentNetworkConfig.value = undefined;

    if (!selectedInstanceId.value) {
        return;
    }

    configLoading.value = true;
    try {
        let ret = await props.api.get_network_config(selectedInstanceId.value!.uuid);
        currentNetworkConfig.value = ret;
    } finally {
        configLoading.value = false;
    }
}

function setCurrentNetworkRunning(running: boolean): void {
    if (!curNetworkInfo.value) {
        return
    }
    if (selectedInstanceId.value && curNetworkInfo.value.instance_id !== selectedInstanceId.value.uuid) {
        return
    }
    curNetworkInfo.value = {
        ...curNetworkInfo.value,
        running,
    }
}

const stopNetwork = async (): Promise<void> => {
    if (!selectedInstanceId.value) {
        return;
    }

    await props.api.update_network_instance_state(selectedInstanceId.value.uuid, true);
    await loadNetworkInstanceIds();
    setCurrentNetworkRunning(false)
}

const startNetwork = async (): Promise<void> => {
    if (!selectedInstanceId.value) {
        return;
    }
    await props.api.update_network_instance_state(selectedInstanceId.value.uuid, false);
    await loadNetworkInstanceIds();
    setCurrentNetworkRunning(true)
}

const toggleCurrentNetwork = async () => {
    vibrate(10);
    if (heroIsRunning.value) {
        await stopNetwork();
    } else {
        await startNetwork();
    }
}

const confirmDialog = ref(false)
const confirmAction = ref<() => void>(() => {})
const confirmMessage = ref('')
const confirmHeader = ref('')

function requireConfirm(message: string, header: string, action: () => void) {
    confirmMessage.value = message
    confirmHeader.value = header
    confirmAction.value = action
    confirmDialog.value = true
}

const confirmDeleteNetwork = () => {
    requireConfirm(
        t('web.device_management.delete_network_confirm') || 'Do you want to delete this network?',
        t('web.device_management.delete_network'),
        async () => {
            try {
                await props.api.delete_network(instanceId.value!);
            } catch (e) {
                console.error(e);
            }
            emits('update');
        }
    );
};

const saveAndRunNewNetwork = async (config?: NetworkTypes.NetworkConfig) => {
    const cfg = config ?? currentNetworkConfig.value;
    if (!cfg) {
        return;
    }

    const targetInstanceId = instanceId.value ?? cfg.instance_id;
    if (targetInstanceId && cfg.instance_id !== targetInstanceId) {
        cfg.instance_id = targetInstanceId;
    }

    try {
        if (networkIsDisabled.value) {
            await props.api.save_config(cfg);
            await props.api.update_network_instance_state(cfg.instance_id, false);
        } else {
            await props.api.run_network(cfg, currentNetworkControl.remoteSave.value);
        }

        delete networkMetaCache.value[cfg.instance_id];
        await loadNetworkMetas([cfg.instance_id]);

        selectedInstanceId.value = { uuid: cfg.instance_id };
        await loadNetworkInstanceIds();
        isEditingNetwork.value = false;
        showToast(t('web.device_management.config_saved') || 'Network started successfully', 'success');
        emits('update');
    } catch (e) {
        console.error(e);
        showToast(String(e), 'error');
    }
}

const saveNetworkConfig = async () => {
    if (!currentNetworkConfig.value) {
        return;
    }

    const targetInstanceId = instanceId.value ?? currentNetworkConfig.value.instance_id;
    if (targetInstanceId && currentNetworkConfig.value.instance_id !== targetInstanceId) {
        currentNetworkConfig.value.instance_id = targetInstanceId;
    }

    try {
        await props.api.save_config(currentNetworkConfig.value);
        delete networkMetaCache.value[currentNetworkConfig.value.instance_id];
        await loadNetworkMetas([currentNetworkConfig.value.instance_id]);
        showToast(t('web.device_management.config_saved') || 'Configuration saved', 'success');
        isEditingNetwork.value = false;
        emits('update');
    } catch (e) {
        console.error(e);
        showToast(String(e), 'error');
    }
}

const newNetwork = async () => {
    isEditingNetwork.value = true;
    selectedInstanceId.value = undefined;
    instanceId.value = undefined;

    if (props.newConfigGenerator) {
        currentNetworkConfig.value = props.newConfigGenerator();
    } else {
        currentNetworkConfig.value = NetworkTypes.DEFAULT_NETWORK_CONFIG();
    }
}

const editNetwork = async () => {
    isEditingNetwork.value = true;
    await loadCurrentNetworkConfig();
}

const cancelEditNetwork = () => {
    isEditingNetwork.value = false;
    loadCurrentNetworkInfo();
}

const loadNetworkInstanceIds = async () => {
    listInstanceIdResponse.value = await props.api.list_network_instance_ids();
    initialLoadDone.value = true;
    // 正在新建/编辑时不要自动选中运行中的实例,否则 1s 轮询会把用户刚打开的表单顶掉。
    if (!instanceId.value && !isEditingNetwork.value && listInstanceIdResponse.value?.running_inst_ids?.length) {
        instanceId.value = Utils.UuidToStr(listInstanceIdResponse.value.running_inst_ids[0]);
    }
}

const loadCurrentNetworkInfo = async () => {
    const targetInstanceId = selectedInstanceId.value?.uuid;
    if (!targetInstanceId) {
        curNetworkInfo.value = null;
        infoLoadedInstanceId.value = null;
        return;
    }

    // 只有选中实例真的变了才清空(渲染骨架);1s 静默轮询不清,避免骨架闪烁
    if (infoLoadedInstanceId.value !== targetInstanceId) {
        curNetworkInfo.value = null;
    }

    try {
        const info = await props.api.get_network_info(targetInstanceId);
        // 响应返回时用户可能已切到别的网络,丢弃过期结果
        if (selectedInstanceId.value?.uuid !== targetInstanceId) {
            return;
        }
        curNetworkInfo.value = {
            instance_id: targetInstanceId,
            running: isRunning(targetInstanceId),
            error_msg: "",
            detail: info as any,
        };
        infoLoadedInstanceId.value = targetInstanceId;
    } catch (e) {
        console.debug(e);
    }
}

const generateConfig = async (config: NetworkTypes.NetworkConfig): Promise<string> => {
    const res = await props.api.generate_config(config);
    return (res as any)?.config ?? (res as any) ?? '';
}

const syncTomlConfig = async (tomlConfig: string) => {
    try {
        const parsed = await props.api.parse_config(tomlConfig) as any;
        // 解析失败时后端会回 error 而不是 config,此时必须给出明确反馈
        if (parsed?.error) {
            showToast(String(parsed.error), 'error');
            return;
        }
        const parsedConfig = (parsed?.config ? parsed.config : parsed) as any;
        // 空内容 / 解析不出配置对象时给出明确反馈,而不是静默什么都不做
        if (!parsedConfig || typeof parsedConfig !== 'object' || Object.keys(parsedConfig).length === 0) {
            showToast(t('web.device_management.import_config_invalid', 'The selected file does not contain a valid config'), 'error');
            return;
        }
        currentNetworkConfig.value = parsedConfig;
        showConfigEditDialog.value = false;
        showToast(t('web.common.success') || 'Configuration imported', 'success');
    } catch (e) {
        console.error(e);
        showToast(String(e), 'error');
    }
}

const exportConfig = async () => {
    if (!selectedInstanceId.value) return;
    try {
        const cfg = await props.api.get_network_config(selectedInstanceId.value.uuid);
        const res = await props.api.generate_config(cfg);
        const toml = typeof res === 'string' ? res : (res as any)?.config ?? '';
        const blob = new Blob([toml], { type: 'text/plain;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${cfg.network_name || 'easytier'}.toml`;
        a.style.display = 'none';
        // 必须先挂到 DOM 再 click,否则部分浏览器(含 Android WebView)会取消下载
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        // 延迟释放:同一 tick 释放可能打断下载
        setTimeout(() => URL.revokeObjectURL(url), 1500);
        showToast(t('web.device_management.export_config_success', 'Config exported'), 'success');
    } catch (e) {
        console.error('Export failed', e);
        showToast(String(e), 'error');
    }
}

const importConfig = (): void => {
    configFile.value?.click();
}

interface ConfigActionItem {
    key: 'edit' | 'import' | 'save'
    icon: string
    labelKey: string
    primary: boolean
    disabled: boolean
    run: () => void
}

const configActions = computed<ConfigActionItem[]>(() => [
    {
        key: 'edit',
        icon: 'mdi-file-code-outline',
        labelKey: 'web.device_management.edit_as_file',
        primary: false,
        disabled: false,
        run: (): void => {
            showConfigEditDialog.value = true
        },
    },
    {
        key: 'import',
        icon: 'mdi-tray-arrow-up',
        labelKey: 'web.device_management.import_config',
        primary: false,
        disabled: false,
        run: importConfig,
    },
    {
        key: 'save',
        icon: 'mdi-content-save-outline',
        labelKey: 'web.device_management.save_config',
        primary: true,
        disabled: !currentNetworkConfig.value,
        run: (): void => {
            void saveNetworkConfig()
        },
    },
])

const handleFileUpload = async (e: Event) => {
    const input = e.target as HTMLInputElement;
    try {
        const file = input.files?.[0];
        if (!file) return;
        const text = await file.text();
        await syncTomlConfig(text);
    } catch (err) {
        console.error('Failed to read config file', err);
        showToast(String(err), 'error');
    } finally {
        // 清空 value,否则再次选择同一个文件不会触发 change
        input.value = '';
    }
}

// 更多操作面板(锚定底部 sheet,不再用裸坐标 v-menu)
const actionMenuOpen = ref(false)

function openActionMenu() {
    actionMenuOpen.value = true
}

function runActionMenu(action: string) {
    actionMenuOpen.value = false
    switch (action) {
        case 'edit':
            editNetwork()
            break
        case 'export':
            exportConfig()
            break
        case 'delete':
            confirmDeleteNetwork()
            break
    }
}

function onSelectNetwork(value: unknown) {
    const uuid = typeof value === 'string' ? value : (value as any)?.uuid
    if (!uuid) {
        instanceId.value = undefined
        return
    }
    const found = instanceList.value.find(i => i.uuid === uuid)
    selectedInstanceId.value = found ?? { uuid }
}

let periodFunc = new Utils.PeriodicTask(async () => {
    if (props.pauseAutoRefresh) {
        return;
    }
    // 页面不可见(切后台/锁屏)时不轮询:省电,也避免无意义的 RPC
    if (typeof document !== 'undefined' && document.hidden) {
        return;
    }
    // 静默刷新:只更新顶部细线指示,不清骨架、不拦截点击
    isRefreshing.value = true;
    try {
        const tasks: Array<Promise<unknown>> = [loadNetworkInstanceIds()];
        // 正在编辑表单时不要用静默刷新覆盖当前网络数据
        if (!isEditingNetwork.value) {
            tasks.push(loadCurrentNetworkInfo());
        }
        await Promise.all(tasks);
    } catch (e) {
        console.debug(e);
    } finally {
        isRefreshing.value = false;
    }
}, 1000);

onMounted(async () => {
    periodFunc.start();
});

onUnmounted(() => {
    periodFunc.stop();
});

const peerCount = computed(() => {
    return curNetworkInfo.value?.detail?.peer_route_pairs?.length ?? 0
})

const activityEvents = computed(() => {
    const detail = curNetworkInfo.value?.detail
    if (!detail?.events) return []
    return detail.events.map((event: string) => JSON.parse(event))
})

/** 事件日志的稳定 key:时间 + 事件内容,重渲染不会错位。 */
function eventTimelineKey(item: any): string {
    try {
        return `${item?.time ?? 'na'}-${JSON.stringify(item?.event ?? {})}`
    } catch {
        return `${item?.time ?? 'na'}`
    }
}

</script>

<template>
    <div class="device-management" :class="{ 'has-tab-bar': needShowNetworkStatus }">
        <input
            type="file"
            @change="handleFileUpload"
            class="d-none"
            accept=".toml,application/toml,text/plain,application/octet-stream,text/x-toml"
            ref="configFile"
        />

        <!-- 静默刷新指示:顶部 2px 细线,pointer-events:none,绝不拦截任何点击 -->
        <div
            class="et-refresh-bar"
            :class="{ 'is-active': isRefreshing && mobileTab !== 'config' }"
            aria-hidden="true"
        />

        <!-- ================= 1. Top Network Switcher Profile Card ================= -->
        <!-- 整块可点,但内部还有"更多操作"按钮:嵌套 button 是非法 HTML,所以用
             role=button + tabindex + 键盘处理,保证键盘与读屏可达。 -->
        <div
            class="et-network-chip et-press-row d-flex align-center justify-space-between mb-3 mt-2"
            :aria-label="`${heroNetworkName} · ${heroIsRunning ? t('web.device_management.active') : t('web.device_management.stopped')}`"
            @click="openNetworkSheet"
            @keydown.enter.prevent="openNetworkSheet"
            @keydown.space.prevent="openNetworkSheet"
            role="button"
            tabindex="0"
        >
            <div class="d-flex align-center ga-3 min-w-0">
                <div
                    class="et-squircle"
                    :style="{ background: heroIsRunning ? 'var(--et-accent-quiet)' : 'var(--et-surface-2)' }"
                >
                    <v-icon size="18" :color="heroIsRunning ? 'primary' : 'medium-emphasis'">
                        {{ heroIsRunning ? 'mdi-shield-check' : 'mdi-shield-outline' }}
                    </v-icon>
                </div>
                <div class="min-w-0">
                  <template v-if="initialLoadDone">
                        <div class="d-flex align-center ga-2">
                            <span class="hero-net-name truncate">{{ heroNetworkName }}</span>
                            <v-chip :color="heroIsRunning ? 'success' : 'default'" size="x-small" variant="tonal" class="rounded-pill font-weight-bold">
                                {{ heroIsRunning ? t('web.device_management.active') : t('web.device_management.stopped') }}
                            </v-chip>
                        </div>
                        <div class="text-caption text-medium-emphasis truncate">
                            {{ isEditingNetwork ? t('web.device_management.edit_network') : t('web.device_management.select_network') }}
                        </div>
                    </template>
                    <!-- 首刷未回:贴合两行文字布局的骨架占位 -->
                    <div v-else role="progressbar" aria-hidden="true" class="et-skeleton et-skeleton--inline">
                        <v-skeleton-loader type="list-item" boilerplate style="max-width: 10rem" class="mb-1" />
                        <v-skeleton-loader type="list-item" boilerplate style="max-width: 14rem" />
                    </div>
                </div>
            </div>

            <div class="d-flex align-center ga-1 flex-shrink-0">
                <template v-if="isEditingNetwork">
                    <v-btn icon="mdi-close" size="small" variant="text" :aria-label="t('web.device_management.cancel_edit')" @click.stop="cancelEditNetwork" />
                </template>
                <template v-else>
                    <v-btn v-if="selectedInstanceId" icon="mdi-dots-vertical" size="small" variant="text" :aria-label="t('web.device_management.more_actions')" @click.stop="openActionMenu" />
                    <v-icon size="20" color="medium-emphasis">mdi-chevron-down</v-icon>
                </template>
            </div>
        </div>

        <!-- Network Switcher Bottom Sheet (iOS Action Sheet) -->
        <v-bottom-sheet v-model="networkSheetOpen" scrollable>
            <v-card rounded="t-xl" class="et-network-sheet">
                <!-- 抓条:原生 button,视觉仍是一根小药丸,外层提供 >=48px 触摸区域 -->
                <button type="button" class="et-sheet-grabber-hit" :aria-label="t('close')" @click="networkSheetOpen = false">
                    <span class="sheet-grabber" aria-hidden="true" />
                </button>
                <v-card-title class="d-flex align-center justify-space-between pt-1 pb-2">
                    <span class="text-subtitle-1 font-weight-bold">{{ t('web.device_management.network') }}</span>
                    <div class="d-flex align-center ga-1">
                        <v-btn color="primary" variant="flat" size="small" rounded="pill" :prepend-icon="'mdi-plus'" @click="sheetCreateNew">
                            {{ t('web.device_management.create_new') }}
                        </v-btn>
                        <v-btn icon="mdi-close" variant="text" size="small" :aria-label="t('close')" @click="networkSheetOpen = false" />
                    </div>
                </v-card-title>
                <v-card-text class="pa-2">
                    <!-- 实例列表首刷未回:骨架 -->
                    <div v-if="!initialLoadDone" class="py-2" role="progressbar" aria-hidden="true">
                        <v-skeleton-loader class="et-skeleton" type="list-item-avatar-two-line@3" boilerplate />
                    </div>
                    <div v-else-if="instanceList.length === 0" class="et-empty">
                        <div class="et-empty__icon"><v-icon size="26" color="primary">mdi-shield-plus-outline</v-icon></div>
                        <div class="et-empty__title">{{ t('web.device_management.no_network_selected') }}</div>
                        <div class="et-empty__hint">{{ t('web.device_management.rm_sheet_empty_hint', 'Create a network to join your mesh') }}</div>
                    </div>
                    <TransitionGroup v-else tag="div" name="et-list-fade" class="ios-group mb-2 et-list-wrap">
                        <button
                            v-for="item in instanceList"
                            :key="item.uuid"
                            type="button"
                            class="et-row et-row-pressable et-press-row"
                            :aria-label="`${item.meta?.network_name ?? item.uuid} · ${t(isRunning(item.uuid) ? 'network_running' : 'network_stopped')}`"
                            @click="sheetSelectNetwork(item)"
                        >
                            <div class="d-flex align-center ga-3 min-w-0">
                                <div class="et-squircle" :style="{ background: isRunning(item.uuid) ? 'var(--et-accent-quiet)' : 'var(--et-surface-2)' }">
                                    <v-icon size="18" :color="isRunning(item.uuid) ? 'primary' : 'medium-emphasis'">
                                        {{ isRunning(item.uuid) ? 'mdi-shield-check' : 'mdi-shield-off' }}
                                    </v-icon>
                                </div>
                                <div class="min-w-0">
                                    <div class="font-weight-bold truncate">{{ item.meta?.network_name ?? item.uuid }}</div>
                                    <div class="text-caption text-mono text-medium-emphasis truncate">{{ item.uuid }}</div>
                                </div>
                            </div>
                            <div class="d-flex align-center ga-2 flex-shrink-0">
                                <v-chip :color="isRunning(item.uuid) ? 'success' : 'default'" size="x-small" variant="tonal" class="rounded-pill">
                                    {{ t(isRunning(item.uuid) ? 'network_running' : 'network_stopped') }}
                                </v-chip>
                                <v-icon v-if="item.uuid === selectedInstanceId?.uuid" color="primary" size="20">mdi-check-circle</v-icon>
                            </div>
                        </button>
                    </TransitionGroup>
                </v-card-text>
            </v-card>
        </v-bottom-sheet>

        <!-- More actions:锚定底部动作面板,整行 >=48px(移动端比裸坐标菜单更可用) -->
        <v-bottom-sheet v-model="actionMenuOpen">
            <v-card rounded="t-xl" class="et-network-sheet">
                <button type="button" class="et-sheet-grabber-hit" :aria-label="t('close')" @click="actionMenuOpen = false">
                    <span class="sheet-grabber" aria-hidden="true" />
                </button>
                <v-card-title class="d-flex align-center justify-space-between pt-1 pb-2">
                    <span class="text-subtitle-1 font-weight-bold">{{ t('web.device_management.more_actions') }}</span>
                    <v-btn icon="mdi-close" variant="text" size="small" :aria-label="t('close')" @click="actionMenuOpen = false" />
                </v-card-title>
                <v-card-text class="pa-2">
                    <v-list density="comfortable" rounded="xl" class="et-menu-list">
                        <v-list-item v-if="currentNetworkControl.editable.value" class="et-sheet-action" @click="runActionMenu('edit')">
                            <template #prepend><v-icon size="20">mdi-pencil</v-icon></template>
                            <v-list-item-title>{{ t('web.device_management.edit_network') }}</v-list-item-title>
                        </v-list-item>
                        <v-list-item class="et-sheet-action" @click="runActionMenu('export')">
                            <template #prepend><v-icon size="20">mdi-download</v-icon></template>
                            <v-list-item-title>{{ t('web.device_management.export_config') }}</v-list-item-title>
                        </v-list-item>
                        <v-list-item v-if="currentNetworkControl.deletable.value" class="et-sheet-action" @click="runActionMenu('delete')">
                            <template #prepend><v-icon color="error" size="20">mdi-trash-can-outline</v-icon></template>
                            <v-list-item-title class="text-error">{{ t('web.device_management.delete_network') }}</v-list-item-title>
                        </v-list-item>
                    </v-list>
                </v-card-text>
            </v-card>
        </v-bottom-sheet>

        <!-- ================= 2. Main Content Area ================= -->
        <div class="network-content">
            <!-- Mode A: Network Creation Form (when user clicked Create/Edit) -->
            <div v-if="isEditingNetwork" class="network-creation-container">
                <div class="d-flex align-center justify-space-between mb-3">
                    <div class="d-flex align-center ga-2">
                        <v-icon color="primary" size="22">mdi-tune-variant</v-icon>
                        <h2 class="text-subtitle-1 font-weight-bold">{{ t('web.device_management.edit_network') }}</h2>
                    </div>
                    <v-btn icon="mdi-close" size="small" variant="text" :aria-label="t('web.device_management.cancel_edit')" @click="cancelEditNetwork" />
                </div>

                <div class="et-action-grid et-group mb-3" role="toolbar">
                    <v-btn
                        v-for="item in configActions"
                        :key="item.key"
                        variant="text"
                        class="et-action-cell"
                        :color="item.primary ? 'primary' : undefined"
                        :aria-label="t(item.labelKey)"
                        :disabled="item.disabled"
                        @click="item.run"
                    >
                        <v-icon size="22">{{ item.icon }}</v-icon>
                        <span>{{ t(item.labelKey) }}</span>
                    </v-btn>
                </div>

                <Config
                    :cur-network="currentNetworkConfig"
                    :config-invalid="!currentNetworkConfig"
                    :loading="configLoading"
                    @run-network="saveAndRunNewNetwork"
                />
            </div>

            <!-- Mode B: Active Network Dashboard & Tabs (刷新不再降低透明度/屏蔽点击) -->
            <div
                v-else-if="needShowNetworkStatus"
                class="network-status-container"
            >
                <!-- Status component (handles Home with prominent start/stop, Devices, etc.) -->
                <Status
                    v-if="curNetworkInfo && curNetworkInfo.error_msg === ''"
                    :cur-network-inst="curNetworkInfo"
                    :api="api"
                    :active-tab="mobileTab"
                    :network-running="connectedOverride"
                    :hide-power-toggle="hidePowerToggle"
                    @start-network="startNetwork"
                    @stop-network="stopNetwork"
                    @toggle-network="toggleCurrentNetwork"
                    class="mb-4"
                />
                <v-alert v-else-if="curNetworkInfo?.error_msg" type="error" variant="tonal" rounded="xl" class="mb-4">
                    {{ curNetworkInfo.error_msg }}
                </v-alert>
                <!-- 运行态详情首刷未回:贴合 Status 布局的骨架(hero + 两个分组) -->
                <div v-else role="progressbar" aria-hidden="true" class="et-skeleton-stack pt-4">
                    <v-skeleton-loader class="et-skeleton" type="article" boilerplate />
                    <v-skeleton-loader class="et-skeleton" type="list-item-two-line@3" boilerplate />
                </div>

                <!-- Activity Tab View (when mobileTab === 'activity') -->
                <div v-if="mobileTab === 'activity'" class="activity-tab-content">
                    <div class="ios-section">
                        <div class="ios-section-header">{{ t('event_log') }}</div>
                        <div v-if="activityEvents.length" class="ios-group pa-3">
                            <v-timeline side="end" density="compact">
                                <v-timeline-item
                                    v-for="item in activityEvents"
                                    :key="eventTimelineKey(item)"
                                    dot-color="primary"
                                    size="small"
                                >
                                    <small class="text-caption text-medium-emphasis d-block mb-1">{{ useTimeAgo(Date.parse(item.time)) }}</small>
                                    <HumanEvent :event="item.event" />
                                </v-timeline-item>
                            </v-timeline>
                        </div>
                        <div v-else class="et-group et-empty">
                            <div class="et-empty__icon"><v-icon size="26" color="primary">mdi-history</v-icon></div>
                            <div class="et-empty__title">{{ t('no_events') }}</div>
                            <div class="et-empty__hint">{{ t('web.device_management.rm_activity_empty_hint', 'Network events appear here as peers join and routes change') }}</div>
                        </div>
                    </div>
                </div>

                <!-- Config Tab View (when mobileTab === 'config' or when disabled in test) -->
                <div v-if="mobileTab === 'config'" class="config-tab-content">
                    <div class="et-action-grid et-group mb-3" role="toolbar">
                        <v-btn
                            v-for="item in configActions"
                            :key="item.key"
                            variant="text"
                            class="et-action-cell"
                            :color="item.primary ? 'primary' : undefined"
                            :aria-label="t(item.labelKey)"
                            :disabled="item.disabled"
                            @click="item.run"
                        >
                            <v-icon size="22">{{ item.icon }}</v-icon>
                            <span>{{ t(item.labelKey) }}</span>
                        </v-btn>
                    </div>
                    <Config
                        :cur-network="currentNetworkConfig"
                        :config-invalid="!currentNetworkConfig"
                        :loading="configLoading"
                        @run-network="saveAndRunNewNetwork"
                    />
                </div>
            </div>

            <!-- 实例列表首刷未回:整块内容骨架,避免空白闪现 -->
            <div v-else-if="!initialLoadDone" role="progressbar" aria-hidden="true" class="et-skeleton-stack pt-2">
                <v-skeleton-loader class="et-skeleton" type="article" boilerplate />
                <v-skeleton-loader class="et-skeleton" type="list-item-two-line@3" boilerplate />
            </div>

            <!-- Mode C: Empty State (No network configured) -->
            <div v-else class="empty-state et-empty d-flex flex-column align-center justify-center py-12">
                <div class="et-empty__icon mb-4">
                    <v-icon size="36" color="primary">mdi-shield-plus-outline</v-icon>
                </div>
                <div class="text-h6 text-center font-weight-bold mb-2">
                    {{ t('web.device_management.no_network_selected') }}
                </div>
                <p class="text-body-2 text-center text-medium-emphasis mb-6 rm-empty-hint">
                    {{ t('web.device_management.select_existing_network_or_create_new') }}
                </p>
                <div class="d-flex flex-column ga-2 w-100" style="max-width: 240px;">
                    <v-btn color="primary" :prepend-icon="'mdi-plus'" variant="flat" size="large" rounded="pill" @click="newNetwork">
                        {{ t('web.device_management.create_network') }}
                    </v-btn>
                    <v-btn variant="tonal" size="large" rounded="pill" :prepend-icon="'mdi-upload'" @click="importConfig">
                        {{ t('web.network.import') }}
                    </v-btn>
                </div>
            </div>
        </div>

        <!-- ================= 3. Fixed iOS Bottom Tab Bar ================= -->
        <nav
            v-if="needShowNetworkStatus"
            class="et-tab-bar d-flex align-center justify-space-around"
            role="tablist"
        >
            <button
                type="button"
                class="et-tab-item"
                :class="{ 'tab-active': mobileTab === 'home' }"
                role="tab"
                :aria-selected="mobileTab === 'home'"
                @click="mobileTab = 'home'"
            >
                <v-icon size="22">{{ mobileTab === 'home' ? 'mdi-shield' : 'mdi-shield-outline' }}</v-icon>
                <span>{{ t('tabs.home') }}</span>
            </button>

            <button
                type="button"
                class="et-tab-item"
                :class="{ 'tab-active': mobileTab === 'devices' }"
                role="tab"
                :aria-selected="mobileTab === 'devices'"
                @click="mobileTab = 'devices'"
            >
                <v-badge v-if="peerCount > 0" :content="peerCount" color="primary" inline>
                    <v-icon size="22">mdi-devices</v-icon>
                </v-badge>
                <v-icon v-else size="22">mdi-devices</v-icon>
                <span>{{ t('tabs.devices') }}</span>
            </button>

            <button
                type="button"
                class="et-tab-item"
                :class="{ 'tab-active': mobileTab === 'config' }"
                role="tab"
                :aria-selected="mobileTab === 'config'"
                @click="mobileTab = 'config'"
            >
                <v-icon size="22">{{ mobileTab === 'config' ? 'mdi-cog' : 'mdi-cog-outline' }}</v-icon>
                <span>{{ t('tabs.config') }}</span>
            </button>

            <button
                type="button"
                class="et-tab-item"
                :class="{ 'tab-active': mobileTab === 'activity' }"
                role="tab"
                :aria-selected="mobileTab === 'activity'"
                @click="mobileTab = 'activity'"
            >
                <v-icon size="22">{{ mobileTab === 'activity' ? 'mdi-pulse' : 'mdi-chart-line' }}</v-icon>
                <span>{{ t('tabs.activity') }}</span>
            </button>
        </nav>

        <!-- TOML Edit Dialog -->
        <ConfigEditDialog
            v-model:visible="showConfigEditDialog"
            :cur-network="currentNetworkConfig"
            :generate-config="generateConfig"
            :save-config="syncTomlConfig"
        />

        <!-- Confirm dialog -->
        <v-dialog v-model="confirmDialog" max-width="420px" transition="dialog-bottom-transition">
            <v-card :title="confirmHeader" rounded="xl" class="ios-dialog-sheet">
                <v-card-text>{{ confirmMessage }}</v-card-text>
                <v-card-actions>
                    <v-spacer />
                    <v-btn variant="text" rounded="pill" color="secondary" @click="confirmDialog = false">{{ t('web.common.cancel') }}</v-btn>
                    <v-btn color="error" variant="flat" rounded="pill" @click="confirmDialog = false; confirmAction()">{{ t('web.common.confirm') }}</v-btn>
                </v-card-actions>
            </v-card>
        </v-dialog>

        <!-- Snackbar Toast -->
        <v-snackbar v-model="toast" :color="toastColor" timeout="2500" location="top" rounded="pill">
            {{ toastMessage }}
        </v-snackbar>
    </div>
</template>

<style scoped>
.device-management {
    height: 100%;
    display: flex;
    flex-direction: column;
    padding: 0 var(--et-space-3);
    position: relative;
}

.et-network-chip {
    background-color: var(--et-surface-1);
    border: 1px solid var(--et-border);
    border-radius: var(--et-radius-lg);
    padding: var(--et-space-3);
    min-height: var(--et-row-h);
    cursor: pointer;
}

.et-network-chip:active {
    background-color: var(--et-surface-2);
}

/* 原生 <button> 承载 .et-row 布局时,先剥掉 UA 外观 */
button.et-row {
    width: 100%;
    border: 0;
    background: transparent;
    color: inherit;
    font: inherit;
    text-align: left;
    cursor: pointer;
    appearance: none;
    -webkit-appearance: none;
}

/* ---------- 共享动效 kit:骨架 / 列表进出场 / 按压反馈 / 空态 ---------- */

/* 骨架容器:透出 et-bg 背景,由内层 bone 提供占位条。
 * 双写 .v-skeleton-loader 提升优先级,替代原来的 !important。 */
.et-skeleton.v-skeleton-loader {
    background: transparent;
    width: 100%;
}

.et-skeleton-stack {
    display: flex;
    flex-direction: column;
    gap: var(--et-gap-stack);
    padding: var(--et-space-1) var(--et-space-1) var(--et-space-4);
}

.et-skeleton--inline {
    padding: var(--et-space-1) 0;
}

/* 静默刷新指示:顶部 2px 细线。pointer-events:none,绝不拦截点击,也不降低内容透明度。 */
.et-refresh-bar {
    position: absolute;
    top: 0;
    left: var(--et-space-3);
    right: var(--et-space-3);
    height: 2px;
    border-radius: var(--et-radius-pill);
    background: var(--et-accent);
    opacity: 0;
    overflow: hidden;
    pointer-events: none;
    z-index: var(--et-z-sticky);
    transition: opacity var(--et-dur-fast) var(--et-ease-standard);
}

/* 延迟 180ms 出现:极快的轮询不会造成闪烁 */
.et-refresh-bar.is-active {
    opacity: 0.9;
    transition-delay: 180ms;
}

.et-refresh-bar.is-active::after {
    content: '';
    position: absolute;
    inset: 0;
    background: linear-gradient(90deg, transparent, color-mix(in srgb, var(--et-accent) 55%, transparent), transparent);
    transform: translateX(-100%);
}

@keyframes et-refresh-sweep {
    from { transform: translateX(-100%); }
    to { transform: translateX(100%); }
}

/* 底部面板抓条:原生 button,触摸区域 >=48px,视觉仍是一根小药丸 */
.et-sheet-grabber-hit {
    min-height: var(--et-touch);
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0 var(--et-space-4);
    border: 0;
    background: transparent;
    cursor: pointer;
    appearance: none;
    -webkit-appearance: none;
}

.et-sheet-grabber-hit :deep(.sheet-grabber) {
    margin: 0;
}

/* 底部动作面板:整行 >=48px,符合移动端最小触摸目标。
 * 双写 .v-list-item 提升优先级,替代原来的 !important。 */
.et-sheet-action.v-list-item {
    min-height: var(--et-touch);
}

/* 空态 */
.et-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    padding: var(--et-space-8) var(--et-space-5);
    color: var(--et-text-2);
}

.et-empty__icon {
    width: 64px;
    height: 64px;
    border-radius: var(--et-radius-lg);
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--et-accent-quiet);
    margin-bottom: var(--et-space-3);
    flex-shrink: 0;
}

.et-empty__title {
    font-size: var(--et-font-body);
    font-weight: var(--et-weight-semibold);
    color: var(--et-text);
}

.et-empty__hint {
    font-size: var(--et-font-body-sm);
    line-height: var(--et-leading-normal);
    max-width: 18rem;
    margin-top: var(--et-space-1);
}

@media (prefers-reduced-motion: no-preference) {
    .et-network-chip,
    .et-press-row {
        transition:
            transform var(--et-dur-fast) var(--et-ease-standard),
            background-color var(--et-dur-fast) var(--et-ease-standard),
            opacity var(--et-dur-fast) var(--et-ease-standard);
    }

    .et-network-chip:active,
    .et-press-row:active {
        transform: scale(0.985);
    }

    .et-refresh-bar.is-active::after {
        animation: et-refresh-sweep 900ms linear infinite;
    }

    /* 列表进出场:12px 位移 + opacity */
    .et-list-fade-enter-active,
    .et-list-fade-leave-active {
        transition:
            opacity var(--et-dur-base) var(--et-ease-standard),
            transform var(--et-dur-base) var(--et-ease-standard);
    }

    .et-list-fade-enter-from,
    .et-list-fade-leave-to {
        opacity: 0;
        transform: translateY(12px);
    }

    .et-list-fade-leave-active {
        position: absolute;
        width: 100%;
    }

    .et-list-fade-move {
        transition: transform var(--et-dur-base) var(--et-ease-standard);
    }

    .et-list-wrap {
        position: relative;
        display: block;
    }

    /* bone 微光,贴合主题色而不是纯灰 */
    .et-skeleton :deep(.v-skeleton-loader__bone::after) {
        background: linear-gradient(
            90deg,
            transparent,
            color-mix(in srgb, var(--et-accent) 10%, transparent),
            transparent
        );
    }
}

.hero-net-name {
    font-size: var(--et-font-body);
    font-weight: var(--et-weight-semibold);
    letter-spacing: -0.02em;
}

.rm-empty-hint {
    max-width: 20rem;
    line-height: var(--et-leading-normal);
}

.network-content {
    flex: 1;
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
    padding: var(--et-space-1) 0 calc(var(--et-tab-height) + var(--et-safe-bottom) + var(--et-space-3));
}

.has-tab-bar :deep(.et-sticky-run) {
    bottom: calc(var(--et-tab-height) + var(--et-safe-bottom));
    padding-bottom: var(--et-space-3);
}

/* 双写 .v-list 提升优先级,替代原来的 !important */
.et-menu-list.v-list {
    background-color: var(--et-surface-1);
}

.truncate {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.text-mono {
  font-family: var(--et-font-data);
}

@media (min-width: 600px) {
    .network-content {
        padding-bottom: var(--et-space-4);
    }
    .has-tab-bar :deep(.et-sticky-run) {
        bottom: var(--et-space-4);
        padding-bottom: 0;
    }
}
</style>
