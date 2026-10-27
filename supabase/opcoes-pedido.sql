-- Opções ao pedir (coluna de opções nos produtos + validação no pedido)
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

