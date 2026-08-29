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
            @click="addUrl"
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
