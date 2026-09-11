<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useDisplay } from 'vuetify'
import { v4 as uuidv4 } from 'uuid'

const props = defineProps<{
    placeholder?: string
    protos: { [proto: string]: number }
    /** 外部 label 的 for 目标:绑定到主机名输入框 */
    id?: string
}>()

const { t } = useI18n()
const { smAndDown } = useDisplay()
// 每个实例独立的对话框控件 id,避免同一页面多个 UrlInput 冲突
const uid = uuidv4()
const url = defineModel<string>({ required: true })
const editing = ref(false)
const hostFocused = ref(false)

// The CSS `@container (min-width: 400px)` query swaps the two rows, but
// `display: none` keeps both in the DOM. An external `label[for=props.id]`
// would therefore resolve to the first match — the hidden full-width input on
// a phone. Mirror the same threshold in JS and hand `props.id` to whichever
// row is actually visible, so the id is unique in the DOM.
const COMPACT_MAX_WIDTH = 400
const rootEl = ref<HTMLElement | null>(null)
const compactLayout = ref(false)
let resizeObserver: ResizeObserver | null = null

onMounted(() => {
    if (!rootEl.value || typeof ResizeObserver === 'undefined') return
    resizeObserver = new ResizeObserver((entries) => {
        const width = entries[0]?.contentRect.width ?? 0
        compactLayout.value = width < COMPACT_MAX_WIDTH
    })
    resizeObserver.observe(rootEl.value)
})

onBeforeUnmount(() => {
    resizeObserver?.disconnect()
    resizeObserver = null
})

type ParsedUrlValue = {
    proto: string
    host: string
    port: number | null
    path: string
}

const parseUrl = (val: string | null | undefined): ParsedUrlValue => {
    const getValidPort = (portStr: string, proto: string) => {
        const p = parseInt(portStr)
        return isNaN(p) ? (props.protos[proto] ?? 11010) : p
    }
    const parseByPattern = (input: string): ParsedUrlValue | null => {
        const trimmed = input.trim()
        if (!trimmed) {
            return null
        }
        const match = trimmed.match(/^(\w+):\/\/(.*)$/)
        const proto = match ? match[1] : 'tcp'
        const rest = match ? match[2] : trimmed
        const pathStart = rest.search(/[/?#]/)
        const authority = pathStart >= 0 ? rest.slice(0, pathStart) : rest
        const path = pathStart >= 0 ? rest.slice(pathStart) : ''
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
                return { proto, host, port, path }
            }
        }
        const portMatch = hostAndMaybePort.match(/^(.*):(\d+)$/)
        const host = portMatch ? portMatch[1] : hostAndMaybePort
        // null = no explicit port in URL; buildUrlValue will omit the port entirely,
        // preserving the protocol's implied standard port (e.g. 443 for wss://).
        const port: number | null = portMatch ? parseInt(portMatch[2]) : null
        return { proto, host, port, path }
    }

    if (!val) {
        return { proto: 'tcp', host: '', port: props.protos['tcp'] ?? 11010, path: '' }
    }
    const parsedByPattern = parseByPattern(val)
    if (parsedByPattern) {
        return parsedByPattern
    }
    return { proto: 'tcp', host: '', port: null, path: '' }
}

const internalValue = ref(parseUrl(url.value))
const defaultHost = '0.0.0.0'

// Only schemes that actually carry a path after the authority can edit one.
const supportsPath = computed(() => {
    const proto = internalValue.value.proto
    return proto === 'ws' || proto === 'wss' || proto === 'http' || proto === 'https'
})

const normalizePath = (path: string) => {
    const trimmed = (path ?? '').trim()
    if (!trimmed) {
        return ''
    }
    return trimmed.startsWith('/') ? trimmed : `/${trimmed}`
}

