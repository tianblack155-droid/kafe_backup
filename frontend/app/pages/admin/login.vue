<script setup lang="ts">
const email = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)

async function submit() {
  error.value = ''
  loading.value = true
  const { error: authError } = await useSupabase().auth.signInWithPassword({
    email: email.value,
    password: password.value
  })
  loading.value = false
  if (authError) {
    error.value = 'Email atau password salah.'
    return
  }
  await navigateTo('/admin')
}
</script>

<template>
  <div class="flex min-h-dvh items-center justify-center bg-cream px-4">
    <div class="card w-full max-w-sm p-8">
      <h1 class="font-display text-2xl font-bold text-brand-950">Admin Login</h1>
      <p class="mt-1 text-sm text-brand-500">Masuk untuk mengelola cafe Anda.</p>

      <form class="mt-6 space-y-4" @submit.prevent="submit">
        <div>
          <label class="label" for="email">Email</label>
          <input id="email" v-model="email" type="email" class="input" required autocomplete="email">
        </div>
        <div>
          <label class="label" for="password">Password</label>
          <input id="password" v-model="password" type="password" class="input" required autocomplete="current-password">
        </div>
        <div v-if="error" class="rounded-xl bg-red-50 px-4 py-2.5 text-sm text-red-700" role="alert">{{ error }}</div>
        <button type="submit" class="btn btn-primary w-full" :disabled="loading">
          {{ loading ? 'Memeriksa...' : 'Masuk' }}
        </button>
      </form>
    </div>
  </div>
</template>
