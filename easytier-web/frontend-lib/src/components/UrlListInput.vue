<script setup lang="ts">
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { v4 as uuidv4 } from 'uuid'
import UrlInput from './UrlInput.vue'

const props = defineProps<{
    protos: { [proto: string]: number }
    addLabel: string
    placeholder?: string
    defaultUrl?: string
    /** 外部 label 的 for 目标:绑定到第一条 URL 的主机名输入框 */
    id?: string
}>()

const { t } = useI18n()

const list = defineModel<string[]>({ required: true })

// 行与内容一一对应但不绑下标:增删一行时其它行不会复用错 DOM。
// 每个位置一个稳定 uuid,和 list 同步增删(外部替换数组时按长度补齐/裁剪)。
const rowKeys = ref<string[]>([])

function rowKey(index: number): string {
    // 渲染期兜底:外部直接替换数组时 watcher 尚未 flush,先补一个 key。
    while (rowKeys.value.length <= index) {
        rowKeys.value.push(uuidv4())
    }
    return rowKeys.value[index]
}

watch(
    () => list.value.length,
    (length) => {
        if (rowKeys.value.length > length) {
            rowKeys.value.splice(length)
        }
        while (rowKeys.value.length < length) {
            rowKeys.value.push(uuidv4())
        }
    },
    { immediate: true },
)

const itemId = (index: number): string | undefined => {
    if (!props.id) return undefined
    return index === 0 ? props.id : `${props.id}-${index}`
}

const addUrl = () => {
    list.value.push(props.defaultUrl || 'tcp://0.0.0.0:11010')
    // 立即对齐 key,不依赖异步 watcher,避免新行短暂复用上一行的 DOM。
    rowKey(list.value.length - 1)
}

const removeUrl = (index: number) => {
    list.value.splice(index, 1)
    // 同步移除对应 key,后续行不会继承被删行的身份。
    rowKeys.value.splice(index, 1)
}
</script>

<template>
    <div class="d-flex flex-column ga-2 w-100">
        <div v-for="(_, index) in list" :key="rowKey(index)" class="d-flex align-center w-100">
            <UrlInput v-model="list[index]" :protos="protos" :placeholder="placeholder" :id="itemId(index)">
                <template #actions>
                    <v-btn
                        icon="mdi-delete"
                        variant="text"
                        color="error"
                        size="small"
                        rounded
                        :aria-label="t('web.common.delete')"
                        @click="removeUrl(index)"
                    />
                </template>
            </UrlInput>
        </div>
        <button type="button" class="url-list-add d-flex align-center justify-center w-100" @click="addUrl">
            <v-icon size="small" aria-hidden="true">mdi-plus</v-icon>
            <span class="text-body-2">{{ addLabel }}</span>
        </button>
    </div>
</template>

<style scoped>
.url-list-add {
    appearance: none;
    border: 1.5px dashed var(--et-control-border);
    border-radius: var(--et-radius-md);
    background: transparent;
    color: var(--et-text-2);
    cursor: pointer;
    min-height: var(--et-touch);
    gap: var(--et-space-2);
    padding: var(--et-space-2) var(--et-space-3);
    font: inherit;
    transition:
        background-color var(--et-dur-fast) var(--et-ease-hover),
        border-color var(--et-dur-fast) var(--et-ease-hover),
        color var(--et-dur-fast) var(--et-ease-hover);
}
.url-list-add:hover {
    border-color: var(--et-accent);
    color: var(--et-text);
}
.url-list-add:focus-visible {
    outline: 2px solid var(--et-focus);
    outline-offset: 2px;
}
.url-list-add:active {
    border-color: var(--et-accent);
    background: var(--et-accent-quiet);
}
</style>
