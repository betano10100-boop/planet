import { supabase, isConfigured, brl } from './supabase.js';
import { getCustomer, openAuth, onCustomer } from './conta.js';
import { REQUIRE_LOGIN, STORE_WHATSAPP, STORE_PHONE_DISPLAY, STORE_HOURS_LABEL } from './config.js';

const state={categories:[],products:[],cart:(()=>{try{const c=JSON.parse(localStorage.getItem('pg_cart')||'[]');return Array.isArray(c)?c.filter(i=>i&&i.id&&i.qty>0):[]}catch(e){return[]}})(),zones:[],settings:{}};
const $=s=>document.querySelector(s);
const $$=s=>[...document.querySelectorAll(s)];

const categoryGrid=$('#categoryGrid'), productsArea=$('#productsArea'), productsGrid=$('#productsGrid');


/* ===== Horário de funcionamento: terça a domingo, 18h às 00h (horário de Brasília) ===== */
const CLOSED_MSG='Loja fechada no momento. Atendemos todos os dias, das 18h às 03h.';
function brNow(){
  const parts=Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone:'America/Sao_Paulo',weekday:'short',hour:'numeric',hourCycle:'h23'}).formatToParts(new Date()).map(p=>[p.type,p.value]));
  return {day:parts.weekday,hour:Number(parts.hour)};
}
function isOpen(){const n=brNow();return n.hour>=18||n.hour<3}
function applyStoreStatus(){
  const open=isOpen(),n=brNow(),badge=$('#storeBadge');
  if(badge){
    badge.className='store-badge '+(open?'open':'closed');
    badge.textContent=open?'Aberto agora · até 03h':'Fechado · abrimos hoje às 18h';
  }
  $$('.add-btn').forEach(b=>{b.disabled=!open;b.title=open?'':CLOSED_MSG});
  const cb=$('#checkoutBtn');if(cb){cb.disabled=!open;cb.textContent=!open?'Loja fechada':(REQUIRE_LOGIN&&!getCustomer()?'Entrar e finalizar pedido':'Finalizar pedido')}
}
function renderStoreInfo(){
  const wa=`https://wa.me/${STORE_WHATSAPP}?text=${encodeURIComponent('Olá! Vim pelo site do Planet das Galáxias.')}`;
  $$('[data-wa]').forEach(a=>{a.href=wa;a.target='_blank';a.rel='noopener'});
  $$('[data-phone]').forEach(a=>{a.textContent=STORE_PHONE_DISPLAY;if(a.tagName==='A')a.href='tel:+'+STORE_WHATSAPP});
  $$('[data-hours]').forEach(el=>el.textContent=STORE_HOURS_LABEL);
}

function saveCart(){localStorage.setItem('pg_cart',JSON.stringify(state.cart));renderCart()}
function cartCount(){return state.cart.reduce((a,i)=>a+i.qty,0)}
function cartSubtotal(){return state.cart.reduce((a,i)=>a+i.price*i.qty,0)}

