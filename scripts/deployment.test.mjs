import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'
const root=resolve(import.meta.dirname,'..')
test('Vercel builds from repo root and delegates to workspace script',()=>{
 const cfg=JSON.parse(readFileSync(resolve(root,'vercel.json'),'utf8'))
 assert.equal(cfg.installCommand,'npm ci')
 assert.equal(cfg.buildCommand,'npm run build:vercel')
 assert.equal(cfg.framework,null)
})
test('Render backend blueprint remains on free compute and root-relative paths',()=>{
 const text=readFileSync(resolve(root,'render.yaml'),'utf8')
 assert.match(text,/plan: free/)
 assert.match(text,/dockerfilePath: \.\/backend\/Dockerfile/)
 assert.match(text,/dockerContext: \.\/backend/)
 assert.match(text,/healthCheckPath: \/health/)
 assert.match(text,/autoDeployTrigger: off/)
})
