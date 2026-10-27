// Aviso de pedido novo + impressão da comanda (impressora térmica 80mm/58mm ou comum).
const LS={get(k,d){try{const v=localStorage.getItem(k);return v===null?d:JSON.parse(v)}catch(e){return d}},set(k,v){try{localStorage.setItem(k,JSON.stringify(v))}catch(e){}}};
const brl=v=>new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'}).format(Number(v||0));
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
export const cfg={sound:LS.get('pg_sound',true),auto:LS.get('pg_autoprint',true),paper:LS.get('pg_paper','80')};

/* ---------- Comanda ---------- */
export function ticketHtml(o,paper=cfg.paper){
  const w=paper==='58'?'52mm':'72mm',fs=paper==='58'?'11px':'13px';
  const items=(o.order_items||[]).map(i=>{
    const opts=String(i.options_text||'').split(' | ').filter(Boolean).map(t=>`<div class="opt">${esc(t)}</div>`).join('');
    return `<div class="it"><span>${esc(i.quantity)}x ${esc(i.product_name)}</span><b>${brl(Number(i.unit_price)*Number(i.quantity))}</b></div>${opts}`}).join('');
  const entrega=o.delivery_type==='pickup'?'RETIRADA NO LOCAL':'ENTREGA'+(o.delivery_zone_name?' — '+esc(o.delivery_zone_name):'');
  const end=o.delivery_type==='pickup'?'':[o.address,o.number?'nº '+o.number:'',o.complement].filter(Boolean).map(esc).join(', ');
  return `<!doctype html><html><head><meta charset="utf-8"><title>Pedido ${esc(o.order_code)}</title><style>
@page{size:${paper==='58'?'58mm':'80mm'} auto;margin:0}*{box-sizing:border-box}
body{margin:0;width:${w};padding:3mm 2mm;font:${fs}/1.35 "Courier New",monospace;color:#000}
h1{font-size:1.5em;text-align:center;margin:0}.c{text-align:center}.cod{font-size:1.7em;font-weight:700;text-align:center;margin:4px 0}
hr{border:0;border-top:1px dashed #000;margin:6px 0}.it{display:flex;justify-content:space-between;gap:6px;font-weight:700}.opt{padding-left:10px;font-size:.92em}
.row{display:flex;justify-content:space-between}.tot{font-size:1.25em;font-weight:700}.big{font-weight:700;font-size:1.1em}
</style></head><body>
<h1>PLANET DAS GALÁXIAS</h1><div class="c">${esc(new Date(o.created_at||Date.now()).toLocaleString('pt-BR'))}</div>
<div class="cod">#${esc(o.order_code)}</div><hr>
<div class="big">${entrega}</div>${end?`<div>${end}</div>`:''}<hr>
<div><b>Cliente:</b> ${esc(o.customer_name)}</div><div><b>Tel:</b> ${esc(o.customer_phone)}</div><hr>
${items||'<div>(sem itens)</div>'}<hr>
<div class="row"><span>Subtotal</span><span>${brl(o.subtotal)}</span></div>
<div class="row"><span>Entrega</span><span>${brl(o.delivery_fee)}</span></div>
<div class="row tot"><span>TOTAL</span><span>${brl(o.total)}</span></div><hr>
<div><b>Pagamento:</b> ${esc(o.payment_method||'—')}</div>${o.notes?`<div><b>Obs:</b> ${esc(o.notes)}</div>`:''}
<hr><div class="c">Obrigado pela preferência!</div><div style="height:8mm"></div></body></html>`;
}
let chain=Promise.resolve();
export function printOrder(o){
  chain=chain.then(()=>new Promise(done=>{
    const f=document.createElement('iframe');f.setAttribute('aria-hidden','true');f.style.cssText='position:fixed;right:0;bottom:0;width:0;height:0;border:0';
    document.body.appendChild(f);const d=f.contentWindow.document;d.open();d.write(ticketHtml(o));d.close();
    setTimeout(()=>{try{f.contentWindow.focus();f.contentWindow.print()}catch(e){console.error(e)}setTimeout(()=>f.remove(),60000);setTimeout(done,2500)},350);
  }));
  return chain;
}

/* ---------- Som ---------- */
let ac;
function audio(){try{ac=ac||new(window.AudioContext||window.webkitAudioContext)();if(ac.state==='suspended')ac.resume()}catch(e){}return ac}
export function beep(){const c=audio();if(!c)return;[0,.35,.7].forEach((t,i)=>{const o=c.createOscillator(),g=c.createGain(),at=c.currentTime+t;o.type='sine';o.frequency.value=i%2?880:1175;g.gain.setValueAtTime(.0001,at);g.gain.exponentialRampToValueAtTime(.4,at+.02);g.gain.exponentialRampToValueAtTime(.0001,at+.3);o.connect(g);g.connect(c.destination);o.start(at);o.stop(at+.32)})}

/* ---------- Vigia de pedidos novos (consulta o banco a cada 15 s) ---------- */
export function startWatcher(supabase,{onNew,every=15000}={}){
  let seen=null;
  const poll=async()=>{try{
    const {data,error}=await supabase.from('orders').select('*,order_items(quantity,unit_price,product_name,options_text)').order('created_at',{ascending:false}).limit(30);
    if(error||!data)return;
    if(seen===null){seen=new Set(data.map(o=>o.id));return} // pedidos que já existiam não disparam aviso
    const fresh=data.filter(o=>!seen.has(o.id));fresh.forEach(o=>seen.add(o.id));
    if(fresh.length)onNew(fresh.reverse());
  }catch(e){console.error(e)}};
  poll();const t=setInterval(poll,every);document.addEventListener('visibilitychange',()=>{if(!document.hidden)poll()});
  return {poll,stop:()=>clearInterval(t)};
}

