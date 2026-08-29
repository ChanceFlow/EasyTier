<script setup lang="ts">
import { getCurrentWindow } from '@tauri-apps/api/window'
import pkg from '~/../package.json'

onBeforeMount(async () => {
  await getCurrentWindow().setTitle(`Easytier GUI: v${pkg.version}`)
})
</script>

<template>
  <v-app class="et-app-host">
    <RouterView />
  </v-app>
</template>

<style>
.et-app-host {
  height: 100%;
  width: 100%;
}
</style>
