<script setup lang="ts">
import UrlInput from './UrlInput.vue'

const props = defineProps<{
    protos: { [proto: string]: number }
    addLabel: string
    placeholder?: string
    defaultUrl?: string
}>()

const list = defineModel<string[]>({ required: true })

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
            <UrlInput v-model="list[index]" :protos="protos" :placeholder="placeholder">
                <template #actions>
                    <v-btn
                        icon="mdi-delete"
                        variant="text"
                        color="error"
                        size="small"
                        rounded
                        :aria-label="'remove'"
                        @click="removeUrl(index)"
                    />
                </template>
            </UrlInput>
        </div>
        <div
            class="d-flex align-center justify-center w-100 url-list-add"
            style="border: 2px dashed var(--v-theme-outlineVariant); border-radius: 12px; cursor: pointer; min-height: 40px; gap: 8px; color: var(--v-theme-onSurfaceVariant);"
            @click="addUrl"
        >
            <v-icon size="small">mdi-plus</v-icon>
            <span class="text-body-2">{{ addLabel }}</span>
        </div>
    </div>
</template>

<style scoped>
.url-list-add {
    transition: background-color 0.2s ease, border-color 0.2s ease;
}
.url-list-add:hover {
    border-color: var(--v-theme-primary);
    background: var(--v-theme-surfaceContainerLow);
}
</style>