function renderCategories(){
  const cats=state.categories.filter(c=>c.active).sort((a,b)=>a.sort_order-b.sort_order);
  categoryGrid.innerHTML=cats.map(c=>`<button class="category-tab" data-id="${escH(c.id)}">${escH(c.name)}</button>`).join('');
  $$('.category-tab').forEach(b=>b.onclick=()=>showCategory(b.dataset.id));
  if(cats.length)showCategory(cats[0].id);
}
function showCategory(id){
  $$('.category-tab').forEach(b=>b.classList.toggle('active',String(b.dataset.id)===String(id)));
  const items=state.products.filter(p=>String(p.category_id)===String(id)&&p.active).sort((a,b)=>Number(a.price)-Number(b.price)||String(a.name).localeCompare(String(b.name),'pt-BR'));
  productsGrid.innerHTML=items.map((p,ix)=>`<article class="menu-item" style="--i:${Math.min(ix,10)}">${p.image_url?`<img class="menu-thumb" src="${escH(p.image_url)}" alt="${escH(p.name)}" loading="lazy">`:''}<div class="menu-info"><h4>${escH(p.name)}</h4>${p.description?`<p>${escH(p.description)}</p>`:''}</div><div class="menu-buy"><span class="price">${brl(p.price)}</span><button class="add-btn" data-id="${p.id}" aria-label="Adicionar ${escH(p.name)}">+</button></div></article>`).join('')||'<p class="empty-msg">Nenhum produto ativo nesta categoria.</p>';
  $$('.add-btn').forEach(b=>b.onclick=()=>addToCart(b.dataset.id));
  applyStoreStatus();
}
const escH=t=>String(t??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
function pushCart(p,sel,notes,extra,optText){const key=p.id+'|'+JSON.stringify(sel)+'|'+notes;const found=state.cart.find(i=>(i.key||String(i.id))===key);if(found)found.qty++;else state.cart.push({key,id:p.id,name:p.name,price:Number(p.price)+extra,qty:1,options:sel,notes,optText});saveCart();openCart()}
function addToCart(id){if(!isOpen()){alert(CLOSED_MSG);return}const p=state.products.find(x=>String(x.id)===String(id));if(!p)return;if(Array.isArray(p.options)&&p.options.length){openOptions(p);return}pushCart(p,{},'',0,'')}
function changeQty(ix,d){const i=state.cart[ix];if(!i)return;i.qty+=d;if(i.qty<=0)state.cart.splice(ix,1);saveCart()}
function renderCart(){
  $('#cartCount').textContent=cartCount();{const el=$('#cartCount');if(window.__lc!==undefined&&window.__lc!==cartCount()){el.classList.remove('bump');void el.offsetWidth;el.classList.add('bump')}window.__lc=cartCount()}{const n=cartCount();$('#cartBar').classList.toggle('hidden',!n);$('#cartBarCount').textContent=n;$('#cartBarTotal').textContent=brl(cartSubtotal());document.body.classList.toggle('has-cart',n>0)} $('#cartSubtotal').textContent=brl(cartSubtotal());
  $('#cartItems').innerHTML=state.cart.length?state.cart.map((i,ix)=>`<div class="cart-item"><div><strong>${escH(i.name)}</strong>${i.optText?`<div class="cart-opts">${escH(i.optText)}</div>`:''}<small>${brl(i.price)} cada</small></div><div class="qty"><button data-ix="${ix}" data-d="-1">−</button><span>${i.qty}</span><button data-ix="${ix}" data-d="1">+</button></div></div>`).join(''):'<p>Seu carrinho está vazio.</p>';
  $$('.qty button').forEach(b=>b.onclick=()=>changeQty(Number(b.dataset.ix),Number(b.dataset.d)));
  updateCheckoutTotal();
}
function openCart(){ $('#cartDrawer').classList.add('open');$('#cartDrawer').setAttribute('aria-hidden','false');$('#drawerBackdrop').classList.remove('hidden') }
function closeCart(){ $('#cartDrawer').classList.remove('open');$('#cartDrawer').setAttribute('aria-hidden','true');$('#drawerBackdrop').classList.add('hidden') }
function selectedFee(){if($('#deliveryType')?.value==='pickup')return 0;const id=$('#deliveryZone')?.value;const z=state.zones.find(x=>String(x.id)===String(id));return Number(z?.fee||0)}
function updateCheckoutTotal(){if($('#checkoutTotal'))$('#checkoutTotal').textContent=brl(cartSubtotal()+selectedFee())}

async function loadData(){
 if(!isConfigured){categoryGrid.innerHTML='<p>Supabase ainda não configurado. Abra <strong>assets/js/config.js</strong> e adicione a URL e a anon key do projeto.</p>';return}
 let categories,products,zones,settings;
 try {
   [{data:categories},{data:products},{data:zones},{data:settings}] = await Promise.all([
     supabase.from('categories').select('*').eq('active',true).order('sort_order'),
     supabase.from('products').select('*').eq('active',true).order('name'),
     supabase.from('delivery_zones').select('*').eq('active',true).order('name'),
     supabase.from('store_settings').select('*').limit(1).maybeSingle()
   ]);
 } catch (err) {
   console.error('Falha ao carregar dados da loja:', err);
   categoryGrid.innerHTML='<p class="empty-msg">Não foi possível conectar ao cardápio. Confira a configuração do Supabase e tente novamente.</p>';
   return;
 }
 if(!categories||!products){categoryGrid.innerHTML='<p class="empty-msg">Não foi possível carregar o cardápio agora. Atualize a página ou chame no WhatsApp.</p>';return}
 state.categories=categories||[];state.products=products||[];
 {const ok=state.cart.filter(i=>state.products.some(p=>String(p.id)===String(i.id)));if(ok.length!==state.cart.length){state.cart=ok;saveCart()}}
state.zones=zones||[];state.settings=settings||{};
 renderCategories();
 $('#deliveryZone').innerHTML='<option value="">Selecione</option>'+state.zones.map(z=>`<option value="${z.id}">${z.name} — ${brl(z.fee)}</option>`).join('');
 const pays=[];if(state.settings.allow_pix)pays.push('Pix');if(state.settings.allow_card)pays.push('Cartão');if(state.settings.allow_cash)pays.push('Dinheiro');$('#paymentMethod').innerHTML=(pays.length?pays:['Pagamento na entrega']).map(x=>`<option>${x}</option>`).join('');
 
}

$('#cartBtn').onclick=openCart;$('#cartBar').onclick=openCart;$('#closeCart').onclick=closeCart;$('#drawerBackdrop').onclick=closeCart;
$('#checkoutBtn').onclick=()=>{if(!isOpen())return alert(CLOSED_MSG);if(!state.cart.length)return alert('Seu carrinho está vazio.');closeCart();if(REQUIRE_LOGIN&&!getCustomer()){openAuth('entrar','Entre ou crie sua conta para finalizar o pedido.');return}$('#checkoutDialog').showModal();fillFromCustomer();updateCheckoutTotal()};
$('#closeCheckout').onclick=()=>$('#checkoutDialog').close();$('#deliveryZone').onchange=updateCheckoutTotal;$('#deliveryType').onchange=()=>{$$('.delivery-field').forEach(el=>el.style.display=$('#deliveryType').value==='pickup'?'none':'grid');updateCheckoutTotal()};


/* ===== CEP: preenche rua, bairro e cidade (ViaCEP) e seleciona a região de entrega ===== */
const norm=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim();
let cepInfo=null;
function payload_address(form){
  if(form.get('delivery_type')!=='delivery')return form.get('address');
  return [form.get('address'),cepInfo?.bairro,cepInfo?`${cepInfo.localidade}/${cepInfo.uf}`:'',form.get('cep')?`CEP ${form.get('cep')}`:''].filter(Boolean).join(' - ');
}
async function lookupCep(){
  const input=$('#cepInput'),msg=$('#cepMsg'),cep=input.value.replace(/\D/g,'');
  input.value=cep.length>5?cep.slice(0,5)+'-'+cep.slice(5,8):cep;
  if(cep.length!==8){cepInfo=null;msg.textContent='';return}
  msg.className='cep-msg';msg.textContent='Buscando endereço...';
  try{
    const d=await (await fetch(`https://viacep.com.br/ws/${cep}/json/`)).json();
    if(d.erro){cepInfo=null;msg.className='cep-msg err';msg.textContent='CEP não encontrado. Preencha o endereço manualmente.';return}
    cepInfo=d;const f=$('#checkoutForm');f.address.value=d.logradouro||f.address.value;
    const z=state.zones.find(x=>norm(x.name)===norm(d.bairro));
    if(z){$('#deliveryZone').value=z.id;msg.className='cep-msg ok';msg.textContent=`${d.bairro} · ${d.localidade}/${d.uf} — entregamos aqui (${brl(z.fee)})`}
    else{$('#deliveryZone').value='';msg.className='cep-msg err';msg.textContent=`${d.bairro||'Bairro'} · ${d.localidade}/${d.uf} — não encontramos esse bairro na lista de entrega. Escolha a região abaixo ou chame no WhatsApp.`}
    updateCheckoutTotal();f.number.focus();
  }catch(e){msg.className='cep-msg err';msg.textContent='Não consegui buscar o CEP agora. Preencha o endereço manualmente.'}
}
$('#cepInput').oninput=lookupCep;
/* ===== Conta do cliente: preenche o checkout e salva o endereço ===== */
function fillFromCustomer(){const c=getCustomer(),f=$('#checkoutForm');if(!c)return;f.customer_name.value=c.name;f.customer_phone.value=c.whatsapp;if(c.address&&!f.address.value){f.address.value=c.address;f.number.value=c.number||'';f.complement.value=c.complement||''}if(c.cep&&!f.cep.value){f.cep.value=c.cep;lookupCep()}}



/* ===== Após confirmar: monta o pedido completo em texto e abre o WhatsApp da loja ===== */
function buildWaUrl(data,payload,cart){
  const zone=state.zones.find(z=>String(z.id)===String(payload.delivery_zone_id));
  const entrega=payload.delivery_type==='delivery';
  const linhas=cart.map(i=>`${i.qty}x ${i.name} — ${brl(i.price*i.qty)}`+(i.optText?`\n   ↳ ${i.optText}`:''));
  const end=entrega?[payload.address,payload.number?`nº ${payload.number}`:'',payload.complement].filter(Boolean).join(', '):'';
  const txt=[
    '*NOVO PEDIDO — Planet das Galáxias*','Pedido: *'+data.order_code+'*','',
    '*Itens*',...linhas,'',
    'Subtotal: '+brl(data.subtotal),
    entrega?`Entrega${zone?' ('+zone.name+')':''}: ${brl(data.delivery_fee)}`:'Retirada no local: R$ 0,00',
    '*TOTAL: '+brl(data.total)+'*','',
    '*Cliente:* '+payload.customer_name,'*WhatsApp:* '+payload.customer_phone,
    '*Tipo:* '+(entrega?'Entrega':'Retirada no local'),
    ...(entrega?['*Endereço:* '+end]:[]),
    '*Pagamento:* '+payload.payment_method,
    ...(payload.notes?['*Observações:* '+payload.notes]:[])
  ].join('\n');
  return `https://wa.me/${STORE_WHATSAPP}?text=${encodeURIComponent(txt)}`;
}

$('#checkoutForm').onsubmit=async(e)=>{
 e.preventDefault();const msg=$('#checkoutMessage');msg.textContent='';if(!isOpen()){msg.className='form-message error';msg.textContent=CLOSED_MSG;return}if(!isConfigured)return;
 const form=new FormData(e.currentTarget); const payload={customer_name:form.get('customer_name'),customer_phone:form.get('customer_phone'),delivery_type:form.get('delivery_type'),address:payload_address(form),number:form.get('number'),complement:form.get('complement'),delivery_zone_id:form.get('delivery_zone_id')||null,payment_method:form.get('payment_method'),notes:form.get('notes'),items:state.cart.map(i=>({product_id:i.id,quantity:i.qty,options:i.options||{},notes:i.notes||''}))};
 if(payload.delivery_type==='delivery'&&!payload.delivery_zone_id){msg.className='form-message error';msg.textContent='Selecione a região de entrega.';return}
 const sb=e.currentTarget.querySelector('button[type=submit]');if(sb.disabled)return;const sbt=sb.textContent;sb.disabled=true;sb.textContent='Enviando pedido...';
 let data,error;try{({data,error}=await supabase.rpc('create_public_order',{payload}))}catch(err){error={message:'sem conexão com a internet. Tente de novo.'}}
 sb.disabled=false;sb.textContent=sbt;
 if(error||!data){msg.className='form-message error';msg.textContent='Não foi possível criar o pedido: '+(error?.message||'tente de novo.');return}
 msg.className='form-message success';msg.innerHTML=`Pedido criado! Seu código é <strong>${data.order_code}</strong>. Total: <strong>${brl(data.total)}</strong>. Salve esse código para acompanhar o pedido.`;
 const waUrl=buildWaUrl(data,payload,state.cart.map(i=>({...i})));
 {const c=getCustomer();if(c&&payload.delivery_type==='delivery')supabase.from('customers').update({cep:form.get('cep'),address:form.get('address'),number:form.get('number'),complement:form.get('complement')}).eq('id',c.id).then(()=>{})}state.cart=[];saveCart();$('#checkoutForm').reset();cepInfo=null;$('#cepMsg').textContent='';fillFromCustomer();
 msg.innerHTML+=`<br>Abrindo o WhatsApp com o seu pedido completo... Se não abrir, <a href="${waUrl}" target="_blank" rel="noopener" style="color:#ff9a35;font-weight:700">toque aqui</a>.`;
 setTimeout(()=>{location.href=waUrl},1200);
};

$('#trackForm').onsubmit=async(e)=>{e.preventDefault();if(!isConfigured)return;let data,error;try{({data,error}=await supabase.rpc('get_public_order_status',{p_order_code:$('#trackCode').value.trim(),p_phone:$('#trackPhone').value.trim()}))}catch(err){error=err}$('#trackResult').textContent=error?'Pedido não encontrado ou dados inválidos.':data?`Status: ${data.status_label} • Total: ${brl(data.total)} • Atualizado em ${new Date(data.updated_at).toLocaleString('pt-BR')}`:'Pedido não encontrado.'};

/* ===== Opções do produto (ex.: adicionais): grupos com limite de escolhas, adicionais com preço e observações ===== */
const optDlg=$('#optionsDialog'),optBody=$('#optBody');let optProd=null;
function openOptions(p){
  optProd=p;$('#optTitle').textContent=p.name;$('#optBase').textContent=brl(p.price);
  optBody.innerHTML=p.options.map((g,gi)=>{const max=Number(g.max)||1,min=Number(g.min)||0;
    return `<fieldset class="opt-group" data-gi="${gi}" data-max="${max}"><legend><span class="opt-gname">${escH(g.name)}</span><small>${min?'Obrigatório · ':''}Escolha até ${max} ${max===1?'item':'itens'}</small></legend>`+
    g.items.map((it,ii)=>`<label class="opt-row"><input type="checkbox" data-gi="${gi}" data-ii="${ii}"><span class="opt-name">${escH(it.name)}</span>${Number(it.price)>0?`<span class="opt-price">+ ${brl(it.price)}</span>`:''}</label>`).join('')+'</fieldset>'}).join('')+
    '<label class="opt-notes">Observações<textarea id="optNotes" maxlength="200" rows="2" placeholder="Ex.: sem granola, caprichar na calda..."></textarea></label>';
  $('#optMsg').textContent='';optRefresh();optDlg.showModal();optDlg.scrollTop=0;
}
function optPicked(){return $$('#optBody .opt-group').map(fs=>{const g=optProd.options[Number(fs.dataset.gi)];return {g,items:[...fs.querySelectorAll('input:checked')].map(i=>g.items[Number(i.dataset.ii)])}})}
function optRefresh(){
  $$('#optBody .opt-group').forEach(fs=>{const max=Number(fs.dataset.max),boxes=[...fs.querySelectorAll('input')],n=boxes.filter(b=>b.checked).length;
    boxes.forEach(b=>{b.disabled=max>1&&n>=max&&!b.checked;b.closest('.opt-row').classList.toggle('on',b.checked)})});
  const extra=optPicked().reduce((a,x)=>a+x.items.reduce((s,i)=>s+Number(i.price||0),0),0);
  $('#optAdd').textContent='Adicionar · '+brl(Number(optProd.price)+extra);
}
optBody.addEventListener('change',e=>{const t=e.target;if(t.type!=='checkbox')return;const fs=t.closest('.opt-group');
  if(Number(fs.dataset.max)===1&&t.checked)fs.querySelectorAll('input').forEach(b=>{if(b!==t)b.checked=false});
  optRefresh()});
$('#closeOpt').onclick=()=>optDlg.close();
$('#optAdd').onclick=()=>{
  if(!isOpen()){$('#optMsg').className='form-message error';$('#optMsg').textContent=CLOSED_MSG;return}
  const sel={},parts=[];let extra=0;
  for(const {g,items} of optPicked()){
    if(items.length<(Number(g.min)||0)){$('#optMsg').className='form-message error';$('#optMsg').textContent=`Escolha pelo menos ${g.min} em "${g.name}".`;return}
    if(!items.length)continue;sel[g.name]=items.map(i=>i.name);
    parts.push(g.name+': '+items.map(i=>i.name+(Number(i.price)>0?` (+${brl(i.price)})`:'')).join(', '));
    extra+=items.reduce((a,i)=>a+Number(i.price||0),0);
  }
  const notes=$('#optNotes').value.trim().slice(0,200);if(notes)parts.push('Obs: '+notes);
  pushCart(optProd,sel,notes,extra,parts.join(' | '));optDlg.close();
};

/* ===== Avaliações reais: lista aprovadas e deixa clientes (com pedido) avaliarem ===== */
const stars=n=>'★'.repeat(n)+'☆'.repeat(5-n);
function renderReviews(list){
  const g=$('#revGrid'),sm=$('#revSummary');
  if(!list.length){sm.textContent='';g.innerHTML='<p class="empty-msg">Ainda não há avaliações. Peça seu lanche e seja o primeiro a avaliar!</p>';return}
  const avg=list.reduce((a,r)=>a+r.rating,0)/list.length;
  sm.innerHTML=`<strong>${avg.toFixed(1).replace('.',',')}</strong> <span class="rev-stars">${stars(Math.round(avg))}</span> <small>${list.length} ${list.length===1?'avaliação':'avaliações'}</small>`;
  g.innerHTML=list.map(r=>`<article class="rev-card"><div class="rev-stars">${stars(r.rating)}</div><p>${escH(r.comment)}</p><div class="rev-by"><strong>${escH(r.author_name)}</strong>${r.product_name?` · <span>${escH(r.product_name)}</span>`:''}<small>Cliente verificado</small></div></article>`).join('');
}
async function loadReviews(){
  if(!isConfigured){renderReviews([]);return}
  try{const {data}=await supabase.from('reviews').select('*').eq('approved',true).order('created_at',{ascending:false}).limit(12);renderReviews(data||[])}
  catch(e){renderReviews([])}
}
let revRating=0;
function setStars(n){revRating=n;$$('#starInput button').forEach(b=>b.classList.toggle('on',Number(b.dataset.v)<=n))}
$$('#starInput button').forEach(b=>b.onclick=()=>setStars(Number(b.dataset.v)));
$('#revBtn').onclick=()=>{
  if(!getCustomer()){openAuth('entrar','Entre na sua conta para avaliar um lanche.');return}
  $('#revProducts').innerHTML=state.products.map(p=>`<option value="${escH(p.name)}">`).join('');
  setStars(0);$('#reviewMsg').textContent='';$('#reviewForm').reset();$('#reviewDialog').showModal();
};
$('#closeReview').onclick=()=>$('#reviewDialog').close();
$('#reviewForm').onsubmit=async e=>{
  e.preventDefault();const m=$('#reviewMsg'),f=e.currentTarget.elements;
  if(!revRating){m.className='form-message error';m.textContent='Toque nas estrelas para dar uma nota.';return}
  const rb=e.currentTarget.querySelector('button[type=submit]');if(rb.disabled)return;rb.disabled=true;let error;try{({error}=await supabase.rpc('submit_review',{p_rating:revRating,p_comment:f.comment.value,p_product:f.product.value}))}catch(err){error={message:'Sem conexão. Tente de novo.'}}rb.disabled=false;
  if(error){m.className='form-message error';m.textContent=error.message;return}
  m.className='form-message success';m.textContent='Obrigado! Sua avaliação aparece no site assim que for aprovada.';
  setTimeout(()=>$('#reviewDialog').close(),1800);
};

onCustomer(()=>applyStoreStatus());renderCart();renderStoreInfo();applyStoreStatus();setInterval(applyStoreStatus,60000);loadData();loadReviews();

/* ===== Animações: aparecer ao rolar a página (respeita quem desativa animações no aparelho) ===== */
if('IntersectionObserver' in window&&!matchMedia('(prefers-reduced-motion: reduce)').matches){
  const io=new IntersectionObserver(es=>es.forEach(en=>{if(en.isIntersecting){en.target.classList.add('in');io.unobserve(en.target)}}),{threshold:.08,rootMargin:'0px 0px -6% 0px'});
  $$('main .section > *, .track-card, footer > *').forEach(el=>{el.classList.add('reveal');io.observe(el)});
}

document.addEventListener('keydown',e=>{if(e.key==='Escape'&&$('#cartDrawer').classList.contains('open'))closeCart()});
