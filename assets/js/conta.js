import { supabase, isConfigured, brl } from './supabase.js';
import { REQUIRE_LOGIN } from './config.js';
const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
export const onlyDigits=s=>String(s||'').replace(/\D/g,'');
export const maskCpf=v=>onlyDigits(v).slice(0,11).replace(/^(\d{3})(\d)/,'$1.$2').replace(/^(\d{3})\.(\d{3})(\d)/,'$1.$2.$3').replace(/\.(\d{3})(\d)/,'.$1-$2');
export const maskPhone=v=>{const d=onlyDigits(v).slice(0,11);return d.replace(/^(\d{2})(\d)/,'($1) $2').replace(d.length>10?/(\d{5})(\d{1,4})$/:/(\d{4})(\d{1,4})$/,'$1-$2')};
export function validCpf(v){const c=onlyDigits(v);if(c.length!==11||/^(\d)\1{10}$/.test(c))return false;const dv=n=>{let s=0;for(let i=0;i<n;i++)s+=Number(c[i])*(n+1-i);s=(s*10)%11;return s===10?0:s};return dv(9)===Number(c[9])&&dv(10)===Number(c[10])}
export const normWa=v=>{let d=onlyDigits(v);if((d.length===12||d.length===13)&&d.startsWith('55'))d=d.slice(2);return d};
const validWa=d=>d.length===10||(d.length===11&&d[2]==='9');
const LB={new:'Novo',accepted:'Aceito',preparing:'Preparando',ready:'Pronto',out_for_delivery:'Saiu para entrega',delivered:'Entregue',cancelled:'Cancelado'};
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
let customer=null,isAdmin=false;const subs=[];
export const getCustomer=()=>customer;
export const onCustomer=fn=>subs.push(fn);
const say=(t,ok)=>{const m=$('#authMsg');m.className='form-message '+(ok?'success':'error');m.textContent=t};
const redirect=()=>location.origin+location.pathname;
function showTab(t){$$('[data-tab]').forEach(b=>b.classList.toggle('active',b.dataset.tab===t));$$('.auth-form').forEach(f=>f.classList.toggle('hidden',f.dataset.form!==t));$('#authMsg').textContent=''}
export function openAuth(tab='entrar',note=''){showTab(tab);$('#authNote').textContent=note;$('#authDialog').showModal()}
async function refresh(){
  customer=null;isAdmin=false;
  if(isConfigured){const {data:{session}}=await supabase.auth.getSession();if(session){
    const [c,p]=await Promise.all([supabase.from('customers').select('*').eq('id',session.user.id).maybeSingle(),supabase.from('profiles').select('role').eq('id',session.user.id).maybeSingle()]);
    customer=c.data||null;isAdmin=p.data?.role==='admin'}}
  $('#adminPanelBtn').classList.toggle('hidden',!isAdmin);
  $('#accountBtn').innerHTML=customer?'Olá, '+esc(customer.name.split(' ')[0]):isAdmin?'Olá, Admin':'<span class="hide-sm">Entrar / </span>Criar conta';
  $$('[data-needs-account]').forEach(el=>el.classList.toggle('hidden',!!customer||!REQUIRE_LOGIN));
  subs.forEach(f=>f(customer));
}
$('#accountBtn').onclick=()=>customer?openConta():isAdmin?(location.href='./admin.html'):openAuth('entrar');
$$('[data-open-auth]').forEach(b=>b.onclick=e=>{e.preventDefault();openAuth(b.dataset.openAuth)});
$$('[data-tab]').forEach(b=>b.onclick=()=>showTab(b.dataset.tab));
$$('[data-close-auth]').forEach(b=>b.onclick=()=>$('#authDialog').close());
$$('[data-go]').forEach(b=>b.onclick=()=>showTab(b.dataset.go));
$('#cCpf').oninput=e=>e.target.value=maskCpf(e.target.value);
$('#cWa').oninput=e=>e.target.value=maskPhone(e.target.value);

