-- Cria (ou atualiza) o administrador do painel. Rode no SQL Editor do Supabase.
-- Login do painel: planet   |   Senha: a que você escrever abaixo (troque DEFINA_SUA_SENHA_AQUI)
do $$
declare uid uuid; em text := 'planet@gmail.com'; pw text := '12345678';
begin
  select id into uid from auth.users where email=em;
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
    values('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated',em,extensions.crypt(pw,extensions.gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"username":"planet"}',now(),now(),'','','','');
    insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
    values(gen_random_uuid(),uid,uid::text,jsonb_build_object('sub',uid::text,'email',em),'email',now(),now(),now());
  else
    update auth.users set encrypted_password=extensions.crypt(pw,extensions.gen_salt('bf')),email_confirmed_at=coalesce(email_confirmed_at,now()) where id=uid;
  end if;
  insert into public.profiles(id,username,role) values(uid,'planet','admin') on conflict(id) do update set username='planet',role='admin';
end $$;
