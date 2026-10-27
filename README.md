# Planet das Galáxias — Site + Painel Admin + Supabase

Site de delivery (cardápio, carrinho, cadastro de clientes, pedidos, avaliações) e painel administrativo (`admin.html`).
Site estático: não precisa de build. Os dados ficam no Supabase.

## 1. Criar o seu projeto no Supabase
1. Crie um projeto em supabase.com (use um projeto novo, só deste site).
2. Em **Project Settings > API**, copie a **Project URL** e a chave **publishable/anon**.
3. Cole as duas em `assets/js/config.js` (`SUPABASE_URL` e `SUPABASE_ANON_KEY`). Nunca coloque a `service_role` nesse arquivo.

## 2. Banco de dados
No **SQL Editor > New query**, rode:
1. `supabase/00-SETUP-COMPLETO.sql` — cria tudo (tabelas, segurança, pedidos, avaliações, horário 18h–03h) e já cadastra o cardápio.
2. `supabase/fotos-produtos.sql` — libera o envio de fotos dos produtos pelo painel.

Em **Authentication > Providers > Email**, desligue **Confirm email**.

## 3. Criar o administrador
Login do painel: `planet` (e-mail interno `planet@admin.planet.local`).

**Opção A (sem terminal):** abra `supabase/criar-admin-planet.sql`, troque `DEFINA_SUA_SENHA_AQUI` pela senha que você quer e rode no SQL Editor.

**Opção B (terminal, com Node):** `SUPABASE_URL="..." SUPABASE_SERVICE_ROLE_KEY="..." ADMIN_PASSWORD="sua-senha-forte" node setup-admin.mjs`

## 4. Dados da loja
Em `assets/js/config.js`: WhatsApp (`STORE_WHATSAPP`, com 55 + DDD), telefone exibido e horário. Link do Instagram e demais textos ficam em `index.html`.
Pelo painel (Configurações) você edita nome, telefone, horário, formas de pagamento e taxas por bairro.

## 5. Publicar
Suba todos os arquivos para uma hospedagem estática (Netlify, Vercel, GitHub Pages, Cloudflare Pages). O painel fica em `/admin.html`.

## Estado da configuração
O código do cliente Supabase e as verificações de configuração já estão preparados. Para conectar ao seu banco real, ainda é necessário inserir a Project URL e a chave publishable/anon do seu projeto em `assets/js/config.js`; esses dados não vieram junto com o ZIP. A chave `service_role` nunca deve ser colocada no frontend.

## Teste rápido
Abra o site, crie uma conta, faça um pedido, entre em `admin.html` com `planet` e a sua senha e confira o pedido.

## Observações
- `supabase/cardapio-planet.sql` recadastra o cardápio num banco que já esteja em uso (desativa os produtos antigos).
- Os pedidos só são aceitos no horário de funcionamento (18h às 03h, horário de Brasília).
