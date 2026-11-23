// Webhook WhatsApp Cloud API (Meta).
// Alur: pesan -> verifikasi tanda tangan -> cocokkan nomor -> parser -> simpan -> balas.
//
// Rahasia (set lewat `supabase secrets set`):
//   WA_VERIFY_TOKEN, WA_APP_SECRET, WA_TOKEN, WA_PHONE_ID
//   SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY sudah tersedia otomatis.
//
// Deploy: supabase functions deploy whatsapp-webhook --no-verify-jwt

import { createClient } from 'npm:@supabase/supabase-js@2';
import {
  detectCommand,
  formatRupiah,
  parseMessage,
  type ParseOk,
} from '../_shared/parser.ts';

const GRAPH = 'https://graph.facebook.com/v21.0';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

type WaLink = {
  user_id: string;
  phone_e164: string;
  verified_at: string | null;
  verify_code: string | null;
  verify_expires_at: string | null;
  pending: Pending | null;
};

type Pending = {
  type: 'expense' | 'income';
  amount: number;
  note: string;
  options: Array<{ id: string; name: string }>;
};

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === 'GET') {
    const url = new URL(req.url);
    const ok =
      url.searchParams.get('hub.mode') === 'subscribe' &&
      url.searchParams.get('hub.verify_token') === Deno.env.get('WA_VERIFY_TOKEN');
    return ok
      ? new Response(url.searchParams.get('hub.challenge') ?? '', { status: 200 })
      : new Response('Forbidden', { status: 403 });
  }

  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const raw = await req.text();
  if (!(await validSignature(raw, req.headers.get('x-hub-signature-256')))) {
    return new Response('Invalid signature', { status: 401 });
  }

  try {
    await handlePayload(JSON.parse(raw));
  } catch (error) {
    console.error('whatsapp-webhook', error);
  }
  // Selalu 200 agar Meta tidak mengirim ulang pesan yang sudah diproses.
  return new Response('ok', { status: 200 });
});

async function validSignature(raw: string, header: string | null): Promise<boolean> {
  const secret = Deno.env.get('WA_APP_SECRET');
  if (!secret) return false;
  if (!header?.startsWith('sha256=')) return false;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const digest = new Uint8Array(
    await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(raw)),
  );
  const expected = [...digest].map((b) => b.toString(16).padStart(2, '0')).join('');
  return timingSafeEqual(header.slice(7), expected);
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ---------------------------------------------------------------------------
// Penanganan pesan
// ---------------------------------------------------------------------------

async function handlePayload(payload: any): Promise<void> {
  const value = payload?.entry?.[0]?.changes?.[0]?.value;
  const message = value?.messages?.[0];
  if (!message || message.type !== 'text') return;

  const from: string = message.from; // contoh: 6281234567890
  const text: string = message.text?.body ?? '';
  const phone = `+${from}`;

  const { data: link } = await supabase
    .from('wa_links')
    .select('*')
    .eq('phone_e164', phone)
    .maybeSingle<WaLink>();

  // FR-76: nomor yang belum tertaut diabaikan sepenuhnya.
  if (!link) return;

  if (!link.verified_at) {
    await verifyLink(link, text);
    return;
  }

  await reply(from, await handleMessage(link, text.trim()));
}

async function verifyLink(link: WaLink, text: string): Promise<void> {
  const code = text.trim();
  const expired =
    !link.verify_expires_at || new Date(link.verify_expires_at).getTime() < Date.now();
  if (code !== link.verify_code || expired) return; // kode salah: abaikan

  await supabase
    .from('wa_links')
    .update({ verified_at: new Date().toISOString(), verify_code: null, pending: null })
    .eq('user_id', link.user_id);

  await reply(
    link.phone_e164.slice(1),
    'Nomor berhasil ditautkan. Kirim catatan seperti "makan siang 25rb".\n' +
      'Perintah: rekap, sisa, batal, bantuan.',
  );
}

