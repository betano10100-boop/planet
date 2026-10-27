-- Desativa a retirada no local também no banco (o site só aceita entrega). Rode no SQL Editor do Supabase.
update public.store_settings set allow_pickup=false;
