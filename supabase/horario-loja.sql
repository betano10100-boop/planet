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
