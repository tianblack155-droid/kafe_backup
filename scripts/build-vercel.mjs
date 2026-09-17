import { spawnSync } from 'node:child_process'
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs'
import { resolve } from 'node:path'

const root = resolve(import.meta.dirname, '..')
const result = spawnSync(process.platform === 'win32' ? 'npm.cmd' : 'npm', ['run', 'build', '--workspace=frontend'], {
  cwd: root,
  stdio: 'inherit',
  env: { ...process.env, NITRO_PRESET: 'vercel' },
})
if (result.error) throw result.error
if (result.status !== 0) process.exit(result.status ?? 1)
const output = resolve(root, 'frontend/.vercel/output')
if (!existsSync(resolve(output, 'config.json'))) throw new Error('Missing Nuxt Vercel Build Output API config')
const config = JSON.parse(readFileSync(resolve(output, 'config.json'), 'utf8'))
if (config.version !== 3) throw new Error('Expected Build Output API version 3')
// Only replace generated output. Never remove project.json or provider settings.
const target = resolve(root, '.vercel/output')
mkdirSync(resolve(root, '.vercel'), { recursive: true })
rmSync(target, { recursive: true, force: true })
cpSync(output, target, { recursive: true })
console.log('Vercel build output ready at repository root .vercel/output')
