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
  <v-expansion-panels variant="accordion" class="mb-2">
    <v-expansion-panel :title="t(`event.${eventKey}`)">
      <template #text>
        <div v-if="eventKey !== 'Unknown'">
          <div v-if="event.DhcpIpv4Changed">
            {{ `${eventValue[0]} -> ${eventValue[1]}` }}
          </div>
          <pre v-else class="text-mono text-body-2">{{ eventValue }}</pre>
        </div>
        <pre v-else class="text-mono text-body-2">{{ eventValue }}</pre>
      </template>
    </v-expansion-panel>
  </v-expansion-panels>
</template>
