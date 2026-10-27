-- Avaliações reais de clientes
-- Rode no Supabase > SQL Editor (depois do clientes.sql).
-- Regras: só quem tem conta e já fez pelo menos 1 pedido pode avaliar; a avaliação só aparece no site depois de aprovada.

create table if not exists public.reviews(
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references auth.users(id) on delete set null,
  author_name text not null,
  rating int not null check (rating between 1 and 5),
  comment text not null check (char_length(comment) between 5 and 400),
  product_name text,
  approved boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.reviews enable row level security;
drop policy if exists "public reads approved reviews" on public.reviews;
drop policy if exists "admins manage reviews" on public.reviews;
DROP POLICY IF EXISTS "public reads approved reviews" ON public.reviews;

CREATE POLICY "public reads approved reviews" ON public.reviews for select using (approved = true or public.is_admin());
DROP POLICY IF EXISTS "admins manage reviews" ON public.reviews;

CREATE POLICY "admins manage reviews" ON public.reviews for all using (public.is_admin()) with check (public.is_admin());
grant select on public.reviews to anon, authenticated;

create or replace function public.submit_review(p_rating int, p_comment text, p_product text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_name text; v_first text; v_last text;
begin
  if auth.uid() is null then raise exception 'Entre na sua conta para avaliar.'; end if;
  if not exists(select 1 from public.orders where customer_id = auth.uid()) then
    raise exception 'Só quem já fez um pedido pode avaliar.';
  end if;
  if (select count(*) from public.reviews where customer_id = auth.uid() and created_at > now() - interval '1 day') >= 3 then
    raise exception 'Você já enviou avaliações hoje. Tente amanhã.';
  end if;
  select name into v_name from public.customers where id = auth.uid();
  v_first := split_part(trim(v_name),' ',1);
  v_last := regexp_replace(trim(v_name),'^.*\s','');
  insert into public.reviews(customer_id, author_name, rating, comment, product_name)
  values(auth.uid(),
         case when v_last <> v_first then v_first || ' ' || left(v_last,1) || '.' else v_first end,
         p_rating, trim(p_comment), nullif(left(trim(coalesce(p_product,'')),80),''));
end $$;
grant execute on function public.submit_review(int,text,text) to authenticated;

-- Para aprovar: Supabase > Table Editor > reviews > marque a coluna "approved" como true.
