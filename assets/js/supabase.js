import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

const url = String(SUPABASE_URL || '').trim();
const key = String(SUPABASE_ANON_KEY || '').trim();
const validUrl = /^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(url);
const validKey = key.length > 20 && !/^COLE_/i.test(key);
export const isConfigured = validUrl && validKey;
export const supabase = isConfigured ? createClient(url.replace(/\/$/, ''), key, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
}) : null;
export const brl = value => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(Number(value || 0));