/* ---------- Barra de avisos no painel ---------- */
export function mountAlerts(supabase,{goOrders}={}){
  if(document.getElementById('alertBar'))return;
  const bar=document.createElement('section');bar.id='alertBar';bar.className='alert-bar';
  bar.innerHTML=`<div class="ab-row"><span class="ab-live"><i></i> Aviso de pedidos ativo <small>(verifica a cada 15 s — deixe esta aba aberta)</small></span>
  <label><input type="checkbox" id="abSound"> Som</label><label><input type="checkbox" id="abAuto"> Imprimir automático</label>
  <label>Papel <select id="abPaper"><option value="80">80 mm</option><option value="58">58 mm</option></select></label>
  <button type="button" class="btn ghost" id="abTest">Testar aviso</button><button type="button" class="btn ghost" id="abPrintTest">Imprimir teste</button></div>
  <details><summary>Como imprimir sem abrir a janela de impressão</summary><ol>
  <li>No Windows, deixe a impressora térmica como <b>padrão</b> (Configurações &gt; Impressoras).</li>
  <li>Feche o Chrome. Clique com o botão direito no atalho do Chrome &gt; Propriedades e, no fim do campo "Destino", acrescente: <code>--kiosk-printing</code></li>
  <li>Abra o Chrome por esse atalho, entre no painel e deixe a aba aberta. Cada pedido novo imprime sozinho.</li></ol>
  <p>Sem esse atalho, o aviso e o som funcionam normalmente, mas o navegador pergunta antes de imprimir.</p></details>`;
  const top=document.querySelector('.admin-top');top?top.after(bar):document.body.prepend(bar);
  const toast=document.createElement('div');toast.id='newOrderAlert';toast.className='new-order-alert hidden';document.body.appendChild(toast);
  const $=s=>bar.querySelector(s);$('#abSound').checked=cfg.sound;$('#abAuto').checked=cfg.auto;$('#abPaper').value=cfg.paper;
  $('#abSound').onchange=e=>{cfg.sound=e.target.checked;LS.set('pg_sound',cfg.sound);audio();if(cfg.sound&&'Notification' in window&&Notification.permission==='default')Notification.requestPermission()};
  $('#abAuto').onchange=e=>{cfg.auto=e.target.checked;LS.set('pg_autoprint',cfg.auto)};
  $('#abPaper').onchange=e=>{cfg.paper=e.target.value;LS.set('pg_paper',cfg.paper)};
  const sample={order_code:'PL-TESTE',created_at:new Date().toISOString(),customer_name:'Cliente Teste',customer_phone:'(21) 99999-0000',delivery_type:'delivery',delivery_zone_name:'Centro',address:'Rua Exemplo',number:'123',subtotal:23.89,delivery_fee:5,total:28.89,payment_method:'Pix',notes:'Teste de impressão',order_items:[{quantity:1,product_name:'X Bacon',unit_price:16.99},{quantity:1,product_name:'Duplo Smash',unit_price:25.99}]};
  $('#abPrintTest').onclick=()=>printOrder(sample);
  let ringing=null,orig=document.title,flash=null,pending=[];
  const stop=()=>{clearInterval(ringing);clearInterval(flash);ringing=flash=null;document.title=orig;toast.classList.add('hidden');pending=[]};
  const show=list=>{
    pending=pending.concat(list);
    toast.innerHTML=`<strong>🔔 ${pending.length>1?pending.length+' novos pedidos':'Novo pedido!'}</strong>`+pending.slice(-4).map(o=>`<div class="na-row"><span><b>#${esc(o.order_code)}</b> · ${esc(o.customer_name)} · ${brl(o.total)}</span><button type="button" class="btn ghost" data-print="${esc(o.id)}">🖨 Imprimir</button></div>`).join('')+`<div class="na-actions"><button type="button" class="btn primary" id="naSee">Ver pedidos</button><button type="button" class="btn ghost" id="naOk">Entendi</button></div>`;
    toast.classList.remove('hidden');
    toast.querySelectorAll('[data-print]').forEach(b=>b.onclick=()=>printOrder(pending.find(o=>String(o.id)===b.dataset.print)));
    toast.querySelector('#naSee').onclick=()=>{stop();goOrders&&goOrders()};toast.querySelector('#naOk').onclick=stop;
    if(!flash){let on=false;flash=setInterval(()=>{document.title=(on=!on)?'🔔 NOVO PEDIDO! — Admin':orig},900)}
    if(cfg.sound){beep();if(!ringing){let n=0;ringing=setInterval(()=>{if(++n>12)return stop();beep()},8000)}}
    if('Notification' in window&&Notification.permission==='granted'&&document.hidden){try{new Notification('Novo pedido no Planet das Galáxias',{body:list.map(o=>'#'+o.order_code+' · '+brl(o.total)).join('\n')})}catch(e){}}
  };
  $('#abTest').onclick=()=>show([{...sample,id:'teste'}]);
  startWatcher(supabase,{onNew:list=>{show(list);if(cfg.auto)list.forEach(o=>printOrder(o))}});
}
