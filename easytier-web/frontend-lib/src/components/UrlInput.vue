<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
    placeholder?: string
    protos: { [proto: string]: number }
}>()

const { t } = useI18n()
const url = defineModel<string>({ required: true })
const editing = ref(false)
const hostFocused = ref(false)

const parseUrl = (val: string | null | undefined): { proto: string; host: string; port: number | null } => {
    const getValidPort = (portStr: string, proto: string) => {
        const p = parseInt(portStr)
        return isNaN(p) ? (props.protos[proto] ?? 11010) : p
    }
    const parseByPattern = (input: string) => {
        const trimmed = input.trim()
        if (!trimmed) {
            return null
        }
        const match = trimmed.match(/^(\w+):\/\/(.*)$/)
        const proto = match ? match[1] : 'tcp'
        const rest = match ? match[2] : trimmed
        const authority = rest.split(/[/?#]/)[0]
        if (!authority) {
            return null
        }
        const hostAndMaybePort = authority.includes('@') ? authority.slice(authority.lastIndexOf('@') + 1) : authority
        if (hostAndMaybePort.startsWith('[')) {
            const ipv6End = hostAndMaybePort.indexOf(']')
            if (ipv6End > 0) {
                const host = hostAndMaybePort.slice(0, ipv6End + 1)
                const remain = hostAndMaybePort.slice(ipv6End + 1)
                // null = no explicit port in URL; do not fabricate a default
                const port: number | null = remain.startsWith(':') ? getValidPort(remain.slice(1), proto) : null
                return { proto, host, port }
            }
        }
        const portMatch = hostAndMaybePort.match(/^(.*):(\d+)$/)
        const host = portMatch ? portMatch[1] : hostAndMaybePort
        // null = no explicit port in URL; buildUrlValue will omit the port entirely,
        // preserving the protocol's implied standard port (e.g. 443 for wss://).
        const port: number | null = portMatch ? parseInt(portMatch[2]) : null
        return { proto, host, port }
    }

    if (!val) {
        return { proto: 'tcp', host: '', port: props.protos['tcp'] ?? 11010 }
    }
    const parsedByPattern = parseByPattern(val)
    if (parsedByPattern) {
        return parsedByPattern
    }
    return { proto: 'tcp', host: '', port: null }
}

const internalValue = ref(parseUrl(url.value))
const defaultHost = '0.0.0.0'

const buildUrlValue = (value: { proto: string, host: string, port: number | null }, forceDefaultHost = false) => {
    const proto = value.proto || 'tcp'
    const rawHost = (value.host ?? '').trim()
    const host = rawHost || (forceDefaultHost ? defaultHost : '')
    if (!host) {
        return null
    }
    // Omit port when the protocol uses no port (protos value = 0), or when the
    // original URL had no explicit port (port === null) – avoids overwriting an
    // implicit standard port (e.g. 443 for wss) with an EasyTier default (11012).
    if (props.protos[proto] === 0 || value.port === null) {
        return `${proto}://${host}`
    }
    return `${proto}://${host}:${value.port}`
}

const syncUrlFromInternal = (forceDefaultHost = false) => {
    const nextUrl = buildUrlValue(internalValue.value, forceDefaultHost)
    if (!nextUrl || nextUrl === url.value) {
        return
    }
    url.value = nextUrl
}

const onHostBlur = () => {
    hostFocused.value = false
    syncUrlFromInternal(true)
}

const onHostFocus = () => {
    hostFocused.value = true
}

const onDialogConfirm = () => {
    syncUrlFromInternal(true)
    editing.value = false
}

const isNoPortProto = computed(() => {
    return props.protos[internalValue.value.proto] === 0
})

// Sync from external
watch(() => url.value, (newVal) => {
    if (hostFocused.value) {
        return
    }
    const parsed = parseUrl(newVal)
    const internalHost = internalValue.value.host ?? ''
    const sameHost = parsed.host === internalHost || (!internalHost.trim() && parsed.host === defaultHost)
    if (parsed.proto !== internalValue.value.proto ||
        !sameHost ||
        parsed.port !== internalValue.value.port) {
        internalValue.value = parsed
    }
})

// Sync to external
watch(internalValue, () => {
    syncUrlFromInternal(false)
}, { deep: true })

const protoOptions = computed(() => Object.keys(props.protos))

const onProtoChange = (newProto: string | null) => {
    if (!newProto) return
    const oldProto = internalValue.value.proto
    const oldDefault = props.protos[oldProto]
    const newDefault = props.protos[newProto]

    if (oldDefault !== undefined && internalValue.value.port === oldDefault && newDefault !== undefined) {
        internalValue.value.port = newDefault
    }
    internalValue.value.proto = newProto
}
</script>

<template>
    <div class="url-input-container w-100">
        <!-- Full width view (>= 400px) -->
        <div class="url-input-full">
            <v-combobox
                :model-value="internalValue.proto"
                :items="protoOptions"
                @update:model-value="onProtoChange"
                hide-details
                density="compact"
                variant="outlined"
                class="url-proto-select"
                style="max-width: 8rem"
            />
            <v-text-field
                :model-value="internalValue.host"
                :placeholder="placeholder || '0.0.0.0'"
                hide-details
                density="compact"
                variant="outlined"
                class="flex-grow-1 url-host-field"
                @update:model-value="internalValue.host = $event"
                @focus="onHostFocus"
                @blur="onHostBlur"
            />
            <template v-if="!isNoPortProto">
                <span class="url-sep">:</span>
                <v-text-field
                    :model-value="internalValue.port"
                    :placeholder="String(protos[internalValue.proto] ?? 11010)"
                    hide-details
                    density="compact"
                    variant="outlined"
                    type="number"
                    min="1"
                    max="65535"
                    class="url-port-field"
                    style="max-width: 6rem"
                    @update:model-value="internalValue.port = $event === '' ? null : Number($event)"
                />
            </template>
            <slot name="actions"></slot>
        </div>

        <!-- Compact view (mobile) -->
        <div class="url-input-compact">
            <div class="d-flex align-center justify-space-between w-100 url-compact-row">
                <span class="truncate text-mono url-compact-text">{{ url }}</span>
                <div class="d-flex align-center shrink-0">
                    <v-btn icon="mdi-pencil" size="small" variant="text" :aria-label="t('web.common.edit')" @click="editing = true" />
                    <slot name="actions"></slot>
                </div>
            </div>
        </div>

        <!-- Edit dialog (used on small screens) -->
        <v-dialog v-model="editing" max-width="500px">
            <v-card :title="placeholder">
                <v-card-text class="d-flex flex-column ga-4 pt-4">
                    <div class="d-flex flex-column ga-2">
                        <label class="text-body-2">{{ t('tunnel_proto') }}</label>
                        <v-combobox
                            :model-value="internalValue.proto"
                            :items="protoOptions"
                            @update:model-value="onProtoChange"
                            hide-details
                            density="compact"
                            variant="outlined"
                        />
                    </div>
                    <div class="d-flex flex-column ga-2">
                        <label class="text-body-2">{{ t('web.common.address') || 'Address' }}</label>
                        <v-text-field
                            :model-value="internalValue.host"
                            :placeholder="placeholder || '0.0.0.0'"
                            hide-details
                            density="compact"
                            variant="outlined"
                            @update:model-value="internalValue.host = $event"
                            @focus="onHostFocus"
                            @blur="onHostBlur"
                        />
                    </div>
                    <div v-if="!isNoPortProto" class="d-flex flex-column ga-2">
                        <label class="text-body-2">{{ t('port') }}</label>
                        <v-text-field
                            :model-value="internalValue.port"
                            :placeholder="String(protos[internalValue.proto] ?? 11010)"
                            hide-details
                            density="compact"
                            variant="outlined"
                            type="number"
                            min="1"
                            max="65535"
                            @update:model-value="internalValue.port = $event === '' ? null : Number($event)"
                        />
                    </div>
                </v-card-text>
                <v-card-actions>
                    <v-spacer />
                    <v-btn variant="elevated" color="primary" @click="onDialogConfirm">
                        <v-icon start>mdi-check</v-icon>
                        {{ t('web.common.confirm') || 'Done' }}
                    </v-btn>
                </v-card-actions>
            </v-card>
        </v-dialog>
    </div>
</template>

<style scoped>
.url-input-container {
    container-type: inline-size;
    min-width: 0;
}

.url-input-full {
    display: none;
    align-items: center;
    gap: 4px;
    min-width: 0;
}

.url-input-compact {
    display: flex;
    align-items: center;
    width: 100%;
    min-width: 0;
}

@container (min-width: 400px) {
    .url-input-full {
        display: flex;
    }
    .url-input-compact {
        display: none;
    }
}

.url-compact-row {
    border: 1px solid var(--v-theme-outlineVariant);
    border-radius: 8px;
    padding: 4px 4px 4px 10px;
    min-width: 0;
    background: var(--v-theme-surface);
}
.url-compact-text {
    font-size: 0.85rem;
    color: var(--v-theme-onSurface);
}
.url-sep {
    font-weight: bold;
    color: var(--v-theme-onSurfaceVariant);
    padding: 0 2px;
}
.url-proto-select :deep(.v-field__input) {
    min-height: 40px;
}
</style>
