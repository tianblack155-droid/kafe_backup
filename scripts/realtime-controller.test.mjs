import test from 'node:test'
import assert from 'node:assert/strict'
import { createRealtimeController, realtimeURL } from '../frontend/shared/realtime.ts'

export const flush = async () => { for(let i=0;i<12;i++) await Promise.resolve() }
export function clock(){
 let now=0,id=0;const tasks=new Map()
 return {setTimeout(fn,ms){tasks.set(++id,{fn,at:now+ms});return id},clearTimeout(id){tasks.delete(id)},
 async tick(ms){const end=now+ms;while(true){const next=[...tasks].filter(([,t])=>t.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!next)break;now=next[1].at;tasks.delete(next[0]);next[1].fn();await flush()}now=end;await flush()},get size(){return tasks.size}}
}
export class Socket {
 sent=[];closed=false;onopen=null;onmessage=null;onclose=null;onerror=null
 send(s){this.sent.push(JSON.parse(s))} close(){this.closed=true;this.onclose?.({})}
 open(){this.onopen?.({})} message(x){this.onmessage?.({data:JSON.stringify(x)})}
}
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject}}
function harness(extra={}){
 const time=clock(),sockets=[],applied=[],statuses=[];let calls=0
 const c=createRealtimeController({url:'wss://cafe.test/ws',scope:{channel:'order',order_id:'A'},
 subscribe:async()=>({type:'subscribe',channel:'order',order_id:'A',order_token:'exact-capability'}),
 createSocket:url=>{assert.equal(url,'wss://cafe.test/ws');const s=new Socket();sockets.push(s);return s},
 fetchSnapshot:async()=>({id:'A',version:++calls}),apply:x=>applied.push(x),onStatus:s=>statuses.push(s),
 setTimeout:time.setTimeout,clearTimeout:time.clearTimeout,random:()=>0.5,...extra})
 return {c,time,sockets,applied,statuses,get calls(){return calls}}
}
test('retry gets fresh credentials, ready timeout, renewal, reconciliation and cleanup',async()=>{
 let token='first',credentials=0
 const h=harness({subscribe:async()=>{credentials++;return {type:'subscribe',channel:'cashier',access_token:token}}})
 h.c.start();await flush();h.sockets[0].open();assert.equal(h.sockets[0].sent[0].access_token,'first')
 await h.time.tick(8000);assert.equal(h.sockets[0].closed,true);assert.equal(h.statuses.at(-1),'polling')
 token='second';await h.time.tick(1000);assert.equal(credentials,2);h.sockets[1].open();assert.equal(h.sockets[1].sent[0].access_token,'second')
 h.sockets[1].message({type:'ready'});await flush();const calls=h.calls
 await h.time.tick(30000);assert.ok(h.calls>calls,'connected still reconciles')
 token='renewed';h.c.reconnect();await flush();assert.equal(h.sockets[1].closed,true);h.sockets[2].open();assert.equal(h.sockets[2].sent[0].access_token,'renewed')
 h.c.stop();assert.equal(h.time.size,0);await h.time.tick(100000);assert.equal(credentials,3)
})

test('exponential retry stays bounded with jitter; fallback fetch continues; stop cancels pending credentials',async()=>{
 const delays=[],time=clock();let n=0
 const h=harness({subscribe:async()=>{n++;throw Error('offline')},setTimeout:(fn,ms)=>{delays.push(ms);return time.setTimeout(fn,ms)},clearTimeout:time.clearTimeout,random:()=>1})
 h.c.start();await flush();await time.tick(200000)
 assert.ok(n>5);assert.ok(n<20);assert.ok(h.calls>5);assert.ok(delays.every(ms=>ms<=30000));assert.ok(delays.includes(1500));assert.ok(delays.includes(3000));h.c.stop();assert.equal(time.size,0)
 const d=deferred(),pending=harness({subscribe:()=>d.promise});pending.c.start();await flush();pending.c.stop();d.resolve({type:'subscribe',channel:'cashier',access_token:'late'});await flush();assert.equal(pending.sockets.length,0)
})