async function handleMessage(link: WaLink, text: string): Promise<string> {
  const command = detectCommand(text);

  if (command === 'bantuan') {
    return (
      'Contoh:\n' +
      '- makan siang 25rb\n' +
      '- ojek 18k\n' +
      '- gaji 6jt masuk\n' +
      'Perintah: rekap, sisa, batal.'
    );
  }

  if (command === 'batal') {
    await supabase
      .from('wa_links')
      .update({ pending: null })
      .eq('user_id', link.user_id);
    return undoLast(link.user_id);
  }

  if (command === 'rekap') return recap(link.user_id);
  if (command === 'sisa') return remaining(link.user_id);

  // Balasan nomor untuk kategori yang sebelumnya ambigu.
  if (link.pending && /^\d{1,2}$/.test(text)) {
    const choice = link.pending.options[Number(text) - 1];
    if (!choice) return 'Pilihan tidak ada. Balas angka sesuai daftar, atau "batal".';
    const saved = await saveTransaction(link.user_id, {
      ok: true,
      type: link.pending.type,
      amount: link.pending.amount,
      note: link.pending.note,
      categoryHint: choice.name,
    }, choice.id);
    await supabase.from('wa_links').update({ pending: null }).eq('user_id', link.user_id);
    return saved;
  }

  const parsed = parseMessage(text);

  if (parsed.reason === 'no_amount') {
    return 'Jumlahnya belum terbaca. Contoh: "makan siang 25rb".';
  }

  if (parsed.reason === 'ambiguous') {
    const options = await categoryOptions(link.user_id);
    if (options.length === 0) return 'Kategori belum tersedia. Buka aplikasi dulu, ya.';
    const pending: Pending = {
      type: parsed.type,
      amount: parsed.amount!,
      note: parsed.note,
      options,
    };
    await supabase.from('wa_links').update({ pending }).eq('user_id', link.user_id);
    const list = options.map((o, i) => `${i + 1}. ${o.name}`).join('\n');
    return `Kategori belum jelas untuk ${formatRupiah(parsed.amount!)}.\nBalas nomor:\n${list}`;
  }

  if (parsed.ok) return saveTransaction(link.user_id, parsed);
  return 'Pesan tidak dikenali. Kirim "bantuan" untuk contoh.';
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

async function categoryOptions(userId: string) {
  const { data } = await supabase
    .from('categories')
    .select('id, name')
    .eq('user_id', userId)
    .eq('type', 'expense')
    .is('deleted_at', null)
    .is('archived_at', null)
    .order('name')
    .limit(6);
  return data ?? [];
}

async function categoryId(userId: string, name: string, type: 'expense' | 'income') {
  const { data } = await supabase
    .from('categories')
    .select('id')
    .eq('user_id', userId)
    .eq('type', type)
    .eq('name', name)
    .is('deleted_at', null)
    .maybeSingle();
  if (data) return data.id as string;

  const id = crypto.randomUUID();
  await supabase.from('categories').insert({
    id,
    user_id: userId,
    name,
    type,
    color: '#1F6F5C',
    icon: 'tag',
  });
  return id;
}

async function saveTransaction(userId: string, parsed: ParseOk, fixedCategoryId?: string): Promise<string> {
  const catId = fixedCategoryId ?? (await categoryId(userId, parsed.categoryHint ?? 'Lainnya', parsed.type));
  const today = jakartaDate();
  const { error } = await supabase.from('transactions').insert({
    id: crypto.randomUUID(),
    user_id: userId,
    type: parsed.type,
    amount: parsed.amount,
    category_id: catId,
    note: parsed.note,
    occurred_on: today,
    source: 'whatsapp',
  });
  if (error) {
    console.error('insert transaction', error);
    return 'Gagal menyimpan. Coba lagi sebentar.';
  }
  const kind = parsed.type === 'income' ? 'pemasukan' : 'pengeluaran';
  return (
    `Tercatat ${kind} ${formatRupiah(parsed.amount)} — ${parsed.note}.\n` +
    'Balas "batal" untuk menghapus.'
  );
}

async function undoLast(userId: string): Promise<string> {
  const { data } = await supabase
    .from('transactions')
    .select('id, amount, note')
    .eq('user_id', userId)
    .eq('source', 'whatsapp')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!data) return 'Tidak ada transaksi WhatsApp yang bisa dibatalkan.';

  await supabase
    .from('transactions')
    .update({ deleted_at: new Date().toISOString(), updated_at: new Date().toISOString() })
    .eq('id', data.id)
    .eq('user_id', userId);
  return `Dibatalkan: ${data.note ?? 'transaksi'} ${formatRupiah(Number(data.amount))}.`;
}

