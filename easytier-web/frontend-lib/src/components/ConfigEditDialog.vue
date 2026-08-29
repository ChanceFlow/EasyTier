<script setup lang="ts">
import { onMounted, ref, watch, type PropType } from 'vue';
import { useDisplay } from 'vuetify';
import { NetworkConfig } from '../types/network';
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
// 移动端(小屏)弹窗全屏展示
const { smAndDown: mobileUI } = useDisplay()

const props = defineProps({
    readonly: {
        type: Boolean,
        default: false,
    },
    generateConfig: {
        type: Function as PropType<(config: NetworkConfig) => Promise<string>>,
        required: true,
    },
    saveConfig: {
        type: Function as PropType<(config: string) => Promise<void>>,
        required: true,
    },
})

const curNetwork = defineModel('curNetwork', {
    type: Object as () => NetworkConfig | undefined,
    required: false,
})

const visible = defineModel('visible', {
    type: Boolean,
    default: false,
})
watch([visible, curNetwork], async ([newVisible, newCurNetwork]) => {
    if (!newVisible) {
        tomlConfig.value = '';
        return;
    }
    if (!newCurNetwork) {
        tomlConfig.value = '';
        return;
    }
    const config = newCurNetwork;
    try {
        errorMessage.value = '';
        tomlConfig.value = await props.generateConfig(config);
    } catch (e) {
        errorMessage.value = 'Failed to generate config: ' + (e instanceof Error ? e.message : String(e));
        tomlConfig.value = '';
    }
})
onMounted(async () => {
    if (!visible.value) {
        return;
    }
    if (!curNetwork.value) {
        tomlConfig.value = '';
        return;
    }
    const config = curNetwork.value;
    try {
        tomlConfig.value = await props.generateConfig(config);
        errorMessage.value = '';
    } catch (e) {
        errorMessage.value = 'Failed to generate config: ' + (e instanceof Error ? e.message : String(e));
        tomlConfig.value = '';
    }
});

const handleConfigSave = async () => {
    if (props.readonly) return;
    try {
        await props.saveConfig(tomlConfig.value);
        visible.value = false;
    } catch (e) {
        errorMessage.value = 'Failed to save config: ' + (e instanceof Error ? e.message : String(e));
    }
};

const tomlConfig = ref<string>('')
const tomlConfigRows = ref<number>(1);
const errorMessage = ref<string>('');

watch(tomlConfig, (newValue) => {
    tomlConfigRows.value = newValue.split('\n').length;
    errorMessage.value = '';
});

</script>
<template>
    <v-dialog v-model="visible" max-width="70vw" :fullscreen="mobileUI">
        <v-card :title="t('config_file')" rounded="xl" class="et-dialog-sheet">
            <v-card-text>
                <pre v-if="errorMessage" class="mb-2 config-error">
                    {{ errorMessage }}
                </pre>
                <v-textarea
                    v-model="tomlConfig"
                    :rows="tomlConfigRows"
                    :readonly="props.readonly"
                    auto-grow
                    spellcheck="false"
                    class="text-mono w-100 config-textarea"
                    variant="outlined"
                />
            </v-card-text>
            <v-divider />
            <v-card-actions class="justify-end">
                <v-btn v-if="!props.readonly" variant="flat" color="primary" rounded="pill" @click="handleConfigSave">{{ t('save') }}</v-btn>
                <v-btn variant="text" rounded="pill" @click="visible = false">{{ t('close') }}</v-btn>
            </v-card-actions>
        </v-card>
    </v-dialog>
</template>

<style scoped>
.config-error {
    background: var(--v-theme-errorContainer);
    color: var(--v-theme-onErrorContainer);
    border-radius: 8px;
    padding: 8px;
    font-size: 0.85rem;
    max-height: 10rem;
    overflow: auto;
    white-space: pre-wrap;
}
.config-textarea {
    max-height: 60vh;
}
.config-textarea :deep(textarea) {
    overflow-y: auto !important;
    font-family: var(--font-mono) !important;
}
</style>
