import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'

// Node loads backend/.env before Go starts; Go does not read dotenv files itself.
const backend = spawn('go', ['run', './cmd/server'], {
  cwd: fileURLToPath(new URL('../backend/', import.meta.url)),
  stdio: 'inherit',
})

backend.on('error', (error) => {
  console.error(error.code === 'ENOENT' ? 'Go belum terpasang atau belum ada di PATH.' : error.message)
  process.exitCode = 1
})

backend.on('exit', (code) => {
  process.exitCode = code ?? 1
})
