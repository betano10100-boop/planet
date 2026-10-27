-- Correção do erro: function gen_random_bytes(integer) does not exist
-- Execute este arquivo inteiro no Supabase SQL Editor.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- Confirma que a função está disponível
select extensions.gen_random_bytes(4);

-- A função create_public_order do schema.sql já foi ajustada para usar
-- extensions.gen_random_bytes(4) e search_path=public, extensions.
