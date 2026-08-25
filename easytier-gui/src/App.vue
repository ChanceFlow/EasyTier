<script setup lang="ts">
import { getCurrentWindow } from '@tauri-apps/api/window'
import pkg from '~/../package.json'

onBeforeMount(async () => {
  await getCurrentWindow().setTitle(`Easytier GUI: v${pkg.version}`)
})
</script>

<template>
  <v-app>
    <RouterView />
  </v-app>
</template>
