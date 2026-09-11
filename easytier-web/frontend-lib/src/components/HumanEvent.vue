<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { EventType } from '../types/network'
import { computed } from 'vue';

const props = defineProps<{
  event: {
    [key: string]: any
  }
}>()
const { t } = useI18n()

// The payload's own key, before an unrecognised event is mapped onto the
// 'Unknown' placeholder used for the i18n title.
const rawEventKey = computed(() => Object.keys(props.event)[0])

const eventKey = computed(() => {
  return Object.keys(EventType).includes(rawEventKey.value) ? rawEventKey.value : 'Unknown'
})

// Read the payload from the event's actual key: for known events that is the
// same value as before, and for unknown events it surfaces the real payload
// instead of the always-undefined `props.event['Unknown']`.
const eventValue = computed(() => props.event[rawEventKey.value])

// Unknown payloads are frequently objects/arrays; render a stable, readable
// string instead of `[object Object]`, falling back to String() for values
// JSON.stringify cannot serialize (e.g. circular references).
const unknownEventText = computed(() => {
  const value = eventValue.value
  if (value === null || value === undefined) {
    return ''
  }
  if (typeof value === 'object') {
    try {
      return JSON.stringify(value)
    } catch {
      return String(value)
    }
  }
  return String(value)
})
</script>

<template>
  <div class="et-event">
    <div class="et-event-title">{{ t(`event.${eventKey}`) }}</div>
    <div v-if="eventKey !== 'Unknown'" class="et-event-body">
      <div v-if="event.DhcpIpv4Changed">
        {{ `${eventValue[0]} -> ${eventValue[1]}` }}
      </div>
      <pre v-else class="text-mono text-caption">{{ eventValue }}</pre>
    </div>
    <pre v-else class="text-mono text-caption">{{ unknownEventText }}</pre>
  </div>
</template>

<style scoped>
.et-event-title {
  font-weight: 650;
  font-size: 0.875rem;
}
.et-event-body {
  margin-top: 4px;
  color: var(--et-text-secondary);
}
.text-mono {
  font-family: var(--font-mono);
  white-space: pre-wrap;
  word-break: break-word;
}
</style>
