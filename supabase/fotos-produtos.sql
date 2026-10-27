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
