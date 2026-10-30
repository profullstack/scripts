// Read-only: reports capability and format counts, never opens or returns keys.
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
const paths = JSON.parse(readFileSync('/app/.next/server/app-paths-manifest.json', 'utf8'));
const operatorModule = existsSync('/app/src/lib/wallets/operator-keys.ts');
const operatorRoutes = Object.keys(paths).some((p) => p.includes('operator-vault'));
const db = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { global: { fetch: (url, init) => fetch(url, { ...init, signal: AbortSignal.timeout(15000) }) } });
const payments = [];
for (let from = 0; ; from += 500) {
  const { data, error } = await db.from('payments').select('id,status')
    .in('status', ['confirmed', 'forwarding', 'forwarding_failed'])
    .is('forwarded_at', null).is('forward_tx_hash', null)
    .order('id').range(from, from + 499);
  if (error) throw new Error('Could not read signing readiness');
  payments.push(...data);
  if (data.length < 500) break;
}
let sealed = 0;
for (let i = 0; i < payments.length; i += 100) {
  const { data, error } = await db.from('payment_addresses').select('encrypted_private_key').in('payment_id', payments.slice(i, i + 100).map((p) => p.id));
  if (error) throw new Error('Could not inspect signing formats');
  sealed += data.filter((p) => p.encrypted_private_key?.startsWith('cpv1.')).length;
}
console.log(JSON.stringify({ mode: operatorModule && operatorRoutes ? 'operator-vault' : !operatorModule && !operatorRoutes ? 'legacy' : 'inconsistent', sealedSigningRows: sealed, paymentsChecked: payments.length }));
