<script setup lang="ts">
import type { CreateOrderPayload, Product } from '#shared/types'
import { prepareReorder } from '#shared/order-flow'
const props=defineProps<{ products:Product[]; initial:CreateOrderPayload['items']; disabled?:boolean }>()
const emit=defineEmits<{ save:[items:CreateOrderPayload['items']] }>()
const items=ref(JSON.parse(JSON.stringify(props.initial)) as CreateOrderPayload['items'])
const selected=ref('')
const validation=computed(()=>prepareReorder({customer_name:'',payment_method:'cash',items:items.value},props.products))
function product(id:string){return props.products.find(p=>p.id===id)}
function add(){
 const p=product(selected.value);if(!p)return
 const groups=new Set(p.variants.filter(v=>v.is_available).map(v=>v.group_name))
 items.value.push({product_id:p.id,quantity:1,notes:'',addon_ids:[],variant_ids:[...groups].map(g=>(p.variants.find(v=>v.group_name===g&&v.is_available&&v.is_default)??p.variants.find(v=>v.group_name===g&&v.is_available))!.id)})
 selected.value=''
}
function chooseVariant(index:number,group:string,value:string){
 const item=items.value[index];if(!item)return
 const p=product(item.product_id)
 item.variant_ids=item.variant_ids.filter(id=>p?.variants.find(v=>v.id===id)?.group_name!==group)
 if(value)item.variant_ids.push(value)
}
</script>
<template>
 <section class="my-3 border rounded p-3" aria-label="Periksa dan revisi pesanan">
  <p>Pastikan ketersediaan ke staf dan sepakati perubahan dengan pelanggan sebelum menerima uang. Harga dihitung ulang saat disimpan.</p>
  <div v-for="(i,index) in items" :key="index" class="my-3 border-b pb-3">
   <strong>{{product(i.product_id)?.name??'Menu tidak tersedia'}}</strong>
   <label class="block">Jumlah<input v-model.number="i.quantity" type="number" min="1" max="50" class="input" :disabled="disabled"></label>
   <label v-for="g in [...new Set(product(i.product_id)?.variants.filter(v=>v.is_available).map(v=>v.group_name))]" :key="g" class="block">{{g}}
    <select :value="i.variant_ids.find(id=>product(i.product_id)?.variants.find(v=>v.id===id)?.group_name===g)??''" :disabled="disabled" @change="chooseVariant(index,g,($event.target as HTMLSelectElement).value)">
     <option value="">Pilih</option><option v-for="v in product(i.product_id)?.variants.filter(v=>v.group_name===g&&v.is_available)" :key="v.id" :value="v.id">{{v.name}} (+{{fmtIDR(v.price_modifier)}})</option>
    </select>
   </label>
   <label v-for="a in product(i.product_id)?.addons.filter(a=>a.is_available)" :key="a.id" class="block"><input v-model="i.addon_ids" type="checkbox" :value="a.id" :disabled="disabled">{{a.name}} (+{{fmtIDR(a.price)}})</label>
   <label class="block">Catatan<input v-model="i.notes" maxlength="200" class="input" :disabled="disabled"></label>
   <button type="button" class="btn" :disabled="disabled" @click="items.splice(index,1)">Hapus / ganti menu</button>
  </div>
  <select v-model="selected" aria-label="Menu pengganti" :disabled="disabled"><option value="">Pilih menu tambahan/pengganti</option><option v-for="p in products.filter(p=>p.is_available)" :key="p.id" :value="p.id">{{p.name}} — {{fmtIDR(p.price)}}</option></select>
  <button class="btn" :disabled="disabled||!selected||items.length>=50" @click="add">Tambah menu</button>
  <p v-for="e in validation.errors" :key="e" class="text-red-700">{{e}}</p>
  <p>Subtotal perkiraan: {{fmtIDR(validation.subtotal)}} (pajak/service mengikuti server)</p>
  <button class="btn btn-primary mt-3" :disabled="disabled||!items.length||!!validation.errors.length" @click="emit('save',JSON.parse(JSON.stringify(items)))">Menu tersedia dan pelanggan setuju — Simpan</button>
 </section>
</template>