test('dedup eviction bounded across cashier order versions, no event high-watermark blocks REST',async()=>{
 const h=harness({scope:{channel:'cashier'},dedupLimit:4});h.c.start();await flush();const s=h.sockets[0];s.open();s.message({type:'ready'});await flush()
 for(const id of ['A','B','C']){s.message(event(id,999,id));await flush()}
 const before=h.calls;s.message(event('A',999,'A'));await flush();assert.equal(h.calls,before+1,'old dedup entries evicted')
 assert.ok(h.applied.at(-1).version<999,'event version never invents snapshot version')
 h.c.stop()
})

const event=(id='e1',version=1,order_id='A')=>({type:'order.changed',event_id:id,order_id,version,event_type:'any.backend.event'})

test('same-origin URL, subscribe only after open, ready resync and event invalidation',async()=>{
 assert.equal(realtimeURL('https://cafe.test/order/A'),'wss://cafe.test/ws')
 assert.equal(realtimeURL('http://localhost:3000'),'ws://localhost:3000/ws')
 assert.equal(realtimeURL('http://cafe.test'),null)
 const h=harness();h.c.start();await flush();const s=h.sockets[0]
 assert.equal(h.calls,1);assert.equal(s.sent.length,0);assert.equal(h.statuses.at(-1),'connecting')
 s.open();assert.deepEqual(s.sent,[{type:'subscribe',channel:'order',order_id:'A',order_token:'exact-capability'}])
 assert.notEqual(h.statuses.at(-1),'connected');s.message({type:'ready'});await flush()
 assert.equal(h.statuses.at(-1),'connected');assert.equal(h.calls,2)
 s.message(event());await flush();assert.equal(h.calls,3);assert.deepEqual(h.applied.at(-1),{id:'A',version:3})
 s.message(event('foreign',100,'B'));await flush();assert.equal(h.calls,3)
 h.c.stop()
})

test('duplicate IDs/versions are bounded, bursts coalesce with trailing refresh, not payload patching',async()=>{
 const h=harness({dedupLimit:2});h.c.start();await flush();const s=h.sockets[0];s.open();s.message({type:'ready'});await flush()
 const before=h.calls
 s.message(event());s.message(event());s.message(event('same-version',1));s.message(event('e2',2));s.message(event('e3',3));await flush()
 assert.equal(h.calls,before+1,'synchronous burst coalesces')
 s.message(event('e3',3));await flush();assert.equal(h.calls,before+1)
 // Older versions are not rejected by a fabricated event watermark after bounded eviction.
 s.message(event('b',1,'B'));s.message(event('c',1,'C')) // ignored for customer scope
 h.c.stop()
 const requests=[],applied=[]
 const busy=harness({fetchSnapshot:()=>{const d=deferred();requests.push(d);return d.promise},apply:x=>applied.push(x)})
 busy.c.start();await flush();const ws=busy.sockets[0];ws.open();ws.message({type:'ready'});ws.message(event());ws.message(event('e2',2));await flush()
 assert.equal(requests.length,1)
 requests[0].resolve({version:9});await flush();assert.equal(requests.length,2,'events during request require trailing snapshot')
 requests[1].resolve({version:10});await flush();assert.deepEqual(applied,[{version:9},{version:10}]);busy.c.stop()
})

test('busy defers invalidations and responses until clear; stop guards stale results',async()=>{
 const requests=[],applied=[]
 const h=harness({fetchSnapshot:({signal})=>{const d=deferred();requests.push({...d,signal});return d.promise},apply:x=>applied.push(x)})
 h.c.start();await flush();h.c.setBusy(true);h.sockets[0].open();h.sockets[0].message({type:'ready'});h.sockets[0].message(event())
 requests[0].resolve({version:1});await flush();assert.deepEqual(applied,[]);assert.equal(requests.length,1)
 h.c.setBusy(false);await flush();assert.equal(requests.length,2)
 h.c.stop();assert.equal(requests[1].signal.aborted,true);requests[1].resolve({version:2});await flush();assert.deepEqual(applied,[])
 assert.equal(h.time.size,0);assert.equal(h.sockets[0].closed,true)
})
