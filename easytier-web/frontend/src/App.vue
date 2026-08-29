<script setup lang="ts">
import { I18nUtils } from 'easytier-frontend-lib'
import { onMounted, onUnmounted } from 'vue';
import { useTheme } from 'vuetify'

const theme = useTheme()

// Follow the OS color scheme (the shared Vuetify instance provides the
// m3Light / m3Dark Material 3 themes).
const darkModeQuery = window.matchMedia('(prefers-color-scheme: dark)')
const applySystemTheme = () => {
    theme.global.name.value = darkModeQuery.matches ? 'm3Dark' : 'm3Light'
}

onMounted(async () => {
  applySystemTheme()
  darkModeQuery.addEventListener('change', applySystemTheme)

  await I18nUtils.loadLanguageAsync(localStorage.getItem('lang') || 'en')
});

onUnmounted(() => {
  darkModeQuery.removeEventListener('change', applySystemTheme)
})
</script>

<template>
  <v-app>
    <RouterView />
  </v-app>
</template>
