<script setup lang="ts">
import { NetworkTypes, Utils, Api, RemoteManagement } from 'easytier-frontend-lib';
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ApiClient from '../modules/api';


const props = defineProps<{
    api: ApiClient;
    deviceList: Array<Utils.DeviceInfo> | undefined;
}>();

const emits = defineEmits(['update']);

const route = useRoute();
const router = useRouter();

const deviceId = computed<string>(() => {
    return route.params.deviceId as string;
});

const instanceId = computed<string>(() => {
    return route.params.instanceId as string;
});

const deviceInfo = computed<Utils.DeviceInfo | undefined | null>(() => {
    return deviceId.value ? props.deviceList?.find((device) => device.machine_id === deviceId.value) : null;
});

const selectedInstanceId = computed({
    get() {
        return instanceId.value;
    },
    set(value: string) {
        console.log("selectedInstanceId", value);
        router.push({ name: 'deviceManagement', params: { deviceId: deviceId.value, instanceId: value } });
    }
});

const remoteClient = computed<Api.RemoteClient>(() => props.api.get_remote_client(deviceId.value));

const newConfigGenerator = () => {
    const config = NetworkTypes.DEFAULT_NETWORK_CONFIG();
    config.hostname = deviceInfo.value?.hostname;
    return config;
}

</script>

<template>
    <RemoteManagement :api="remoteClient" v-model:instance-id="selectedInstanceId"
        :new-config-generator="newConfigGenerator" />
</template>

<style scoped>
.network-content {
    flex: 1;
    overflow-y: auto;
}

/* 网络选择相关样式 */
.network-label {
    white-space: nowrap;
}

:deep(.network-select-container) {
    max-width: 100%;
}
</style>