async function recap(userId: string): Promise<string> {
  const { start, end } = monthBounds();
  const { data } = await supabase
    .from('transactions')
    .select('type, amount, category_id, categories(name)')
    .eq('user_id', userId)
    .is('deleted_at', null)
    .gte('occurred_on', start)
    .lte('occurred_on', end);

  const rows = data ?? [];
  let expense = 0;
  let income = 0;
  const perCategory = new Map<string, number>();
  for (const row of rows) {
    const amount = Number(row.amount);
    if (row.type === 'income') income += amount;
    else {
      expense += amount;
      const name = (row as any).categories?.name ?? 'Lainnya';
      perCategory.set(name, (perCategory.get(name) ?? 0) + amount);
    }
  }
  if (rows.length === 0) return 'Belum ada transaksi bulan ini.';

  const top = [...perCategory.entries()].sort((a, b) => b[1] - a[1])[0];
  const label = new Date(`${start}T00:00:00+07:00`).toLocaleDateString('id-ID', {
    month: 'long',
    timeZone: 'Asia/Jakarta',
  });
  return (
    `${label}: keluar ${formatRupiah(expense)}, masuk ${formatRupiah(income)}.\n` +
    (top ? `Terbesar: ${top[0]} ${formatRupiah(top[1])}.` : '')
  );
}

async function remaining(userId: string): Promise<string> {
  const { start, end } = monthBounds();
  const { data: budgets } = await supabase
    .from('budgets')
    .select('category_id, limit_amount, categories(name)')
    .eq('user_id', userId)
    .eq('month', start);
  if (!budgets?.length) return 'Belum ada anggaran bulan ini. Atur di aplikasi.';

  const { data: spent } = await supabase
    .from('transactions')
    .select('category_id, amount')
    .eq('user_id', userId)
    .eq('type', 'expense')
    .is('deleted_at', null)
    .gte('occurred_on', start)
    .lte('occurred_on', end);

  const spentByCategory = new Map<string, number>();
  for (const row of spent ?? []) {
    spentByCategory.set(
      row.category_id,
      (spentByCategory.get(row.category_id) ?? 0) + Number(row.amount),
    );
  }

  const lines = budgets.map((b: any) => {
    const left = Number(b.limit_amount) - (spentByCategory.get(b.category_id) ?? 0);
    const name = b.categories?.name ?? 'Kategori';
    return left >= 0 ? `${name}: sisa ${formatRupiah(left)}` : `${name}: lewat ${formatRupiah(-left)}`;
  });
  return `Sisa anggaran:\n${lines.join('\n')}`;
}

// ---------------------------------------------------------------------------
// Utilitas
// ---------------------------------------------------------------------------

function jakartaDate(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jakarta' });
}

function monthBounds(): { start: string; end: string } {
  const today = jakartaDate();
  const start = `${today.slice(0, 7)}-01`;
  const d = new Date(`${start}T00:00:00Z`);
  d.setUTCMonth(d.getUTCMonth() + 1);
  d.setUTCDate(0);
  return { start, end: d.toISOString().slice(0, 10) };
}

async function reply(to: string, body: string): Promise<void> {
  const token = Deno.env.get('WA_TOKEN');
  const phoneId = Deno.env.get('WA_PHONE_ID');
  if (!token || !phoneId) {
    console.warn('WA_TOKEN/WA_PHONE_ID belum diatur; balasan tidak dikirim.');
    return;
  }
  const res = await fetch(`${GRAPH}/${phoneId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to,
      type: 'text',
      text: { body: body.slice(0, 4000) },
    }),
  });
  if (!res.ok) console.error('send message', res.status, await res.text());
}