const buildUrlValue = (value: ParsedUrlValue, forceDefaultHost = false) => {
    const proto = value.proto || 'tcp'
    const rawHost = (value.host ?? '').trim()
    const host = rawHost || (forceDefaultHost ? defaultHost : '')
    const path = supportsPath.value ? normalizePath(value.path) : ''
    if (!host) {
        return null
    }
    // Omit port when the protocol uses no port (protos value = 0), or when the
    // original URL had no explicit port (port === null) – avoids overwriting an
    // implicit standard port (e.g. 443 for wss) with an EasyTier default (11012).
    if (props.protos[proto] === 0 || value.port === null) {
        return `${proto}://${host}${path}`
    }
    return `${proto}://${host}:${value.port}${path}`
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
        parsed.port !== internalValue.value.port ||
        parsed.path !== internalValue.value.path) {
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
    <div ref="rootEl" class="url-input-container w-100">
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
                :id="compactLayout ? undefined : props.id"
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
            <template v-if="supportsPath">
                <v-text-field
                    :model-value="internalValue.path"
                    placeholder="/mypath"
                    hide-details
                    density="compact"
                    variant="outlined"
                    class="url-path-field"
                    @update:model-value="internalValue.path = $event"
                />
            </template>
            <!-- Rendered in both responsive branches; keep action slot content free of side effects and duplicate IDs. -->
            <slot name="actions"></slot>
        </div>

        <!-- Compact view (mobile) -->
        <div class="url-input-compact">
            <div class="d-flex align-center justify-space-between w-100 url-compact-row">
                <!-- Real focusable control: an external `label[for=props.id]` targets
                     this instead of the hidden full-width input on a phone. -->
                <button
                    type="button"
                    :id="compactLayout ? props.id : undefined"
                    class="url-compact-trigger"
                    @click="editing = true"
                >
                    <span class="truncate text-mono url-compact-text">{{ url }}</span>
                </button>
                <div class="d-flex align-center shrink-0">
                    <v-btn icon="mdi-pencil" size="small" variant="text" :aria-label="t('web.common.edit')" @click="editing = true" />
                    <slot name="actions"></slot>
                </div>
            </div>
        </div>

        <!-- Edit dialog (used on small screens) -->
        <v-dialog v-model="editing" max-width="500px" :fullscreen="smAndDown">
            <v-card :title="placeholder" rounded="xl" class="et-dialog-sheet">
                <v-card-text class="d-flex flex-column ga-4 pt-4">
                    <div class="d-flex flex-column ga-2">
                        <label :for="`${uid}-proto`" class="text-body-2">{{ t('tunnel_proto') }}</label>
                        <v-combobox
                            :id="`${uid}-proto`"
                            :model-value="internalValue.proto"
                            :items="protoOptions"
                            @update:model-value="onProtoChange"
                            hide-details
                            density="compact"
                            variant="outlined"
                        />
                    </div>
                    <div class="d-flex flex-column ga-2">
                        <label :for="`${uid}-host`" class="text-body-2">{{ t('web.common.address') || 'Address' }}</label>
                        <v-text-field
                            :id="`${uid}-host`"
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
                        <label :for="`${uid}-port`" class="text-body-2">{{ t('port') }}</label>
                        <v-text-field
                            :id="`${uid}-port`"
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
                    <div v-if="supportsPath" class="d-flex flex-column ga-2">
                        <label :for="`${uid}-path`" class="text-body-2">{{ t('path') }}</label>
                        <v-text-field
                            :id="`${uid}-path`"
                            :model-value="internalValue.path"
                            placeholder="/mypath"
                            hide-details
                            density="compact"
                            variant="outlined"
                            @update:model-value="internalValue.path = $event"
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
    border: 1px solid var(--et-border);
    border-radius: 12px;
    padding: 4px 4px 4px 12px;
    min-width: 0;
    min-height: 44px;
    background: var(--et-surface);
}
.url-compact-trigger {
    display: flex;
    align-items: center;
    align-self: stretch;
    flex: 1 1 auto;
    min-width: 0;
    appearance: none;
    background: none;
    border: 0;
    padding: 0;
    margin: 0;
    text-align: left;
    cursor: pointer;
}
.url-compact-text {
    display: block;
    min-width: 0;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
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
.url-path-field {
    min-width: 0;
}
</style>
