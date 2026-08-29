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

const eventKey = computed(() => {
  const key = Object.keys(props.event)[0]
  return Object.keys(EventType).includes(key) ? key : 'Unknown'
})

const eventValue = computed(() => {
  const value = props.event[eventKey.value]
  return typeof value === 'object' ? value : value
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
    <pre v-else class="text-mono text-caption">{{ eventValue }}</pre>
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
