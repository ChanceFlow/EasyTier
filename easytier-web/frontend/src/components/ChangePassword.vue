<script lang="ts" setup>
import { ref } from 'vue';
import ApiClient from '../modules/api';

const props = defineProps<{
    api: ApiClient | undefined;
}>();

const emit = defineEmits<{
    (e: 'close'): void;
}>();

const password = ref('');

// 密码可见性切换（替代 PrimeVue Password 的 toggleMask）
const showPassword = ref(false);

const changePassword = async () => {
    if (props.api) {
        await props.api.change_password(password.value);
    }
    emit('close');
}
</script>

<template>
    <v-card rounded="lg">
        <v-card-title class="text-h6 font-weight-bold text-center">Change Password
        </v-card-title>
        <v-card-text>
            <div class="d-flex flex-column ga-4">
                <v-text-field v-model="password" placeholder="New Password"
                    :type="showPassword ? 'text' : 'password'"
                    :append-inner-icon="showPassword ? 'mdi-eye-off' : 'mdi-eye'"
                    @click:append-inner="showPassword = !showPassword" />
            </div>
        </v-card-text>
        <v-card-actions>
            <v-btn block color="primary" variant="flat" @click="changePassword">Ok</v-btn>
        </v-card-actions>
    </v-card>
</template>
