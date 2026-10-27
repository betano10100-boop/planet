-- Contas de clientes (CPF, e-mail, WhatsApp). Rode no Supabase > SQL Editor DEPOIS do schema.sql e do horario-loja.sql.
create or replace function public.valid_cpf(c text) returns boolean language plpgsql immutable as $$
declare d int[]; s int; i int;
begin
  c:=regexp_replace(coalesce(c,''),'\D','','g');
  if length(c)<>11 or c ~ '^(\d)\1{10}$' then return false; end if;
  for i in 1..11 loop d[i]:=substr(c,i,1)::int; end loop;
  s:=0; for i in 1..9 loop s:=s+d[i]*(11-i); end loop;
  s:=(s*10)%11; if s=10 then s:=0; end if; if s<>d[10] then return false; end if;
  s:=0; for i in 1..10 loop s:=s+d[i]*(12-i); end loop;
  s:=(s*10)%11; if s=10 then s:=0; end if; return s=d[11];
end $$;

create table if not exists public.customers(
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null, cpf text not null unique, whatsapp text not null unique, email text not null,
  cep text, address text, number text, complement text, created_at timestamptz not null default now());
alter table public.customers enable row level security;
drop policy if exists "customer reads self" on public.customers;
drop policy if exists "customer updates self" on public.customers;
drop policy if exists "admins manage customers" on public.customers;
DROP POLICY IF EXISTS "customer reads self" ON public.customers;

CREATE POLICY "customer reads self" ON public.customers for select using (id=auth.uid() or public.is_admin());
DROP POLICY IF EXISTS "customer updates self" ON public.customers;

CREATE POLICY "customer updates self" ON public.customers for update using (id=auth.uid()) with check (id=auth.uid());
DROP POLICY IF EXISTS "admins manage customers" ON public.customers;

CREATE POLICY "admins manage customers" ON public.customers for all using (public.is_admin()) with check (public.is_admin());

-- Cliente não altera CPF nem e-mail; valida WhatsApp na edição
create or replace function public.customers_guard() returns trigger language plpgsql as $$
begin
  if not public.is_admin() then new.id:=old.id; new.cpf:=old.cpf; new.email:=old.email; end if;
  if length(new.whatsapp) not between 10 and 11 then raise exception 'WhatsApp inválido'; end if;
  return new;
end $$;
drop trigger if exists customers_guard_t on public.customers;
create trigger customers_guard_t before update on public.customers for each row execute function public.customers_guard();

-- Cria o cadastro do cliente quando a conta é criada (valida CPF, WhatsApp e nome no banco)
create or replace function public.handle_new_customer() returns trigger language plpgsql security definer set search_path=public as $$
declare m jsonb:=coalesce(new.raw_user_meta_data,'{}'::jsonb); v_cpf text; v_wa text;
begin
  if m->>'cpf' is null then return new; end if; -- admin e outros usuários
  v_cpf:=regexp_replace(m->>'cpf','\D','','g'); v_wa:=regexp_replace(coalesce(m->>'whatsapp',''),'\D','','g');
  if not public.valid_cpf(v_cpf) then raise exception 'CPF inválido'; end if;
  if length(v_wa) not between 10 and 11 then raise exception 'WhatsApp inválido'; end if;
  if length(trim(coalesce(m->>'name','')))<3 then raise exception 'Nome inválido'; end if;
  insert into public.customers(id,name,cpf,whatsapp,email) values(new.id,trim(m->>'name'),v_cpf,v_wa,lower(new.email));
  return new;
end $$;
drop trigger if exists on_auth_customer on auth.users;
create trigger on_auth_customer after insert on auth.users for each row execute function public.handle_new_customer();

-- Checagem de duplicidade no cadastro (devolve só verdadeiro/falso)
create or replace function public.check_signup(p_cpf text,p_whatsapp text) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('cpf',exists(select 1 from customers where cpf=regexp_replace(p_cpf,'\D','','g')),
                            'whatsapp',exists(select 1 from customers where whatsapp=regexp_replace(p_whatsapp,'\D','','g')));
$$;
grant execute on function public.check_signup(text,text) to anon,authenticated;

-- Login por CPF ou WhatsApp: devolve o e-mail da conta para o login com senha
create or replace function public.resolve_login(p_identifier text) returns text language sql stable security definer set search_path=public as $$
  select email from customers
  where cpf=regexp_replace(p_identifier,'\D','','g') or whatsapp=regexp_replace(regexp_replace(p_identifier,'\D','','g'),'^55(\d{10,11})$','\1')
  order by (cpf=regexp_replace(p_identifier,'\D','','g')) desc limit 1;
$$;
grant execute on function public.resolve_login(text) to anon,authenticated;

-- Pedidos ligados à conta do cliente
alter table public.orders add column if not exists customer_id uuid references auth.users(id) on delete set null;
create or replace function public.orders_set_customer() returns trigger language plpgsql as $$
begin new.customer_id:=auth.uid(); return new; end $$;
drop trigger if exists orders_set_customer_t on public.orders;
create trigger orders_set_customer_t before insert on public.orders for each row execute function public.orders_set_customer();
drop policy if exists "customer reads own orders" on public.orders;
drop policy if exists "customer reads own items" on public.order_items;
DROP POLICY IF EXISTS "customer reads own orders" ON public.orders;

CREATE POLICY "customer reads own orders" ON public.orders for select using (customer_id=auth.uid());
DROP POLICY IF EXISTS "customer reads own items" ON public.order_items;

CREATE POLICY "customer reads own items" ON public.order_items for select using (exists(select 1 from public.orders o where o.id=order_id and o.customer_id=auth.uid()));
