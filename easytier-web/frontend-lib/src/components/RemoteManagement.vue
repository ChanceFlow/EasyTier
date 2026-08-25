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

const props = defineProps<{
    api: Api.RemoteClient;
    newConfigGenerator?: () => NetworkTypes.NetworkConfig;
    pauseAutoRefresh?: boolean;
}>();

const instanceId = defineModel('instanceId', {
    type: String as () => string | undefined,
    required: false,
})

const emits = defineEmits(['update']);

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

const showConfigEditDialog = ref(false);
const isEditingNetwork = ref(false);
const currentNetworkConfig = ref<NetworkTypes.NetworkConfig | undefined>(undefined);

const listInstanceIdResponse = ref<Api.ListNetworkInstanceIdResponse | undefined>(undefined);

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
    if (newVal?.uuid !== oldVal?.uuid && (networkIsDisabled.value || isEditingNetwork.value)) {
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

// ---- 移动端网络切换 Bottom Sheet ----
const networkSheetOpen = ref(false);

const heroIsRunning = computed(() => {
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

    let ret = await props.api.get_network_config(selectedInstanceId.value!.uuid);
    currentNetworkConfig.value = ret;
}

const stopNetwork = async () => {
    if (!selectedInstanceId.value) {
        return;
    }

    await props.api.update_network_instance_state(selectedInstanceId.value.uuid, true);
    await loadNetworkInstanceIds();
}

const startNetwork = async () => {
    if (!selectedInstanceId.value) {
        return;
    }
    await props.api.update_network_instance_state(selectedInstanceId.value.uuid, false);
    await loadNetworkInstanceIds();
}

const toggleCurrentNetwork = async () => {
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
    if (!instanceId.value && listInstanceIdResponse.value?.running_inst_ids?.length) {
        instanceId.value = Utils.UuidToStr(listInstanceIdResponse.value.running_inst_ids[0]);
    }
}

const loadCurrentNetworkInfo = async () => {
    if (!selectedInstanceId.value) {
        curNetworkInfo.value = null;
        return;
    }

    try {
        const info = await props.api.get_network_info(selectedInstanceId.value.uuid);
        curNetworkInfo.value = {
            instance_id: selectedInstanceId.value.uuid,
            running: isRunning(selectedInstanceId.value.uuid),
            error_msg: "",
            detail: info as any,
        };
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
        const parsed = await props.api.parse_config(tomlConfig);
        currentNetworkConfig.value = ((parsed as any)?.config ? (parsed as any).config : parsed) as any;
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
        a.click();
        URL.revokeObjectURL(url);
    } catch (e) {
        console.error('Export failed', e);
        showToast(String(e), 'error');
    }
}

const importConfig = () => {
    configFile.value?.click();
}

const handleFileUpload = async (e: Event) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;
    const text = await file.text();
    await syncTomlConfig(text);
}

// 菜单引用和菜单项
const actionMenuOpen = ref(false)
const menuX = ref(0)
const menuY = ref(0)

function openActionMenu(e: Event) {
    menuX.value = (e as MouseEvent).clientX
    menuY.value = (e as MouseEvent).clientY
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
    try {
        await Promise.all([loadNetworkInstanceIds(), loadCurrentNetworkInfo()]);
    } catch (e) {
        console.debug(e);
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

</script>

<template>
    <div class="device-management">
        <input type="file" @change="handleFileUpload" class="d-none" accept="application/toml" ref="configFile" />

        <!-- ================= 1. Top Network Switcher Profile Card ================= -->
        <div class="ios-profile-card d-flex align-center justify-space-between mb-3 mt-2" @click="openNetworkSheet">
            <div class="d-flex align-center ga-3 min-w-0">
                <div class="ios-squircle pressable" :style="{ background: heroIsRunning ? 'var(--ios-green)' : 'var(--ios-surface-secondary)' }" @click.stop="toggleCurrentNetwork">
                    <v-icon size="18" :color="heroIsRunning ? 'white' : 'var(--ios-text-secondary)'">
                        {{ heroIsRunning ? 'mdi-shield-check' : 'mdi-power' }}
                    </v-icon>
                </div>
                <div class="min-w-0">
                    <div class="d-flex align-center ga-2">
                        <span class="hero-net-name truncate">{{ heroNetworkName }}</span>
                        <v-chip :color="heroIsRunning ? 'success' : 'default'" size="x-small" variant="tonal" class="rounded-pill font-weight-bold">
                            {{ heroIsRunning ? 'Active' : 'Stopped' }}
                        </v-chip>
                    </div>
                    <div class="text-caption text-mono text-medium-emphasis truncate">{{ selectedInstanceId?.uuid ?? t('web.device_management.select_network') }}</div>
                </div>
            </div>

            <div class="d-flex align-center ga-1 flex-shrink-0">
                <template v-if="isEditingNetwork">
                    <v-btn icon="mdi-close" size="small" variant="text" :aria-label="t('web.device_management.cancel_edit')" @click.stop="cancelEditNetwork" />
                </template>
                <template v-else>
                    <v-btn
                        :color="heroIsRunning ? 'error' : 'success'"
                        variant="tonal"
                        size="x-small"
                        rounded="pill"
                        class="font-weight-bold px-3 me-1"
                        @click.stop="toggleCurrentNetwork"
                    >
                        {{ heroIsRunning ? 'Stop' : 'Start' }}
                    </v-btn>
                    <v-btn v-if="selectedInstanceId" icon="mdi-dots-vertical" size="small" variant="text" :aria-label="t('web.device_management.more_actions')" @click.stop="openActionMenu" />
                    <v-icon size="20" color="medium-emphasis">mdi-chevron-down</v-icon>
                </template>
            </div>
        </div>

        <!-- Network Switcher Bottom Sheet (iOS Action Sheet) -->
        <v-bottom-sheet v-model="networkSheetOpen" scrollable>
            <v-card rounded="t-xl" class="ios-network-sheet">
                <div class="sheet-grabber" @click="networkSheetOpen = false" />
                <v-card-title class="d-flex align-center justify-space-between pt-1 pb-2">
                    <span class="text-subtitle-1 font-weight-bold">{{ t('web.device_management.network') }}</span>
                    <v-btn color="primary" variant="flat" size="small" rounded="pill" :prepend-icon="'mdi-plus'" @click="sheetCreateNew">
                        {{ t('web.device_management.create_new') }}
                    </v-btn>
                </v-card-title>
                <v-card-text class="pa-2">
                    <div class="ios-group mb-2">
                        <div
                            v-for="item in instanceList"
                            :key="item.uuid"
                            class="ios-row ios-row-pressable"
                            @click="sheetSelectNetwork(item)"
                        >
                            <div class="d-flex align-center ga-3 min-w-0">
                                <div class="ios-squircle" :style="{ background: isRunning(item.uuid) ? 'var(--ios-green)' : 'var(--ios-surface-secondary)' }">
                                    <v-icon size="18" :color="isRunning(item.uuid) ? 'white' : 'var(--ios-text-secondary)'">
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
                        </div>
                    </div>
                </v-card-text>
            </v-card>
        </v-bottom-sheet>

        <!-- More actions menu -->
        <v-menu v-model="actionMenuOpen" :position-x="menuX" :position-y="menuY" location="bottom end">
            <v-list density="comfortable" min-width="180" rounded="xl" class="ios-menu-list">
                <v-list-item v-if="currentNetworkControl.editable.value" @click="runActionMenu('edit')">
                    <v-list-item-title>{{ t('web.device_management.edit_network') }}</v-list-item-title>
                    <template #prepend><v-icon size="20">mdi-pencil</v-icon></template>
                </v-list-item>
                <v-list-item @click="runActionMenu('export')">
                    <v-list-item-title>{{ t('web.device_management.export_config') }}</v-list-item-title>
                    <template #prepend><v-icon size="20">mdi-download</v-icon></template>
                </v-list-item>
                <v-list-item v-if="currentNetworkControl.deletable.value" @click="runActionMenu('delete')">
                    <v-list-item-title class="text-error">{{ t('web.device_management.delete_network') }}</v-list-item-title>
                    <template #prepend><v-icon color="error" size="20">mdi-trash-can-outline</v-icon></template>
                </v-list-item>
            </v-list>
        </v-menu>

        <!-- ================= 2. Main Content Area ================= -->
        <div class="network-content">
            <!-- Mode A: Network Creation Form (when user clicked Create/Edit) -->
            <div v-if="isEditingNetwork" class="network-creation-container">
                <div class="d-flex align-center justify-space-between mb-3">
                    <div class="d-flex align-center ga-2">
                        <v-icon color="primary" size="22">mdi-tune-variant</v-icon>
                        <h2 class="text-subtitle-1 font-weight-bold">{{ t('web.device_management.edit_network') }}</h2>
                    </div>
                    <v-btn icon="mdi-close" size="small" variant="text" @click="cancelEditNetwork" />
                </div>

                <div class="rm-toolbar d-flex flex-wrap ga-2 justify-start mb-3">
                    <v-btn variant="tonal" size="small" rounded="pill" :prepend-icon="'mdi-file-edit-outline'" @click="showConfigEditDialog = true">
                        {{ t('web.device_management.edit_as_file') }}
                    </v-btn>
                    <v-btn variant="tonal" size="small" rounded="pill" :prepend-icon="'mdi-upload'" @click="importConfig">
                        {{ t('web.device_management.import_config') }}
                    </v-btn>
                    <v-btn color="success" size="small" variant="tonal" rounded="pill" :prepend-icon="'mdi-content-save'" :disabled="!currentNetworkConfig" @click="saveNetworkConfig">
                        {{ t('web.device_management.save_config') }}
                    </v-btn>
                </div>

                <Config
                    :cur-network="currentNetworkConfig"
                    :config-invalid="!currentNetworkConfig"
                    @run-network="saveAndRunNewNetwork"
                />
            </div>

            <!-- Mode B: Active Network Dashboard & Tabs -->
            <div v-else-if="needShowNetworkStatus" class="network-status-container">
                <!-- Status component (handles Home with prominent start/stop, Devices, etc.) -->
                <Status
                    v-if="curNetworkInfo && curNetworkInfo.error_msg === ''"
                    :cur-network-inst="curNetworkInfo"
                    :api="api"
                    :active-tab="mobileTab"
                    @start-network="startNetwork"
                    @stop-network="stopNetwork"
                    @toggle-network="toggleCurrentNetwork"
                    class="mb-4"
                />
                <v-alert v-else-if="curNetworkInfo?.error_msg" type="error" variant="tonal" rounded="xl" class="mb-4">
                    {{ curNetworkInfo.error_msg }}
                </v-alert>
                <v-alert v-else type="info" variant="tonal" rounded="xl" class="mb-4">
                    {{ t('web.device_management.loading_network_status') }}
                </v-alert>

                <!-- Activity Tab View (when mobileTab === 'activity') -->
                <div v-if="mobileTab === 'activity'" class="activity-tab-content">
                    <div class="ios-section">
                        <div class="ios-section-header">{{ t('event_log') }}</div>
                        <div v-if="activityEvents.length" class="ios-group pa-3">
                            <v-timeline side="end" density="compact">
                                <v-timeline-item
                                    v-for="(item, i) in activityEvents"
                                    :key="i"
                                    dot-color="primary"
                                    size="small"
                                >
                                    <small class="text-caption text-medium-emphasis d-block mb-1">{{ useTimeAgo(Date.parse(item.time)) }}</small>
                                    <HumanEvent :event="item.event" />
                                </v-timeline-item>
                            </v-timeline>
                        </div>
                        <div v-else class="ios-group text-center py-10 text-medium-emphasis">
                            <v-icon size="40" class="mb-2">mdi-history</v-icon>
                            <div>No events recorded yet</div>
                        </div>
                    </div>
                </div>

                <!-- Config Tab View (when mobileTab === 'config' or when disabled in test) -->
                <div v-if="mobileTab === 'config' || networkIsDisabled" class="config-tab-content">
                    <div class="rm-toolbar d-flex flex-wrap ga-2 justify-start mb-3">
                        <v-btn variant="tonal" size="small" rounded="pill" :prepend-icon="'mdi-file-edit-outline'" @click="showConfigEditDialog = true">
                            {{ t('web.device_management.edit_as_file') }}
                        </v-btn>
                        <v-btn variant="tonal" size="small" rounded="pill" :prepend-icon="'mdi-upload'" @click="importConfig">
                            {{ t('web.device_management.import_config') }}
                        </v-btn>
                        <v-btn color="success" size="small" variant="tonal" rounded="pill" :prepend-icon="'mdi-content-save'" :disabled="!currentNetworkConfig" @click="saveNetworkConfig">
                            {{ t('web.device_management.save_config') }}
                        </v-btn>
                    </div>
                    <Config
                        :cur-network="currentNetworkConfig"
                        :config-invalid="!currentNetworkConfig"
                        @run-network="saveAndRunNewNetwork"
                    />
                </div>
            </div>

            <!-- Mode C: Empty State (No network configured) -->
            <div v-else class="empty-state d-flex flex-column align-center justify-center py-12">
                <div class="ios-squircle mb-4" style="width: 72px; height: 72px; border-radius: 20px; background: rgba(10, 132, 255, 0.15);">
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
                        {{ t('web.device_management.import_config') }}
                    </v-btn>
                </div>
            </div>
        </div>

        <!-- ================= 3. Fixed iOS Bottom Tab Bar ================= -->
        <nav
            v-if="needShowNetworkStatus"
            class="ios-tab-bar d-flex align-center justify-space-around"
        >
            <button
                type="button"
                class="ios-tab-item pressable"
                :class="{ 'tab-active': mobileTab === 'home' }"
                @click="mobileTab = 'home'"
            >
                <v-icon size="22">{{ mobileTab === 'home' ? 'mdi-shield' : 'mdi-shield-outline' }}</v-icon>
                <span>Mesh</span>
            </button>

            <button
                type="button"
                class="ios-tab-item pressable"
                :class="{ 'tab-active': mobileTab === 'devices' }"
                @click="mobileTab = 'devices'"
            >
                <v-badge v-if="peerCount > 0" :content="peerCount" color="primary" inline>
                    <v-icon size="22">mdi-devices</v-icon>
                </v-badge>
                <v-icon v-else size="22">mdi-devices</v-icon>
                <span>Devices</span>
            </button>

            <button
                type="button"
                class="ios-tab-item pressable"
                :class="{ 'tab-active': mobileTab === 'config' }"
                @click="mobileTab = 'config'"
            >
                <v-icon size="22">{{ mobileTab === 'config' ? 'mdi-cog' : 'mdi-cog-outline' }}</v-icon>
                <span>Settings</span>
            </button>

            <button
                type="button"
                class="ios-tab-item pressable"
                :class="{ 'tab-active': mobileTab === 'activity' }"
                @click="mobileTab = 'activity'"
            >
                <v-icon size="22">{{ mobileTab === 'activity' ? 'mdi-pulse' : 'mdi-chart-line' }}</v-icon>
                <span>Activity</span>
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
        <v-dialog v-model="confirmDialog" max-width="420px">
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
    padding: 0 0.75rem;
    position: relative;
}

/* Profile Card (iOS style) */
.ios-profile-card {
    background-color: var(--ios-surface);
    border: 1px solid var(--ios-border);
    border-radius: 14px;
    padding: 0.625rem 0.875rem;
    cursor: pointer;
    transition: background-color 0.15s ease;
}

.ios-profile-card:active {
    background-color: var(--ios-surface-secondary);
}

.hero-net-name {
    font-size: 1rem;
    font-weight: var(--fw-bold);
    letter-spacing: -0.01em;
}

.rm-empty-hint {
    max-width: 20rem;
    line-height: 1.5;
}

.network-content {
    flex: 1;
    overflow-y: auto;
    padding: 0.25rem 0 4.5rem;
}

.ios-menu-list {
    background-color: var(--ios-surface) !important;
}

.truncate {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.text-mono {
  font-family: var(--font-mono);
}
</style>