$('#formEntrar').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget.elements;let email=f.login.value.trim();
  if(!email.includes('@')){const {data}=await supabase.rpc('resolve_login',{p_identifier:email});email=data}
  if(!email)return say('Dados de acesso incorretos.');
  const {error}=await supabase.auth.signInWithPassword({email:email.toLowerCase(),password:f.senha.value});
  if(error)return say(/confirm/i.test(error.message)?'Confirme seu e-mail antes de entrar (veja sua caixa de entrada).':'Dados de acesso incorretos.');
  $('#authDialog').close();$('#formEntrar').reset();await refresh()};

$('#formCriar').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget.elements;
  const nome=f.nome.value.trim(),cpf=onlyDigits(f.cpf.value),wa=normWa(f.whatsapp.value),email=f.email.value.trim().toLowerCase();
  if(nome.split(/\s+/).length<2)return say('Digite seu nome completo.');
  if(!validCpf(cpf))return say('CPF inválido. Confira os números.');
  if(!validWa(wa))return say('WhatsApp inválido. Use DDD + número, ex.: (21) 99999-9999.');
  if(f.senha.value.length<8)return say('A senha precisa ter pelo menos 8 caracteres.');
  if(f.senha.value!==f.senha2.value)return say('As senhas não conferem.');
  const {data:chk,error:chkErr}=await supabase.rpc('check_signup',{p_cpf:cpf,p_whatsapp:wa});
  if(chkErr)return say('O banco ainda não está preparado para cadastros. Rode o arquivo supabase/clientes.sql no SQL Editor do Supabase.');
  if(chk?.cpf)return say('Este CPF já tem cadastro. Entre na sua conta ou recupere a senha.');
  if(chk?.whatsapp)return say('Este WhatsApp já tem cadastro. Entre na sua conta ou recupere a senha.');
  const {data,error}=await supabase.auth.signUp({email,password:f.senha.value,options:{data:{name:nome,cpf,whatsapp:wa},emailRedirectTo:redirect()}});
  if(error)return say(/registered/i.test(error.message)?'Este e-mail já tem cadastro. Entre na sua conta.':/rate limit|too many/i.test(error.message)?'Muitas tentativas de envio de e-mail. Aguarde alguns minutos ou desligue "Confirm email" no Supabase (Authentication > Providers > Email).':/database error/i.test(error.message)?'O banco recusou o cadastro. Confira CPF e WhatsApp e confirme que o supabase/clientes.sql foi executado.':'Não foi possível criar a conta: '+error.message);
  if(data.user&&data.user.identities?.length===0)return say('Este e-mail já tem cadastro. Entre na sua conta.');
  /* Entra logado na hora: se o Supabase não devolveu sessão, faz o login automático com o e-mail e a senha recém-criados */
  const senha=f.senha.value;let session=data.session;
  if(!session){const r=await supabase.auth.signInWithPassword({email,password:senha});session=r.data?.session||null}
  if(session){$('#authDialog').close();$('#formCriar').reset();await refresh();return}
  /* Plano B (só se o Supabase ainda exigir confirmação de e-mail): abre o "Entrar" já preenchido */
  showTab('entrar');const fe=$('#formEntrar').elements;fe.login.value=email;fe.senha.value=senha;
  say('Conta criada! Toque em "Entrar" para continuar.',true)};

$('#formRecuperar').onsubmit=async e=>{e.preventDefault();let email=e.currentTarget.elements.login.value.trim();
  if(!email.includes('@')){const {data}=await supabase.rpc('resolve_login',{p_identifier:email});email=data}
  if(email)await supabase.auth.resetPasswordForEmail(email.toLowerCase(),{redirectTo:redirect()});
  say('Se existir uma conta com esses dados, enviamos o link para criar uma nova senha no e-mail cadastrado.',true)};

