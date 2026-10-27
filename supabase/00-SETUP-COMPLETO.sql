-- ============================================================
-- PLANET DAS GALÁXIAS — CONFIGURAÇÃO COMPLETA DO SUPABASE
-- Execute este arquivo INTEIRO no Supabase > SQL Editor.
--
-- ORDEM:
-- 1) schema base + dados
-- 2) horário da loja
-- 3) clientes/login
-- 4) cadastro sem confirmação de e-mail
-- 5) opções nos produtos
-- 7) avaliações
-- 8) desativa retirada
-- 9) correção final dos pedidos/gen_random_bytes
-- ============================================================



-- ============================================================
-- INÍCIO: schema.sql
-- ============================================================
-- Planet das Galáxias - esquema completo Supabase
-- Rode este arquivo no SQL Editor de um projeto Supabase novo.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  role text not null default 'customer' check (role in ('admin','customer')),
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete restrict,
  name text not null,
  description text,
  price numeric(10,2) not null check(price >= 0),
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.delivery_zones (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  fee numeric(10,2) not null default 0 check(fee >= 0),
  minimum_order numeric(10,2) not null default 0 check(minimum_order >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.store_settings (
  id uuid primary key default gen_random_uuid(),
  store_name text not null default 'Planet das Galáxias',
  phone text default '',
  opening_hours text default '',
  minimum_order numeric(10,2) not null default 0,
  allow_pickup boolean not null default true,
  allow_cash boolean not null default true,
  allow_pix boolean not null default true,
  allow_card boolean not null default true,
  hero_subtitle text default 'Cardápio completo, pedidos rápidos e entrega com acompanhamento.',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_code text unique not null,
  customer_name text not null,
  customer_phone text not null,
  delivery_type text not null check(delivery_type in ('delivery','pickup')),
  address text,
  number text,
  complement text,
  delivery_zone_id uuid references public.delivery_zones(id),
  delivery_zone_name text,
  delivery_fee numeric(10,2) not null default 0,
  subtotal numeric(10,2) not null,
  total numeric(10,2) not null,
  payment_method text not null,
  payment_status text not null default 'pending' check(payment_status in ('pending','paid','failed','refunded')),
  status text not null default 'new' check(status in ('new','accepted','preparing','ready','out_for_delivery','delivered','cancelled')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id),
  product_name text not null,
  quantity integer not null check(quantity > 0),
  unit_price numeric(10,2) not null,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public, extensions as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.delivery_zones enable row level security;
alter table public.store_settings enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
DROP POLICY IF EXISTS "public read active categories" ON public.categories;

CREATE POLICY "public read active categories" ON public.categories for select using (active or public.is_admin());
DROP POLICY IF EXISTS "admins manage categories" ON public.categories;

CREATE POLICY "admins manage categories" ON public.categories for all using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "public read active products" ON public.products;

CREATE POLICY "public read active products" ON public.products for select using (active or public.is_admin());
DROP POLICY IF EXISTS "admins manage products" ON public.products;

CREATE POLICY "admins manage products" ON public.products for all using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "public read active zones" ON public.delivery_zones;

CREATE POLICY "public read active zones" ON public.delivery_zones for select using (active or public.is_admin());
DROP POLICY IF EXISTS "admins manage zones" ON public.delivery_zones;

CREATE POLICY "admins manage zones" ON public.delivery_zones for all using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "public read settings" ON public.store_settings;

CREATE POLICY "public read settings" ON public.store_settings for select using (true);
DROP POLICY IF EXISTS "admins manage settings" ON public.store_settings;

CREATE POLICY "admins manage settings" ON public.store_settings for all using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "admin profiles" ON public.profiles;

CREATE POLICY "admin profiles" ON public.profiles for select using (id=auth.uid() or public.is_admin());
DROP POLICY IF EXISTS "admin manage profiles" ON public.profiles;

CREATE POLICY "admin manage profiles" ON public.profiles for all using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "admins read orders" ON public.orders;

CREATE POLICY "admins read orders" ON public.orders for select using (public.is_admin());
DROP POLICY IF EXISTS "admins update orders" ON public.orders;

CREATE POLICY "admins update orders" ON public.orders for update using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "admins read items" ON public.order_items;

CREATE POLICY "admins read items" ON public.order_items for select using (public.is_admin());

create or replace function public.store_is_open()
returns boolean language sql stable as $$
  -- Aberto todos os dias, das 18h às 03h (horário de Brasília).
  select extract(hour from (now() at time zone 'America/Sao_Paulo')) >= 18
     or extract(hour from (now() at time zone 'America/Sao_Paulo')) < 3;
$$;
grant execute on function public.store_is_open() to anon,authenticated;

create or replace function public.create_public_order(payload jsonb)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare
  v_order_id uuid;
  v_code text;
  v_subtotal numeric(10,2):=0;
  v_fee numeric(10,2):=0;
  v_total numeric(10,2):=0;
  v_zone record;
  v_item jsonb;
  v_product record;
  v_qty integer;
  v_settings record;
begin
  if not public.store_is_open() then raise exception 'Loja fechada. Atendemos todos os dias, das 18h às 03h.'; end if;
  select * into v_settings from public.store_settings limit 1;
  if payload->>'customer_name' is null or payload->>'customer_phone' is null then raise exception 'Nome e telefone são obrigatórios'; end if;
  if jsonb_array_length(coalesce(payload->'items','[]'::jsonb))=0 then raise exception 'Carrinho vazio'; end if;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    v_qty := greatest(1, least(50, (v_item->>'quantity')::int));
    select id,name,price,active into v_product from public.products where id=(v_item->>'product_id')::uuid;
    if v_product.id is null or not v_product.active then raise exception 'Produto indisponível'; end if;
    v_subtotal := v_subtotal + (v_product.price * v_qty);
  end loop;

  if coalesce(payload->>'delivery_type','delivery')='delivery' then
    select * into v_zone from public.delivery_zones where id=(payload->>'delivery_zone_id')::uuid and active=true;
    if v_zone.id is null then raise exception 'Região de entrega inválida'; end if;
    if v_subtotal < greatest(coalesce(v_zone.minimum_order,0),coalesce(v_settings.minimum_order,0)) then raise exception 'Pedido abaixo do mínimo'; end if;
    v_fee := v_zone.fee;
  else
    if not coalesce(v_settings.allow_pickup,true) then raise exception 'Retirada desativada'; end if;
  end if;

  v_total := v_subtotal + v_fee;
  v_code := 'PL-' || upper(substr(encode(extensions.gen_random_bytes(4),'hex'),1,6));

  insert into public.orders(order_code,customer_name,customer_phone,delivery_type,address,number,complement,delivery_zone_id,delivery_zone_name,delivery_fee,subtotal,total,payment_method,notes)
  values(v_code,payload->>'customer_name',payload->>'customer_phone',coalesce(payload->>'delivery_type','delivery'),payload->>'address',payload->>'number',payload->>'complement',case when payload->>'delivery_type'='pickup' then null else v_zone.id end,case when payload->>'delivery_type'='pickup' then null else v_zone.name end,v_fee,v_subtotal,v_total,coalesce(payload->>'payment_method','Não informado'),payload->>'notes') returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    v_qty := greatest(1, least(50, (v_item->>'quantity')::int));
    select id,name,price into v_product from public.products where id=(v_item->>'product_id')::uuid;
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price) values(v_order_id,v_product.id,v_product.name,v_qty,v_product.price);
  end loop;
  return jsonb_build_object('order_id',v_order_id,'order_code',v_code,'subtotal',v_subtotal,'delivery_fee',v_fee,'total',v_total);
end $$;

grant execute on function public.create_public_order(jsonb) to anon,authenticated;

create or replace function public.get_public_order_status(p_order_code text,p_phone text)
returns jsonb language sql security definer set search_path=public, extensions as $$
  select jsonb_build_object('order_code',o.order_code,'status',o.status,'status_label',case o.status when 'new' then 'Novo' when 'accepted' then 'Aceito' when 'preparing' then 'Preparando' when 'ready' then 'Pronto' when 'out_for_delivery' then 'Saiu para entrega' when 'delivered' then 'Entregue' when 'cancelled' then 'Cancelado' end,'total',o.total,'updated_at',o.updated_at)
  from public.orders o where upper(o.order_code)=upper(p_order_code) and regexp_replace(o.customer_phone,'\\D','','g')=regexp_replace(p_phone,'\\D','','g') limit 1;
$$;
grant execute on function public.get_public_order_status(text,text) to anon,authenticated;

-- Dados iniciais
insert into public.store_settings(store_name,phone,opening_hours,minimum_order,allow_pickup,allow_cash,allow_pix,allow_card)
select 'Planet das Galáxias Bento Ribeiro','(21) 97531-0020','18:00 - 03:00',0,true,true,true,true where not exists(select 1 from public.store_settings);

-- Cardápio Planet das Galáxias
insert into public.categories(name,sort_order,active) values('Combo com piscininha de cheddar',1,true) on conflict(name) do update set sort_order=1,active=true;
insert into public.categories(name,sort_order,active) values('Desfiado das Galaxias',2,true) on conflict(name) do update set sort_order=2,active=true;
insert into public.categories(name,sort_order,active) values('Combo casal',3,true) on conflict(name) do update set sort_order=3,active=true;
insert into public.categories(name,sort_order,active) values('PROMOÇÃO',4,true) on conflict(name) do update set sort_order=4,active=true;
insert into public.categories(name,sort_order,active) values('Entradas',5,true) on conflict(name) do update set sort_order=5,active=true;
insert into public.categories(name,sort_order,active) values('Linha Vegetariana das Galaxias',6,true) on conflict(name) do update set sort_order=6,active=true;
insert into public.categories(name,sort_order,active) values('Burguers Artesanal',7,true) on conflict(name) do update set sort_order=7,active=true;
insert into public.categories(name,sort_order,active) values('Burguers das Galáxias',8,true) on conflict(name) do update set sort_order=8,active=true;
insert into public.categories(name,sort_order,active) values('Bebidas',9,true) on conflict(name) do update set sort_order=9,active=true;
insert into public.categories(name,sort_order,active) values('Bebidas Alcoólicas',10,true) on conflict(name) do update set sort_order=10,active=true;
insert into public.products(category_id,name,description,price,active) select id,'Combo das Galaxias','2 duplo smash com piscininha de cheddar e batata com cheddar e bacon',59.90,true from public.categories where name='Combo com piscininha de cheddar';
insert into public.products(category_id,name,description,price,active) select id,'COMETA DE CARNE SECA','PÃO BRIOCHE, 2 BLENDS DE 90G, CHEDDAR FATIADO, CARNE SECA DESFIADA, QUEIJO DE COALHO, CEBOLA CARAMELIZADA E MAIONESE DA CASA',41.99,true from public.categories where name='Desfiado das Galaxias';
insert into public.products(category_id,name,description,price,active) select id,'PERNIL ESTELAR','PÃO BRIOCHE, 2 BLENDS DE 90G, PERNIL DESFIADO, CHEAM CHEESE, CEBOLA CRISPY E BARBECUE',39.99,true from public.categories where name='Desfiado das Galaxias';
insert into public.products(category_id,name,description,price,active) select id,'EXPLOSÃO SOLAR DE CARNE DE SOL','PÃO BRIOCHE, 2 BLENDS 90G, CHEDDAR FATIADO, CARNE DE SOL DESFIADA, CATUPIRY CREMOSO, BACON CROCANTE, CEBOLA CRISPY E MAIONESE DA CASA',43.99,true from public.categories where name='Desfiado das Galaxias';
insert into public.products(category_id,name,description,price,active) select id,'CONSTELAÇÃO DE CUPIM','PÃO BRIOCHE, 2 BLENDS 90G, CHEDDAR FATIADO, CUPIM DESFIADO, CHEDDAR CREMOSO, CEBOLA CRISPY E BARBECUE',42.99,true from public.categories where name='Desfiado das Galaxias';
insert into public.products(category_id,name,description,price,active) select id,'COSTELA CÓSMICA','PÃO BRIOCHE, 2 BLENDS DE 90G, COSTELA DESFIADA, CATUPIRY CREMOSO, BACON CROCANTE, CEBOLA CARAMELIZADA E MAIONESE DA CASA',44.99,true from public.categories where name='Desfiado das Galaxias';
insert into public.products(category_id,name,description,price,active) select id,'COMBO CASAL','2 DUPLO SMASH + BATATA COM CHEDDAR E BACON + 8 NUGGETS + 8 ANEIS DE CEBOLA + 1 REFRI DE 1LITRO (GUARANA ANTARCTICA)',89.99,true from public.categories where name='Combo casal';
insert into public.products(category_id,name,description,price,active) select id,'2 DUPLO SMASH + 2 GUARAVITAS','PÃO BRIOCHE, 2 BLENDS 80G, CHEDDAR, CEBOLA CARAMELIZADA, BACON E MAIONESE DA CASA',52.99,true from public.categories where name='PROMOÇÃO';
insert into public.products(category_id,name,description,price,active) select id,'JÚPTER - X-TUDO + BATATA E GUARAVITA','PÃO, CARNE, CHEDDAR, OVO, BACON, TOMATE, ALFACE, CEBOLA CARAMELIZADA E MAIONESE DA CASA',27.99,true from public.categories where name='PROMOÇÃO';
insert into public.products(category_id,name,description,price,active) select id,'2 GRAND X CAMARÃO + BATATA PEQUENA','PÃO BRIOCHE, CAMARÕES, TOMATE, CREAM CHEESE, MUÇARELA E ALFACE.',72.99,true from public.categories where name='PROMOÇÃO';
insert into public.products(category_id,name,description,price,active) select id,'2 DUPLO SMASH + BATATA PEQUENA',null,55.99,true from public.categories where name='PROMOÇÃO';
insert into public.products(category_id,name,description,price,active) select id,'2 MUÇA BACON + BATATA PEQUENA','PÃO BRIOCHE, BLEND 160G, MUÇARELA ENVOLVIDA NO BACON, PINCELADA DE MELAÇO DE CANA E MAIONESE DA CASA',79.99,true from public.categories where name='PROMOÇÃO';
insert into public.products(category_id,name,description,price,active) select id,'2 X CAMARÃO + BATATA PEQUENA',null,54.99,true from public.categories where name='PROMOÇÃO';
insert into public.products(category_id,name,description,price,active) select id,'TRIO URANO + BATATA + GUARAVITA','PAO, 2 CARNES, CHEDDAR, BACON, OVO, CEBOLA CARAMELIZADA, TOMATE, ALFACE E MAIONESE DA CASA',31.99,true from public.categories where name='PROMOÇÃO';
insert into public.products(category_id,name,description,price,active) select id,'2 X-TUDO E 2 GUARAVITAS','Pão, carne, cheddar fatiado, bacon, ovo, alface, cebola caramelizada e maionese da casa',36.99,true from public.categories where name='PROMOÇÃO';
insert into public.products(category_id,name,description,price,active) select id,'3 X-CAMARÃO','CAMARÕES ENVOLVIDOS NA MUSSARELA + CREAM CHEESE + ALFACE + TOMATE',69.99,true from public.categories where name='PROMOÇÃO';
insert into public.products(category_id,name,description,price,active) select id,'🍟 BATATA SUPREMA – GRANDE (500g)','Batata crocante coberta com cheddar cremoso, costela desfiada suculenta e bacon crocante. Melhor custo-benefício da casa! Acompanha maionese da casa. Peso aproximado antes do preparo, podendo haver variação após montagem.',43.99,true from public.categories where name='Entradas';
insert into public.products(category_id,name,description,price,active) select id,'🍟 BATATA SUPREMA – MÉDIA (300g)','Batata crocante coberta com cheddar cremoso, costela desfiada suculenta e bacon crocante. Acompanha maionese da casa. Peso aproximado antes do preparo, podendo haver variação após montagem.',34.99,true from public.categories where name='Entradas';
insert into public.products(category_id,name,description,price,active) select id,'Batatas Frita - Pequena',null,9.99,true from public.categories where name='Entradas';
insert into public.products(category_id,name,description,price,active) select id,'Batatas Frita - Média','300G DE BATATA',17.99,true from public.categories where name='Entradas';
insert into public.products(category_id,name,description,price,active) select id,'BATATA FRITA GRANDE',null,30.99,true from public.categories where name='Entradas';
insert into public.products(category_id,name,description,price,active) select id,'Fritas c/ Bacon e Cheddar - Média','300G DE BATATA + CHEDDAR E BACON',25.99,true from public.categories where name='Entradas';
insert into public.products(category_id,name,description,price,active) select id,'Fritas c/ Bacon e Cheddar - Grande','600G DE BATATA + CHEDDAR E BACON',35.99,true from public.categories where name='Entradas';
insert into public.products(category_id,name,description,price,active) select id,'Nuggets','10 unidades e molho',16.99,true from public.categories where name='Entradas';
insert into public.products(category_id,name,description,price,active) select id,'Anel de Cebolas','10 unidades e molho',16.99,true from public.categories where name='Entradas';
insert into public.products(category_id,name,description,price,active) select id,'🪐 Planeta Verde (Clássico)','Hambúrguer vegetal, alface fresca, tomate, cebola caramelizada e maionese verde da casa no pão brioche.',34.90,true from public.categories where name='Linha Vegetariana das Galaxias';
insert into public.products(category_id,name,description,price,active) select id,'🔥 Órbita Defumada','Hambúrguer vegetal com cheddar derretido, molho barbecue e cebola crocante. Sabor intenso e marcante.',35.90,true from public.categories where name='Linha Vegetariana das Galaxias';
insert into public.products(category_id,name,description,price,active) select id,'🍯 Constelação Agridoce','Hambúrguer vegetal com cheddar, cebola caramelizada e toque agridoce especial. Equilíbrio perfeito entre doce e salgado.',36.90,true from public.categories where name='Linha Vegetariana das Galaxias';
insert into public.products(category_id,name,description,price,active) select id,'Costela Cósmica','PÃO BRIOCHE, 2 BLENDS SUCULENTO DE 90G, COSTELA DESFIADA SUPER SABOROSA, CATUPIRY CREMOSO, BACON CROCANTE, CEBOLA CARAMELIZADA E MAIONESE DA CASA.',45.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'Eclipse Burguer','PÃO BRIOCHE, 2 BLENDS 90G, MUSSARELA EMPANADA, ALFACE, TOMATE E CEBOLA CARAMELIZADA.',42.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'Smash','PÃO BRIOCHE, 1 BLEND 120G, CHEDDAR FATIADO, CEBOLA CARAMELIZADA E MAIONESE DA CASA',21.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'Smash Turbo','PÃO BRIOCHE, 1 BLEND 160G, CHEDDAR',24.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'Duplo Smash','Pão, 2 blends 90gr, cheddar fatiado, cebola caramelizada e maionese da casa',25.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'Duplo Smash TURBO','PÃO BRIOCHE, 4 BLENDS DE 90G, CHEDDAR, BACON, ALFACE, TOMATE E CEBOLA CARAMELIZADA.',34.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'TRIPLO SMASH','PÃO BRIOCHE, 3 BLENDS DE 90G, CHEDDAR, BACON, CEBOLA CARAMELIZADA, MAIONESE DA CASA',32.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'Triplo Smash TURBO','PÃO BRIOCHE, 6 BLENDS DE 90G, CHEDDAR FATIADO, BACON, ALFACE, TOMATE, CEBOLA CARAMELIZADA E MAIONESE DA CASA',45.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'Muça Bacon','Pão brioche, 2 blends de 90G, mussarela envolvida com bacon e uma pincelada de melaço de cana',37.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'X-Camarão Monstrinho','PÃO BRIOCHE 1 BLEND DE 90G, CAMARÕES ENVOLVIDOS NA MUSSARELA, CHEDDAR CREMOSO, BACON CROCANTE, OVO, ALFACE, TOMATE, CEBOLA CARAMELIZADA E MAIONESE DA CASA.',40.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'Grand X-Camarão','PÃO BRIOCHE, CREAM CHEESE, CAMARÕES ENVOLVIDOS NA MUSSARELA, ALFACE, TOMATE, CEBOLA CARAMELIZADA E MAIONESE DA CASA',33.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'X-Camarão','PÃO, CREAM CHEESE, CAMARÕES ENVOLVIDOS NA MUSSARELA, ALFACE, TOMATE, CEBOLA CARAMELIZADA E MAIONESE DA CASA.',25.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'New Lua','PÃO BRIOCHE, 2 BLENDS DE 90G, CHEDDAR FATIADO, CAMARÕES ENVOLVIDOS NA MUSSARELA, ALFACE, TOMATE, CEBOLA CARAMELIZADA E MAIONESE DA CASA',35.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'Frango Nobre','Pão, hamburguer de frango empanado artesanal, muçarela, tomate, alface, cebola caramelizada e maionese da casa',30.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'New Sol','Pão brioche, 2 blends de 90g, uma generosidade de cheddar c/ farofa de bacon',37.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'Saturno','PÃO BRIOCHE, 2 BLENDS DE 90G, 3 ANEIS DE CEBOLA, ALFACE, TOMATE E CEBOLA CARAMELIZADA E MAIONESE DA CASA',31.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'MelCoalho','Pao brioche, 2 blends 90gr, 2 fatias de queijo de coalho mergulhadas no mel, bacon e maionese da sua escolha',42.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'NETUNO BBQ','PÃO BRIOCHE, 2 BLENDS 90G, CEBOLA CRISPY E MAIONESE DA CASA',28.99,true from public.categories where name='Burguers Artesanal';
insert into public.products(category_id,name,description,price,active) select id,'3 Marias','Pão, 3 carnes, fatias de cheddar, tomate, alface, cebola caramelizada e maionese da casa',24.99,true from public.categories where name='Burguers das Galáxias';
insert into public.products(category_id,name,description,price,active) select id,'Vênus (X-Burger)','Pão, carne, fatias de cheddar, tomate, alface cebola caramelizada e maionese da casa',12.99,true from public.categories where name='Burguers das Galáxias';
insert into public.products(category_id,name,description,price,active) select id,'Marte (X-Bacon)','Pão, carne, cheddar fatiado, fatias de bacon, tomate, alface, cebola caramelizada e maionese da casa',14.99,true from public.categories where name='Burguers das Galáxias';
insert into public.products(category_id,name,description,price,active) select id,'Júpiter (X-Tudo)','Pão, carne, cheddar fatiado, bacon, ovo, alface, cebola caramelizada e maionese da casa',17.99,true from public.categories where name='Burguers das Galáxias';
insert into public.products(category_id,name,description,price,active) select id,'Terra (X-egg)','pão, carne, fatias de cheddar, ovo, tomate, alface, cebola caramelizada e maionese de casa',14.99,true from public.categories where name='Burguers das Galáxias';
insert into public.products(category_id,name,description,price,active) select id,'URANO (BIG TUDO)','PAO, 2 CARNES, CHEDDAR, BACON, OVO, CEBOLA CARAMELIZADA, TOMATE, ALFACE E MAIONESE DA CASA',21.99,true from public.categories where name='Burguers das Galáxias';
insert into public.products(category_id,name,description,price,active) select id,'Coca-Cola 2 Litros',null,14.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Coca-Cola 2L ZERO','Coca cola zero açúcar',14.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Refrigerante Lata','A partir de R$ 7,00',7.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Fanta laranja lata',null,7.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Fanta uva lata',null,7.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Água tônica',null,7.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Guaravita',null,3.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Guaraviton Tradicional',null,5.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Guaraviton Açai',null,5.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'schweppes citrus',null,7.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'H2O',null,7.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'LIMONETO',null,8.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'GATORADE','A partir de R$ 10,00',10.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Agua sem gas',null,3.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Agua com gas',null,4.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'Red Bull',null,13.00,true from public.categories where name='Bebidas';
insert into public.products(category_id,name,description,price,active) select id,'AMSTEL LATAO',null,9.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'Antarctica Latão',null,7.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'Brahma Latão',null,7.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'Heineken Latão',null,9.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'IMPÉRIO LATÃO',null,7.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'GT',null,10.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'Heineken Longneck',null,10.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'Chopp de vinho PinkMoon',null,8.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'Corona Latão',null,10.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'ICE',null,8.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'HEINEKEN 0.0',null,10.00,true from public.categories where name='Bebidas Alcoólicas';
insert into public.products(category_id,name,description,price,active) select id,'Imperio Gold Long Neck',null,7.00,true from public.categories where name='Bebidas Alcoólicas';

-- FIM: schema.sql


-- ============================================================
-- INÍCIO: horario-loja.sql
-- ============================================================
-- Rode este arquivo no Supabase > SQL Editor (para quem já executou o schema.sql antes).
-- Bloqueia pedidos fora do horário: terça a domingo, das 18h às 00h.

create or replace function public.store_is_open()
returns boolean language sql stable as $$
  -- Aberto todos os dias, das 18h às 03h (horário de Brasília).
  select extract(hour from (now() at time zone 'America/Sao_Paulo')) >= 18
     or extract(hour from (now() at time zone 'America/Sao_Paulo')) < 3;
$$;
grant execute on function public.store_is_open() to anon,authenticated;

create or replace function public.create_public_order(payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_order_id uuid;
  v_code text;
  v_subtotal numeric(10,2):=0;
  v_fee numeric(10,2):=0;
  v_total numeric(10,2):=0;
  v_zone record;
  v_item jsonb;
  v_product record;
  v_qty integer;
  v_settings record;
begin
  if not public.store_is_open() then raise exception 'Loja fechada. Atendemos todos os dias, das 18h às 03h.'; end if;
  select * into v_settings from public.store_settings limit 1;
  if payload->>'customer_name' is null or payload->>'customer_phone' is null then raise exception 'Nome e telefone são obrigatórios'; end if;
  if jsonb_array_length(coalesce(payload->'items','[]'::jsonb))=0 then raise exception 'Carrinho vazio'; end if;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    v_qty := greatest(1, least(50, (v_item->>'quantity')::int));
    select id,name,price,active into v_product from public.products where id=(v_item->>'product_id')::uuid;
    if v_product.id is null or not v_product.active then raise exception 'Produto indisponível'; end if;
    v_subtotal := v_subtotal + (v_product.price * v_qty);
  end loop;

  if coalesce(payload->>'delivery_type','delivery')='delivery' then
    select * into v_zone from public.delivery_zones where id=(payload->>'delivery_zone_id')::uuid and active=true;
    if v_zone.id is null then raise exception 'Região de entrega inválida'; end if;
    if v_subtotal < greatest(coalesce(v_zone.minimum_order,0),coalesce(v_settings.minimum_order,0)) then raise exception 'Pedido abaixo do mínimo'; end if;
    v_fee := v_zone.fee;
  else
    if not coalesce(v_settings.allow_pickup,true) then raise exception 'Retirada desativada'; end if;
  end if;

  v_total := v_subtotal + v_fee;
  v_code := 'PL-' || upper(substr(encode(gen_random_bytes(4),'hex'),1,6));

  insert into public.orders(order_code,customer_name,customer_phone,delivery_type,address,number,complement,delivery_zone_id,delivery_zone_name,delivery_fee,subtotal,total,payment_method,notes)
  values(v_code,payload->>'customer_name',payload->>'customer_phone',coalesce(payload->>'delivery_type','delivery'),payload->>'address',payload->>'number',payload->>'complement',case when payload->>'delivery_type'='pickup' then null else v_zone.id end,case when payload->>'delivery_type'='pickup' then null else v_zone.name end,v_fee,v_subtotal,v_total,coalesce(payload->>'payment_method','Não informado'),payload->>'notes') returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    v_qty := greatest(1, least(50, (v_item->>'quantity')::int));
    select id,name,price into v_product from public.products where id=(v_item->>'product_id')::uuid;
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price) values(v_order_id,v_product.id,v_product.name,v_qty,v_product.price);
  end loop;
  return jsonb_build_object('order_id',v_order_id,'order_code',v_code,'subtotal',v_subtotal,'delivery_fee',v_fee,'total',v_total);
end $$;

grant execute on function public.create_public_order(jsonb) to anon,authenticated;

update public.store_settings set phone='(21) 97531-0020', opening_hours='18:00 - 03:00';

-- FIM: horario-loja.sql


-- ============================================================
-- INÍCIO: clientes.sql
-- ============================================================
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

-- FIM: clientes.sql


-- ============================================================
-- INÍCIO: sem-verificacao-email.sql
-- ============================================================
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

-- FIM: sem-verificacao-email.sql


-- ============================================================
-- INÍCIO: opcoes-pedido.sql
-- ============================================================
-- Opções ao pedir (adicionais: sabor, caldas, complementos, adicionais + observações)
-- Rode este arquivo no Supabase > SQL Editor (uma vez, depois do schema.sql e do horario-loja.sql).

alter table public.products add column if not exists options jsonb;
alter table public.order_items add column if not exists options_text text;

-- Formato de products.options: lista de grupos
--   [{"name":"Caldas","min":0,"max":1,"items":[{"name":"Uva","price":0}]}]
-- min = mínimo obrigatório, max = máximo de itens, price = valor extra por item (R$).

-- Valida o que o cliente escolheu e calcula o extra SEMPRE no banco (o cliente não define preço).
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create or replace function public.resolve_item_options(p_opts jsonb, p_sel jsonb)
returns jsonb language plpgsql stable as $$
declare
  g jsonb; it jsonb; n text;
  v_names text[]; v_lbl text[]; v_parts text[] := '{}';
  v_extra numeric := 0; v_cnt int; v_price numeric;
begin
  if p_opts is null or jsonb_typeof(p_opts) <> 'array' then
    return jsonb_build_object('extra',0,'text','');
  end if;
  for g in select value from jsonb_array_elements(p_opts) loop
    v_names := array(select jsonb_array_elements_text(coalesce(p_sel->(g->>'name'),'[]'::jsonb)));
    v_cnt := coalesce(array_length(v_names,1),0);
    if v_cnt <> (select count(distinct x) from unnest(v_names) x) then raise exception 'Opção repetida em "%"', g->>'name'; end if;
    if v_cnt > coalesce((g->>'max')::int,1) then raise exception 'Máximo de % item(ns) em "%"', g->>'max', g->>'name'; end if;
    if v_cnt < coalesce((g->>'min')::int,0) then raise exception 'Escolha pelo menos % item(ns) em "%"', g->>'min', g->>'name'; end if;
    v_lbl := '{}';
    foreach n in array v_names loop
      select value into it from jsonb_array_elements(g->'items') where value->>'name' = n limit 1;
      if it is null then raise exception 'Opção inválida em "%": %', g->>'name', n; end if;
      v_price := coalesce((it->>'price')::numeric,0);
      v_extra := v_extra + v_price;
      v_lbl := v_lbl || (n || case when v_price > 0 then ' (+R$ ' || replace(to_char(v_price,'FM999990.00'),'.',',') || ')' else '' end);
    end loop;
    if v_cnt > 0 then v_parts := v_parts || ((g->>'name') || ': ' || array_to_string(v_lbl,', ')); end if;
  end loop;
  return jsonb_build_object('extra',v_extra,'text',array_to_string(v_parts,' | '));
end $$;

create or replace function public.create_public_order(payload jsonb)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare
  v_order_id uuid;
  v_code text;
  v_subtotal numeric(10,2):=0;
  v_fee numeric(10,2):=0;
  v_total numeric(10,2):=0;
  v_zone record;
  v_item jsonb;
  v_product record;
  v_qty integer;
  v_settings record;
  v_opt jsonb;
  v_txt text;
begin
  -- Só clientes com conta fazem pedido (o site usa REQUIRE_LOGIN = true). Para permitir pedido sem conta, apague as 3 linhas abaixo.
  if auth.uid() is null then raise exception 'Entre na sua conta para fazer o pedido.'; end if;
  if not public.store_is_open() then raise exception 'Loja fechada. Atendemos todos os dias, das 18h às 03h.'; end if;
  select * into v_settings from public.store_settings limit 1;
  if payload->>'customer_name' is null or payload->>'customer_phone' is null then raise exception 'Nome e telefone são obrigatórios'; end if;
  if jsonb_array_length(coalesce(payload->'items','[]'::jsonb))=0 then raise exception 'Carrinho vazio'; end if;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    v_qty := greatest(1, least(50, (v_item->>'quantity')::int));
    select id,name,price,active,options into v_product from public.products where id=(v_item->>'product_id')::uuid;
    if v_product.id is null or not v_product.active then raise exception 'Produto indisponível'; end if;
    v_opt := public.resolve_item_options(v_product.options, v_item->'options');
    v_subtotal := v_subtotal + ((v_product.price + (v_opt->>'extra')::numeric) * v_qty);
  end loop;

  if coalesce(payload->>'delivery_type','delivery')='delivery' then
    select * into v_zone from public.delivery_zones where id=(payload->>'delivery_zone_id')::uuid and active=true;
    if v_zone.id is null then raise exception 'Região de entrega inválida'; end if;
    if v_subtotal < greatest(coalesce(v_zone.minimum_order,0),coalesce(v_settings.minimum_order,0)) then raise exception 'Pedido abaixo do mínimo'; end if;
    v_fee := v_zone.fee;
  else
    if not coalesce(v_settings.allow_pickup,true) then raise exception 'Retirada desativada'; end if;
  end if;

  v_total := v_subtotal + v_fee;
  loop
    v_code := 'PL-' || upper(substr(encode(extensions.gen_random_bytes(4),'hex'),1,6));
    exit when not exists(select 1 from public.orders where order_code=v_code);
  end loop;

  insert into public.orders(order_code,customer_name,customer_phone,delivery_type,address,number,complement,delivery_zone_id,delivery_zone_name,delivery_fee,subtotal,total,payment_method,notes)
  values(v_code,payload->>'customer_name',payload->>'customer_phone',coalesce(payload->>'delivery_type','delivery'),payload->>'address',payload->>'number',payload->>'complement',case when payload->>'delivery_type'='pickup' then null else v_zone.id end,case when payload->>'delivery_type'='pickup' then null else v_zone.name end,v_fee,v_subtotal,v_total,coalesce(payload->>'payment_method','Não informado'),payload->>'notes') returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    v_qty := greatest(1, least(50, (v_item->>'quantity')::int));
    select id,name,price,options into v_product from public.products where id=(v_item->>'product_id')::uuid;
    v_opt := public.resolve_item_options(v_product.options, v_item->'options');
    v_txt := nullif(concat_ws(' | ', nullif(v_opt->>'text',''), case when coalesce(trim(v_item->>'notes'),'')<>'' then 'Obs: '||left(trim(v_item->>'notes'),200) end),'');
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price,options_text) values(v_order_id,v_product.id,v_product.name,v_qty,v_product.price+(v_opt->>'extra')::numeric,v_txt);
  end loop;
  return jsonb_build_object('order_id',v_order_id,'order_code',v_code,'subtotal',v_subtotal,'delivery_fee',v_fee,'total',v_total);
end $$;

grant execute on function public.create_public_order(jsonb) to anon,authenticated;


-- FIM: opcoes-pedido.sql




-- ============================================================
-- INÍCIO: avaliacoes.sql
-- ============================================================
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

-- FIM: avaliacoes.sql


-- ============================================================
-- INÍCIO: sem-retirada.sql
-- ============================================================
-- Desativa a retirada no local também no banco (o site só aceita entrega). Rode no SQL Editor do Supabase.
update public.store_settings set allow_pickup=false;

-- FIM: sem-retirada.sql


-- ============================================================
-- INÍCIO: CORRECAO-FINAL-PEDIDO.sql
-- ============================================================
-- CORREÇÃO FINAL DO PEDIDO. Rode este arquivo inteiro no Supabase > SQL Editor (uma vez, mesmo que já tenha rodado os outros).
-- Corrige: erro "gen_random_bytes does not exist" ao finalizar o pedido; código de pedido repetido; exige conta para pedir.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create or replace function public.resolve_item_options(p_opts jsonb, p_sel jsonb)
returns jsonb language plpgsql stable as $$
declare
  g jsonb; it jsonb; n text;
  v_names text[]; v_lbl text[]; v_parts text[] := '{}';
  v_extra numeric := 0; v_cnt int; v_price numeric;
begin
  if p_opts is null or jsonb_typeof(p_opts) <> 'array' then
    return jsonb_build_object('extra',0,'text','');
  end if;
  for g in select value from jsonb_array_elements(p_opts) loop
    v_names := array(select jsonb_array_elements_text(coalesce(p_sel->(g->>'name'),'[]'::jsonb)));
    v_cnt := coalesce(array_length(v_names,1),0);
    if v_cnt <> (select count(distinct x) from unnest(v_names) x) then raise exception 'Opção repetida em "%"', g->>'name'; end if;
    if v_cnt > coalesce((g->>'max')::int,1) then raise exception 'Máximo de % item(ns) em "%"', g->>'max', g->>'name'; end if;
    if v_cnt < coalesce((g->>'min')::int,0) then raise exception 'Escolha pelo menos % item(ns) em "%"', g->>'min', g->>'name'; end if;
    v_lbl := '{}';
    foreach n in array v_names loop
      select value into it from jsonb_array_elements(g->'items') where value->>'name' = n limit 1;
      if it is null then raise exception 'Opção inválida em "%": %', g->>'name', n; end if;
      v_price := coalesce((it->>'price')::numeric,0);
      v_extra := v_extra + v_price;
      v_lbl := v_lbl || (n || case when v_price > 0 then ' (+R$ ' || replace(to_char(v_price,'FM999990.00'),'.',',') || ')' else '' end);
    end loop;
    if v_cnt > 0 then v_parts := v_parts || ((g->>'name') || ': ' || array_to_string(v_lbl,', ')); end if;
  end loop;
  return jsonb_build_object('extra',v_extra,'text',array_to_string(v_parts,' | '));
end $$;

create or replace function public.create_public_order(payload jsonb)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare
  v_order_id uuid;
  v_code text;
  v_subtotal numeric(10,2):=0;
  v_fee numeric(10,2):=0;
  v_total numeric(10,2):=0;
  v_zone record;
  v_item jsonb;
  v_product record;
  v_qty integer;
  v_settings record;
  v_opt jsonb;
  v_txt text;
begin
  -- Só clientes com conta fazem pedido (o site usa REQUIRE_LOGIN = true). Para permitir pedido sem conta, apague as 3 linhas abaixo.
  if auth.uid() is null then raise exception 'Entre na sua conta para fazer o pedido.'; end if;
  if not public.store_is_open() then raise exception 'Loja fechada. Atendemos todos os dias, das 18h às 03h.'; end if;
  select * into v_settings from public.store_settings limit 1;
  if payload->>'customer_name' is null or payload->>'customer_phone' is null then raise exception 'Nome e telefone são obrigatórios'; end if;
  if jsonb_array_length(coalesce(payload->'items','[]'::jsonb))=0 then raise exception 'Carrinho vazio'; end if;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    v_qty := greatest(1, least(50, (v_item->>'quantity')::int));
    select id,name,price,active,options into v_product from public.products where id=(v_item->>'product_id')::uuid;
    if v_product.id is null or not v_product.active then raise exception 'Produto indisponível'; end if;
    v_opt := public.resolve_item_options(v_product.options, v_item->'options');
    v_subtotal := v_subtotal + ((v_product.price + (v_opt->>'extra')::numeric) * v_qty);
  end loop;

  if coalesce(payload->>'delivery_type','delivery')='delivery' then
    select * into v_zone from public.delivery_zones where id=(payload->>'delivery_zone_id')::uuid and active=true;
    if v_zone.id is null then raise exception 'Região de entrega inválida'; end if;
    if v_subtotal < greatest(coalesce(v_zone.minimum_order,0),coalesce(v_settings.minimum_order,0)) then raise exception 'Pedido abaixo do mínimo'; end if;
    v_fee := v_zone.fee;
  else
    if not coalesce(v_settings.allow_pickup,true) then raise exception 'Retirada desativada'; end if;
  end if;

  v_total := v_subtotal + v_fee;
  loop
    v_code := 'PL-' || upper(substr(encode(extensions.gen_random_bytes(4),'hex'),1,6));
    exit when not exists(select 1 from public.orders where order_code=v_code);
  end loop;

  insert into public.orders(order_code,customer_name,customer_phone,delivery_type,address,number,complement,delivery_zone_id,delivery_zone_name,delivery_fee,subtotal,total,payment_method,notes)
  values(v_code,payload->>'customer_name',payload->>'customer_phone',coalesce(payload->>'delivery_type','delivery'),payload->>'address',payload->>'number',payload->>'complement',case when payload->>'delivery_type'='pickup' then null else v_zone.id end,case when payload->>'delivery_type'='pickup' then null else v_zone.name end,v_fee,v_subtotal,v_total,coalesce(payload->>'payment_method','Não informado'),payload->>'notes') returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    v_qty := greatest(1, least(50, (v_item->>'quantity')::int));
    select id,name,price,options into v_product from public.products where id=(v_item->>'product_id')::uuid;
    v_opt := public.resolve_item_options(v_product.options, v_item->'options');
    v_txt := nullif(concat_ws(' | ', nullif(v_opt->>'text',''), case when coalesce(trim(v_item->>'notes'),'')<>'' then 'Obs: '||left(trim(v_item->>'notes'),200) end),'');
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price,options_text) values(v_order_id,v_product.id,v_product.name,v_qty,v_product.price+(v_opt->>'extra')::numeric,v_txt);
  end loop;
  return jsonb_build_object('order_id',v_order_id,'order_code',v_code,'subtotal',v_subtotal,'delivery_fee',v_fee,'total',v_total);
end $$;

grant execute on function public.create_public_order(jsonb) to anon,authenticated;

-- FIM: CORRECAO-FINAL-PEDIDO.sql

-- Fotos dos produtos: bucket público 'produtos'; só o administrador envia/troca/apaga.
insert into storage.buckets (id,name,public) values ('produtos','produtos',true) on conflict (id) do update set public=true;
drop policy if exists "produtos leitura publica" on storage.objects;
drop policy if exists "produtos admin insere" on storage.objects;
drop policy if exists "produtos admin altera" on storage.objects;
drop policy if exists "produtos admin apaga" on storage.objects;
create policy "produtos leitura publica" on storage.objects for select using (bucket_id='produtos');
create policy "produtos admin insere" on storage.objects for insert to authenticated with check (bucket_id='produtos' and public.is_admin());
create policy "produtos admin altera" on storage.objects for update to authenticated using (bucket_id='produtos' and public.is_admin()) with check (bucket_id='produtos' and public.is_admin());
create policy "produtos admin apaga" on storage.objects for delete to authenticated using (bucket_id='produtos' and public.is_admin());
