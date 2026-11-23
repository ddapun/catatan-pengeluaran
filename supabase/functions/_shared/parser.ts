// Parser pesan WhatsApp. Murni tanpa dependensi agar bisa diuji dengan
// `node --test` maupun dijalankan di Supabase Edge Functions (Deno).

export type TxType = 'expense' | 'income';

export type ParseOk = {
  ok: true;
  type: TxType;
  amount: number;
  note: string;
  categoryHint: string | null;
};

export type ParseFail = {
  ok: false;
  reason: 'empty' | 'no_amount' | 'ambiguous';
  type: TxType;
  amount: number | null;
  note: string;
};

export type ParseResult = ParseOk | ParseFail;

export type Command = 'batal' | 'rekap' | 'sisa' | 'bantuan' | null;

/** Kata kunci kategori bawaan. Kunci = nama kategori. */
export const CATEGORY_KEYWORDS: Record<string, string[]> = {
  Makan: [
    'makan', 'sarapan', 'brunch', 'kopi', 'nasi', 'ayam', 'bakso', 'mie', 'soto',
    'resto', 'restoran', 'warung', 'jajan', 'snack', 'camilan', 'minum', 'cafe',
    'kafe', 'gofood', 'grabfood', 'shopeefood', 'es', 'teh', 'roti', 'kue',
  ],
  Transport: [
    'ojek', 'gojek', 'grab', 'bensin', 'bbm', 'parkir', 'tol', 'bus', 'kereta',
    'krl', 'mrt', 'lrt', 'taksi', 'taxi', 'ongkos', 'transport', 'angkot', 'travel',
  ],
  Belanja: [
    'belanja', 'beli', 'supermarket', 'indomaret', 'alfamart', 'shopee',
    'tokopedia', 'lazada', 'baju', 'sepatu', 'celana', 'pasar', 'groceries',
    'sembako', 'sabun', 'shampoo', 'odol',
  ],
  Tagihan: [
    'listrik', 'token', 'air', 'internet', 'wifi', 'pulsa', 'kuota', 'tagihan',
    'bpjs', 'sewa', 'kos', 'kontrakan', 'langganan', 'netflix', 'spotify',
    'youtube', 'icloud', 'google one',
  ],
  Kesehatan: [
    'obat', 'dokter', 'klinik', 'rumah sakit', 'rs', 'vitamin', 'apotek',
    'kesehatan', 'periksa', 'gym', 'olahraga',
  ],
  Hiburan: [
    'nonton', 'bioskop', 'film', 'game', 'konser', 'liburan', 'hiburan',
    'rekreasi', 'wisata', 'karaoke',
  ],
};

const INCOME_WORDS = [
  'gaji', 'masuk', 'terima', 'diterima', 'pemasukan', 'bonus', 'thr', 'fee',
  'honor', 'pendapatan', 'refund', 'cashback', 'dividen', 'bunga',
];

const COMMANDS: Record<string, Command> = {
  batal: 'batal',
  undo: 'batal',
  rekap: 'rekap',
  sisa: 'sisa',
  bantuan: 'bantuan',
  help: 'bantuan',
  menu: 'bantuan',
};

const AMOUNT_WITH_UNIT =
  /(?:rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d+(?:[.,]\d+)?)\s*(jt|juta|rb|ribu|k)\b/gi;
const AMOUNT_PLAIN = /(?:rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d+)/gi;

function toNumber(raw: string, hasUnit: boolean): number {
  if (!/[.,]/.test(raw)) return Number(raw);
  const last = Math.max(raw.lastIndexOf('.'), raw.lastIndexOf(','));
  const decimals = raw.length - last - 1;
  if (!hasUnit && decimals === 3) return Number(raw.replace(/[.,]/g, ''));
  const intPart = raw.slice(0, last).replace(/[.,]/g, '');
  return Number(`${intPart}.${raw.slice(last + 1)}`);
}

/** Mengembalikan jumlah dalam Rupiah bulat, atau null bila tidak ada angka. */
export function parseAmount(text: string): number | null {
  let best: number | null = null;
  for (const m of text.matchAll(AMOUNT_WITH_UNIT)) {
    const unit = m[2].toLowerCase();
    const multiplier = unit === 'jt' || unit === 'juta' ? 1_000_000 : 1_000;
    const value = Math.round(toNumber(m[1], true) * multiplier);
    if (value > 0 && (best === null || value > best)) best = value;
  }
  if (best !== null) return best;

  for (const m of text.matchAll(AMOUNT_PLAIN)) {
    const value = Math.round(toNumber(m[1], false));
    if (value > 0 && (best === null || value > best)) best = value;
  }
  return best;
}

export function detectCommand(text: string): Command {
  const word = text.trim().toLowerCase().replace(/[!.]/g, '').trim();
  return COMMANDS[word] ?? null;
}

export function detectType(text: string): TxType {
  const lower = text.toLowerCase();
  return INCOME_WORDS.some((w) => new RegExp(`\\b${w}\\b`).test(lower))
    ? 'income'
    : 'expense';
}

/** Nama kategori bawaan yang paling cocok, atau null bila ambigu. */
export function detectCategory(text: string, type: TxType): string | null {
  const lower = text.toLowerCase();
  if (type === 'income') {
    const isSalary = ['gaji', 'bonus', 'thr', 'honor', 'fee', 'pendapatan'].some(
      (w) => lower.includes(w),
    );
    return isSalary ? 'Gaji' : 'Lainnya';
  }
  let best: { name: string; index: number } | null = null;
  for (const [name, words] of Object.entries(CATEGORY_KEYWORDS)) {
    for (const word of words) {
      const index = lower.indexOf(word);
      if (index === -1) continue;
      if (best === null || index < best.index) best = { name, index };
    }
  }
  return best?.name ?? null;
}

function buildNote(text: string, amountMatch: string | undefined, fallback: string): string {
  let note = amountMatch ? text.replace(amountMatch, ' ') : text;
  note = note.replace(/\s+/g, ' ').replace(/^[\s,.;:-]+|[\s,.;:-]+$/g, '').trim();
  if (!note) note = fallback;
  note = note.charAt(0).toUpperCase() + note.slice(1);
  return note.slice(0, 120);
}

export function parseMessage(text: string): ParseResult {
  const clean = text.trim();
  if (!clean) {
    return { ok: false, reason: 'empty', type: 'expense', amount: null, note: '' };
  }

  const type = detectType(clean);
  const amount = parseAmount(clean);
  const categoryHint = detectCategory(clean, type);
  const amountMatch =
    clean.match(AMOUNT_WITH_UNIT)?.[0] ?? clean.match(AMOUNT_PLAIN)?.[0];
  const note = buildNote(clean, amountMatch, categoryHint ?? 'Transaksi');

  if (amount === null) {
    return { ok: false, reason: 'no_amount', type, amount: null, note };
  }
  if (type === 'expense' && categoryHint === null) {
    return { ok: false, reason: 'ambiguous', type, amount, note };
  }
  return { ok: true, type, amount, note, categoryHint };
}

/** Format Rupiah untuk balasan bot. */
export function formatRupiah(value: number): string {
  return `Rp ${value.toLocaleString('id-ID')}`;
}
