// Real Vue pages + production composable/controller; fake only browser/network/auth boundaries.
import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { createRequire } from 'node:module'
import * as Vue from 'vue'
import { parse, compileScript } from '@vue/compiler-sfc'
import ts from 'typescript'
import * as flow from '../frontend/shared/order-flow.ts'
import * as realtime from '../frontend/shared/realtime.ts'
const require=createRequire(import.meta.url)
const flush=async()=>{for(let i=0;i<20;i++)await Promise.resolve();await Vue.nextTick()}
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject}}
const renderer=Vue.createRenderer({createElement:tag=>({tag,children:[],props:{}}),createText:text=>({text}),createComment:text=>({text}),setText:(n,t)=>n.text=t,setElementText:(n,t)=>n.text=t,patchProp:(n,k,o,v)=>n.props[k]=v,insert(n,p,anchor){if(n.parent){const i=n.parent.children.indexOf(n);if(i>=0)n.parent.children.splice(i,1)}n.parent=p;const i=p.children.indexOf(anchor);p.children.splice(i<0?p.children.length:i,0,n)},remove(n){const i=n.parent?.children.indexOf(n);if(i>=0)n.parent.children.splice(i,1)},parentNode:n=>n.parent,nextSibling:n=>{const siblings=n.parent?.children??[];return siblings[siblings.indexOf(n)+1]??null}})
function targets(){const handlers=new Map();return {location:{href:'https://cafe.test'},visibilityState:'visible',addEventListener(k,fn){if(!handlers.has(k))handlers.set(k,new Set());handlers.get(k).add(fn)},removeEventListener(k,fn){handlers.get(k)?.delete(fn)},fire(k){for(const f of handlers.get(k)??[])f()},get count(){return [...handlers.values()].reduce((n,s)=>n+s.size,0)}}}
const snapshot=(id='A',version=1)=>({id,version,status:'pending',payment_status:'unpaid',total:12000,order_items:[],order_number:id})
async function mount(kind,{fetch:fetcher}={}){
 const sockets=[],requests=[],saved=new Map([['tkm-order-A','cap-A'],['tkm-order-B','cap-B'],['tkm-table-token','NOT-ORDER-AUTH']]),win=targets(),doc=targets(),timers=new Map()
 let timerId=0,token='staff-first',authCallback,unsubscribed=false
 const auth={getSession:async()=>({data:{session:token?{access_token:token}:null}}),signOut:async()=>{token=null;authCallback?.('SIGNED_OUT',null)},onAuthStateChange:fn=>{authCallback=fn;return {data:{subscription:{unsubscribe(){unsubscribed=true}}}}}}
 class WS {onopen;onmessage;onclose;onerror;sent=[];closed=false;constructor(url){this.url=url;sockets.push(this)}send(x){this.sent.push(JSON.parse(x))}close(){this.closed=true;this.onclose?.({})}open(){this.onopen?.({})}message(x){this.onmessage?.({data:JSON.stringify(x)})}}
 const route=Vue.reactive({params:{uuid:'A'}})
 const env={ref:Vue.ref,reactive:Vue.reactive,computed:Vue.computed,watch:Vue.watch,nextTick:Vue.nextTick,onMounted:Vue.onMounted,onUnmounted:Vue.onUnmounted,window:win,document:doc,WebSocket:WS,AbortController,queueMicrotask,sessionStorage:{getItem:k=>saved.get(k)??null,setItem:(k,v)=>saved.set(k,v),removeItem:k=>saved.delete(k)},
 setInterval:()=>0,clearInterval:()=>{},setTimeout:(fn,ms)=>{timers.set(++timerId,{fn,ms});return timerId},clearTimeout:id=>timers.delete(id),
 useRoute:()=>route,useSupabase:()=>({auth}),fmtIDR:n=>'Rp'+n,STATUS_LABEL:{},confirm:()=>true,navigateTo:async()=>{},crypto:globalThis.crypto,
 $fetch:async(url,options)=>{requests.push({url,options});return fetcher?fetcher(url,options):url==='/api/core/admin/orders'?[snapshot()]:snapshot(route.params.uuid)}}
 function evaluate(source){const js=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;const module={exports:{}};new Function('require','module','exports',...Object.keys(env),js)(id=>id==='#shared/order-flow'?flow:id==='#shared/realtime'?realtime:require(id),module,module.exports,...Object.values(env));return module.exports}
 // Missing composable is allowed only for the integration RED before implementation.
 try{env.useRealtime=evaluate(readFileSync(new URL('../frontend/app/composables/useRealtime.ts',import.meta.url),'utf8')).useRealtime}catch(e){if(e.code!=='ENOENT')throw e}
 const path=kind==='cashier'?'cashier.vue':'order/[uuid].vue',expose=kind==='cashier'?'orders,editing,draft,busy,loggedIn,logout,tab,offset,load,received':'order,loadError'
 const pageSource=process.env.REALTIME_PAGE_SOURCE==='HEAD'
  ?execFileSync('git',['show','HEAD:frontend/app/pages/'+path],{cwd:new URL('../',import.meta.url),encoding:'utf8'})
  :readFileSync(new URL('../frontend/app/pages/'+path,import.meta.url),'utf8')
 const source=pageSource.replace('</script>',`\ndefineExpose({${expose}})\n</script>`)
 const {descriptor}=parse(source,{filename:path});const compiled=compileScript(descriptor,{id:path,inlineTemplate:true,templateOptions:{compilerOptions:{directiveTransforms:{model:()=>({props:[],needRuntime:false})}}}})
 const app=renderer.createApp(evaluate(compiled.content).default);Object.assign(app.config.globalProperties,{fmtIDR:env.fmtIDR,STATUS_LABEL:{}});for(const name of ['NuxtLink','Icon','OrderEditor'])app.component(name,{render:()=>null})
 const root={children:[]},vm=app.mount(root);await flush()
 return {app,vm,root,route,sockets,requests,win,doc,timers,saved,renew(value){token=value;authCallback?.('TOKEN_REFRESHED',{access_token:value})},get unsubscribed(){return unsubscribed}}
}
function text(node){return [node.text??'',...(node.children??[]).map(text)].join(' ')}
const event=(id='e',order_id='A',version=2)=>({type:'order.changed',event_id:id,order_id,version,event_type:'unrestricted.backend.name'})

