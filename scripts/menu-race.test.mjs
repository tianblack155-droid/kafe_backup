import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import ts from 'typescript'
test('shared catalog ignores stale response across composable callers',async()=>{
 const states=new Map(),pending=[]
 const source=readFileSync(new URL('../frontend/app/composables/useMenu.ts',import.meta.url),'utf8')
 const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText
 const module={exports:{}}
 new Function('module','exports','useState','$fetch',code)(module,module.exports,(key,init)=>{if(!states.has(key))states.set(key,{value:init()});return states.get(key)},()=>new Promise(resolve=>pending.push(resolve)))
 const a=module.exports.useMenu(),b=module.exports.useMenu()
 const first=a.load(true).catch(()=>{}),second=b.load(true)
 pending[1]({products:['new']});await second
 pending[0]({products:['old']});await first
 assert.deepEqual(a.menu.value,{products:['new']})
 assert.equal(a.loading.value,false)
})
