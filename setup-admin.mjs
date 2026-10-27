// Cria/atualiza o administrador no Supabase Auth sem expor a service_role no site.
// Uso:
// SUPABASE_URL="https://xxxx.supabase.co" SUPABASE_SERVICE_ROLE_KEY="..." ADMIN_PASSWORD="sua-senha-forte" node setup-admin.mjs

const url=process.env.SUPABASE_URL;
const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
if(!url||!key){console.error('Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no terminal.');process.exit(1)}
const email='planet@admin.planet.local';
const password=process.env.ADMIN_PASSWORD;
if(!password||password.length<10){console.error('Defina ADMIN_PASSWORD com uma senha forte (mínimo 10 caracteres) no terminal.');process.exit(1)}
const headers={'apikey':key,'Authorization':`Bearer ${key}`,'Content-Type':'application/json'};

async function req(path,opts={}){const r=await fetch(url+path,{...opts,headers:{...headers,...opts.headers}});const txt=await r.text();let body;try{body=JSON.parse(txt)}catch{body=txt}if(!r.ok)throw new Error(`${r.status}: ${typeof body==='string'?body:JSON.stringify(body)}`);return body}

let user;
try{
  const list=await req('/auth/v1/admin/users?page=1&per_page=100');
  user=(list.users||[]).find(u=>u.email===email);
  if(!user){user=await req('/auth/v1/admin/users',{method:'POST',body:JSON.stringify({email,password,email_confirm:true,user_metadata:{username:'planet'}})});console.log('Usuário admin criado.')}else{await req(`/auth/v1/admin/users/${user.id}`,{method:'PUT',body:JSON.stringify({password,email_confirm:true,user_metadata:{username:'planet'}})});console.log('Senha do admin atualizada.')}
  await req('/rest/v1/profiles?on_conflict=id',{method:'POST',headers:{'Prefer':'resolution=merge-duplicates,return=minimal'},body:JSON.stringify([{id:user.id,username:'planet',role:'admin'}])});
  console.log('Perfil administrativo configurado. Login: planet');
}catch(e){console.error('Falha ao configurar admin:',e.message);process.exit(1)}
