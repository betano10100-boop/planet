-- Cadastro sem verificação de e-mail
-- Rode este arquivo no Supabase > SQL Editor (uma vez).
-- Toda conta nova já nasce com o e-mail confirmado, então o cliente consegue entrar logo após criar a conta.
-- Recomendado também: Authentication > Providers > Email > desligue "Confirm email" (assim nenhum e-mail de confirmação é enviado).

create or replace function public.auto_confirm_email() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.email_confirmed_at is null then new.email_confirmed_at := now(); end if;
  return new;
end $$;

drop trigger if exists auto_confirm_email_t on auth.users;
create trigger auto_confirm_email_t before insert on auth.users
for each row execute function public.auto_confirm_email();

-- Confirma também as contas que ficaram pendentes antes de rodar este arquivo
update auth.users set email_confirmed_at = now() where email_confirmed_at is null;