$('#formNova').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget.elements;
  if(f.senha.value.length<8)return say('A senha precisa ter pelo menos 8 caracteres.');
  if(f.senha.value!==f.senha2.value)return say('As senhas não conferem.');
  const {error}=await supabase.auth.updateUser({password:f.senha.value});
  if(error)return say('Não foi possível trocar a senha. Peça um novo link.');
  say('Senha alterada! Você já está conectado.',true);setTimeout(()=>$('#authDialog').close(),1200);await refresh()};

async function openConta(){
  const c=customer,f=$('#contaForm').elements;
  $('#contaCpf').textContent=maskCpf(c.cpf);$('#contaEmail').textContent=c.email;
  f.nome.value=c.name;f.whatsapp.value=maskPhone(c.whatsapp);f.cep.value=c.cep||'';f.address.value=c.address||'';f.number.value=c.number||'';f.complement.value=c.complement||'';
  $('#contaMsg').textContent='';$('#contaOrders').innerHTML='<p class="muted">Carregando...</p>';$('#contaDialog').showModal();
  const {data}=await supabase.from('orders').select('order_code,status,total,created_at,order_items(product_name,quantity)').order('created_at',{ascending:false}).limit(10);
  $('#contaOrders').innerHTML=(data||[]).map(o=>`<div class="conta-order"><div><strong>#${esc(o.order_code)}</strong><small>${(o.order_items||[]).map(i=>i.quantity+'x '+esc(i.product_name)).join(', ')}</small></div><div><b>${brl(o.total)}</b><small>${esc(LB[o.status]||o.status)} · ${new Date(o.created_at).toLocaleDateString('pt-BR')}</small></div></div>`).join('')||'<p class="muted">Você ainda não fez pedidos.</p>';
}
$('[data-close-conta]').onclick=()=>$('#contaDialog').close();
$('#contaForm').elements.whatsapp.oninput=e=>e.target.value=maskPhone(e.target.value);
$('#contaForm').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget.elements,m=$('#contaMsg'),wa=normWa(f.whatsapp.value);
  if(f.nome.value.trim().split(/\s+/).length<2||!validWa(wa)){m.className='form-message error';m.textContent='Confira nome completo e WhatsApp.';return}
  const {error}=await supabase.from('customers').update({name:f.nome.value.trim(),whatsapp:wa,cep:f.cep.value,address:f.address.value,number:f.number.value,complement:f.complement.value}).eq('id',customer.id);
  m.className='form-message '+(error?'error':'success');m.textContent=error?(/unique|duplicate/i.test(error.message)?'Este WhatsApp já está em outra conta.':'Não foi possível salvar.'):'Dados salvos!';
  if(!error)await refresh()};
$('#contaLogout').onclick=async()=>{await supabase.auth.signOut();$('#contaDialog').close();await refresh()};

if(isConfigured){supabase.auth.onAuthStateChange(ev=>{if(ev==='PASSWORD_RECOVERY')setTimeout(()=>openAuth('nova','Crie uma nova senha para a sua conta.'),0);else if(ev==='SIGNED_OUT')setTimeout(refresh,0)});}
/* Evita clique duplo e mostra erro amigável se a internet/servidor falhar */
['#formEntrar','#formCriar','#formRecuperar','#formNova','#contaForm'].forEach(s=>{const fm=$(s),h=fm.onsubmit;
  fm.onsubmit=async e=>{e.preventDefault();const b=fm.querySelector('button[type=submit]');if(b&&b.disabled)return;const t=b&&b.textContent;
    if(b){b.disabled=true;b.textContent='Aguarde...'}
    try{if(!isConfigured){if(s==='#contaForm'){const m=$('#contaMsg');m.className='form-message error';m.textContent='Configure a URL e a chave publishable do Supabase em assets/js/config.js.'}else say('Configure a URL e a chave publishable do Supabase em assets/js/config.js.');return}await h.call(fm,e)}catch(err){console.error(err);if(s==='#contaForm'){const m=$('#contaMsg');m.className='form-message error';m.textContent='Sem conexão. Tente de novo.'}else say('Sem conexão com o servidor. Verifique a internet e tente de novo.')}
    finally{if(b){b.disabled=false;b.textContent=t}}}});
refresh();