test('customer exact capability, ready snapshot, REST versions, focus/online and cleanup',async t=>{
 let version=1;const h=await mount('order',{fetch:async()=>snapshot('A',version)});t.after(()=>h.app.unmount())
 assert.equal(h.sockets.length,1,'MISSING SOCKET: page must start realtime');const ws=h.sockets[0];assert.equal(ws.url,'wss://cafe.test/ws');assert.match(text(h.root),/Menghubungkan…/)
 ws.open();assert.deepEqual(ws.sent,[{type:'subscribe',channel:'order',order_id:'A',order_token:'cap-A'}]);assert.doesNotMatch(text(h.root),/Realtime tersambung/)
 version=3;ws.message({type:'ready'});await flush();assert.equal(h.vm.order.version,3);assert.match(text(h.root),/Realtime tersambung/)
 version=2;ws.message(event('older','A',1000));await flush();assert.equal(h.vm.order.version,3,'REST lower version cannot regress displayed order; event not authoritative')
 version=4;h.win.fire('focus');await flush();assert.equal(h.vm.order.version,4)
 version=5;h.win.fire('online');await flush();assert.equal(h.vm.order.version,5)
 ws.close();await flush();assert.match(text(h.root),/Polling cadangan/)
 h.app.unmount();assert.equal(ws.closed,true);assert.equal(h.win.count+h.doc.count,0);assert.equal(h.timers.size,0)
})

test('route reuse aborts and rejects old response/event; new scope uses new exact capability',async t=>{
 const a=deferred();const h=await mount('order',{fetch:async(url)=>url.endsWith('/A')?a.promise:snapshot('B',2)});t.after(()=>h.app.unmount())
 assert.equal(h.sockets.length,1,'MISSING SOCKET: page must start realtime');const old=h.sockets[0];old.open();const late=old.onmessage
 h.route.params.uuid='B';await flush();assert.equal(old.closed,true);assert.equal(h.requests[0].options.signal.aborted,true)
 const ws=h.sockets[1];ws.open();assert.equal(ws.sent[0].order_token,'cap-B');assert.equal(h.vm.order.id,'B')
 a.resolve(snapshot('A',99));late?.({data:JSON.stringify(event())});await flush();assert.equal(h.vm.order.id,'B');assert.equal(h.vm.order.version,2)
 const n=h.requests.length;ws.message({type:'ready'});await flush();ws.message(event('wrong','A',99));await flush();assert.equal(h.requests.length,n+1)
})

test('cashier events preserve editor/draft/received, busy trails, fresh auth reconnect and logout cleanup',async t=>{
 let version=1;const h=await mount('cashier',{fetch:async()=>[snapshot('A',version)]});t.after(()=>h.app.unmount())
 assert.equal(h.sockets.length,1,'MISSING SOCKET: page must start realtime');let ws=h.sockets[0];ws.open();assert.equal(ws.sent[0].access_token,'staff-first');ws.message({type:'ready'});await flush()
 h.vm.editing=snapshot('A',1);h.vm.draft={customer_name:'unsaved',items:[]};h.vm.received.A=17000
 h.vm.busy=true;version=4;const n=h.requests.length;ws.message(event());await flush();assert.equal(h.requests.length,n)
 h.vm.busy=false;await flush();assert.equal(h.requests.length,n+1);assert.equal(h.vm.orders[0].version,4);assert.equal(h.vm.editing.version,1);assert.equal(h.vm.draft.customer_name,'unsaved');assert.equal(h.vm.received.A,17000)
 h.renew('fresh-token');await flush();assert.equal(ws.closed,true);ws=h.sockets.at(-1);ws.open();assert.equal(ws.sent[0].access_token,'fresh-token')
 await h.vm.logout();await flush();assert.equal(ws.closed,true);assert.equal(h.vm.loggedIn,false);assert.deepEqual(h.vm.orders,[]);assert.equal(h.timers.size,0)
 h.app.unmount();assert.equal(h.unsubscribed,true);assert.equal(h.win.count+h.doc.count,0)
})

test('cashier tab/query reuse cannot apply an old fetch and logout cannot resurrect session',async t=>{
 const pending=deferred();let initial=true
 const h=await mount('cashier',{fetch:async()=>{if(initial){initial=false;return [snapshot()]};return pending.promise}});t.after(()=>h.app.unmount())
 assert.equal(h.sockets.length,1,'MISSING SOCKET: page must start realtime');h.vm.load();await flush();const old=h.requests.at(-1)
 h.vm.tab='history';h.vm.offset=100;await flush();assert.equal(old.options.signal.aborted,true)
 assert.equal(h.requests.at(-1).options.query.tab,'history');assert.equal(h.requests.at(-1).options.query.offset,100)
 await h.vm.logout();pending.resolve([snapshot('old',90)]);await flush();assert.deepEqual(h.vm.orders,[]);assert.equal(h.vm.loggedIn,false)
})
