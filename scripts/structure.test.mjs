import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const root = resolve(import.meta.dirname, '..')
test('frontend and legacy backend have independent source directories', () => {
  for (const file of ['frontend/package.json', 'frontend/nuxt.config.ts', 'frontend/app/app.vue', 'backend/legacy-nuxt/api/orders/index.post.ts', 'backend/supabase/migrations/0001_init.sql', 'backend/arsitektur.md']) {
    assert.ok(existsSync(resolve(root, file)), `missing ${file}`)
  }
  assert.ok(!existsSync(resolve(root, 'frontend/server')), 'server source must not live in frontend')
  assert.ok(!existsSync(resolve(root, 'app')), 'old app source must be moved')
})
test('Nuxt explicitly loads the transitional backend', () => {
  const config = readFileSync(resolve(root, 'frontend/nuxt.config.ts'), 'utf8')
  assert.match(config, /serverDir:\s*['"]\.\.\/backend\/legacy-nuxt['"]/)
})
