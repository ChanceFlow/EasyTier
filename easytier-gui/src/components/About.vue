<script setup lang="ts">
import { getEasytierVersion } from '~/composables/backend'

const { t } = useI18n()

const etVersion = ref('')

onMounted(async () => {
  etVersion.value = await getEasytierVersion()
})
</script>

<template>
  <div class="about-container text-center py-2">
    <div class="et-squircle mx-auto mb-4" style="width: 72px; height: 72px; border-radius: 20px; background: var(--et-accent);">
      <v-icon size="36" color="onPrimary">mdi-shield-outline</v-icon>
    </div>

    <div class="text-h6 font-weight-bold">EasyTier</div>
    <v-chip size="small" color="primary" variant="tonal" class="mt-1 mb-3 font-weight-medium rounded-pill">
      v{{ etVersion || '2.2.0' }}
    </v-chip>

    <p class="text-body-2 text-medium-emphasis mb-4 px-2 about-desc">
      {{ t('about.description') }}
    </p>

    <div class="d-flex justify-center ga-2">
      <v-btn
        variant="tonal"
        size="large"
        rounded="pill"
        prepend-icon="mdi-web"
        href="https://easytier.top"
        target="_blank"
      >
        {{ t('about.homepage') }}
      </v-btn>
      <v-btn
        variant="tonal"
        size="large"
        rounded="pill"
        prepend-icon="mdi-github"
        href="https://github.com/EasyTier/EasyTier"
        target="_blank"
      >
        GitHub
      </v-btn>
    </div>
  </div>
</template>

<style scoped>
.about-container {
  display: flex;
  flex-direction: column;
  align-items: center;
}
.about-desc {
  line-height: 1.6;
  max-width: 22rem;
}
</style>
