<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { Utils } from 'easytier-frontend-lib';
import ApiClient, { Summary } from '../modules/api';

const props = defineProps({
    api: ApiClient,
});

// 通知状态（替代 PrimeVue Toast）
const snackbar = ref(false);
const snackbarMessage = ref('');

const summary = ref<Summary | undefined>(undefined);

const loadSummary = async () => {
    const resp = await props.api?.get_summary();
    summary.value = resp;
};

const periodFunc = new Utils.PeriodicTask(async () => {
    try {
        await loadSummary();
    } catch (e) {
        snackbarMessage.value = `Load Summary Failed: ${e}`;
        snackbar.value = true;
        console.error(e);
    }
}, 1000);

onMounted(async () => {
    periodFunc.start();
});

onUnmounted(() => {
    periodFunc.stop();
});

const deviceCount = computed<number | undefined>(
    () => {
        return summary.value?.device_count;
    },
);

</script>

<template>
    <v-row dense>
        <v-col cols="12" sm="4">
            <v-card class="h-100" rounded="lg">
                <v-card-title>Device Count</v-card-title>
                <v-card-text>
                    <div class="d-flex justify-center align-center text-h1 font-weight-bold text-success py-4">
                        {{ deviceCount }}
                    </div>
                </v-card-text>
            </v-card>
        </v-col>
        <v-col cols="12" sm="8">
            <v-sheet class="h-100 d-flex align-center justify-center" color="surfaceContainerLow" rounded="lg">
            </v-sheet>
        </v-col>
    </v-row>

    <v-snackbar v-model="snackbar" color="error" :timeout="2000" location="bottom">
        {{ snackbarMessage }}
    </v-snackbar>
</template>
