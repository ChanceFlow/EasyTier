<script setup lang="ts">
import { useI18n } from 'vue-i18n'
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

const itemId = (index: number): string | undefined => {
    if (!props.id) return undefined
    return index === 0 ? props.id : `${props.id}-${index}`
}

const addUrl = () => {
    list.value.push(props.defaultUrl || 'tcp://0.0.0.0:11010')
}

const removeUrl = (index: number) => {
    list.value.splice(index, 1)
}
</script>

<template>
    <div class="d-flex flex-column ga-2 w-100">
        <div v-for="(_, index) in list" :key="index" class="d-flex align-center w-100">
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
        <div
            class="d-flex align-center justify-center w-100 url-list-add"
            role="button"
            tabindex="0"
            @click="addUrl"
            @keydown.enter.prevent="addUrl"
            @keydown.space.prevent="addUrl"
        >
            <v-icon size="small">mdi-plus</v-icon>
            <span class="text-body-2">{{ addLabel }}</span>
        </div>
    </div>
</template>

<style scoped>
.url-list-add {
    border: 1.5px dashed var(--et-border);
    border-radius: 12px;
    cursor: pointer;
    min-height: 44px;
    gap: 8px;
    color: var(--et-text-secondary);
}
.url-list-add:active {
    border-color: var(--et-accent);
    background: var(--et-accent-dim);
}
</style>
