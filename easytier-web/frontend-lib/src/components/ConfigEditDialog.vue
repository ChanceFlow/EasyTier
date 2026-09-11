<script setup lang="ts">
import { onMounted, ref, watch, type PropType } from 'vue';
import { useDisplay } from 'vuetify';
import { NetworkConfig } from '../types/network';
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
// 移动端(小屏)弹窗全屏展示
const { smAndDown: mobileUI } = useDisplay()

// 触觉反馈:组件内局部实现,不动共享 utils(避免与其他 agent 冲突)
function vibrate(ms = 8) {
    try {
        navigator.vibrate?.(ms);
    } catch {
        /* ignore */
    }
}

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
const tomlConfig = ref<string>('')
const tomlConfigRows = ref<number>(1)
const errorMessage = ref<string>('')
// 生成中的状态:生成完成前禁止保存,避免写入空配置
const generating = ref(false)

async function generateConfigText(config: NetworkConfig) {
    generating.value = true
    errorMessage.value = ''
    tomlConfig.value = ''
    try {
        tomlConfig.value = await props.generateConfig(config)
    } catch (e) {
        errorMessage.value = t('config_file_generate_failed', 'Failed to generate config') + ': ' + (e instanceof Error ? e.message : String(e))
    } finally {
        generating.value = false
    }
}

watch([visible, curNetwork], async ([newVisible, newCurNetwork]) => {
    if (!newVisible) {
        tomlConfig.value = ''
        return;
    }
    if (!newCurNetwork) {
        tomlConfig.value = '';
        return;
    }
    await generateConfigText(newCurNetwork);
})
onMounted(async () => {
    if (!visible.value) {
        return;
    }
    if (!curNetwork.value) {
        tomlConfig.value = '';
        return;
    }
    await generateConfigText(curNetwork.value);
});

const handleConfigSave = async () => {
    if (props.readonly) return;
    if (generating.value || !tomlConfig.value) return;
    try {
        await props.saveConfig(tomlConfig.value);
        visible.value = false;
    } catch (e) {
        errorMessage.value = t('config_file_save_failed', 'Failed to save config') + ': ' + (e instanceof Error ? e.message : String(e));
    }
};

watch(tomlConfig, (newValue) => {
    tomlConfigRows.value = newValue.split('\n').length;
    errorMessage.value = '';
});

</script>
<template>
    <v-dialog v-model="visible" max-width="70vw" :fullscreen="mobileUI" transition="dialog-bottom-transition">
        <v-card :title="t('config_file')" rounded="xl" class="et-dialog-sheet">
            <v-card-text>
                <Transition name="et-error-fade">
                    <pre v-if="errorMessage" class="mb-2 config-error" role="alert">
                        {{ errorMessage }}
                    </pre>
                </Transition>
                <div v-if="generating" class="d-flex align-center ga-2 mb-2 text-caption text-medium-emphasis" role="status">
                    <v-progress-circular indeterminate size="16" width="2" />
                    <span>{{ t('config_file_generating', 'Generating…') }}</span>
                </div>
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
                <v-btn v-if="!props.readonly" variant="flat" color="primary" rounded="pill" :loading="generating" :disabled="generating || !tomlConfig" @click="handleConfigSave(); vibrate(10)">{{ t('save') }}</v-btn>
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
    font-variant-numeric: tabular-nums;
}

@media (prefers-reduced-motion: no-preference) {
    .et-error-fade-enter-active,
    .et-error-fade-leave-active {
        transition: opacity 180ms ease-out, transform 180ms ease-out;
    }

    .et-error-fade-enter-from,
    .et-error-fade-leave-to {
        opacity: 0;
        transform: translateY(12px);
    }
}
</style>
