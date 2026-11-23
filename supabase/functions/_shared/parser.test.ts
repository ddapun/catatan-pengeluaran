import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  detectCommand,
  formatRupiah,
  parseAmount,
  parseMessage,
} from './parser.ts';

test('format jumlah yang dikenali', () => {
  assert.equal(parseAmount('makan 25rb'), 25000);
  assert.equal(parseAmount('ojek 25k'), 25000);
  assert.equal(parseAmount('belanja 25.000'), 25000);
  assert.equal(parseAmount('gaji 1,5jt'), 1500000);
  assert.equal(parseAmount('bonus 2jt'), 2000000);
  assert.equal(parseAmount('bayar Rp 1.500.000'), 1500000);
  assert.equal(parseAmount('2 orang 50rb'), 50000);
  assert.equal(parseAmount('beli 2 baju 150000'), 150000);
  assert.equal(parseAmount('tanpa angka'), null);
});

test('pengeluaran dengan kategori jelas', () => {
  const r = parseMessage('makan siang 25rb');
  assert.equal(r.ok, true);
  assert.equal(r.type, 'expense');
  assert.equal(r.amount, 25000);
  assert.equal(r.categoryHint, 'Makan');
  assert.equal(r.note, 'Makan siang');
});

test('kata kunci tiap kategori', () => {
  const cases: Array<[string, string]> = [
    ['ojek ke kampus 18k', 'Transport'],
    ['beli baju 150.000', 'Belanja'],
    ['token listrik 300rb', 'Tagihan'],
    ['obat apotek 45rb', 'Kesehatan'],
    ['nonton bioskop 50k', 'Hiburan'],
    ['kopi 25rb', 'Makan'],
  ];
  for (const [message, category] of cases) {
    const r = parseMessage(message);
    assert.equal(r.ok, true, message);
    assert.equal(r.categoryHint, category, message);
  }
});

test('pemasukan', () => {
  const r = parseMessage('gaji 6jt masuk');
  assert.equal(r.ok, true);
  assert.equal(r.type, 'income');
  assert.equal(r.amount, 6000000);
  assert.equal(r.categoryHint, 'Gaji');
});

test('kategori ambigu dan tanpa jumlah', () => {
  const ambiguous = parseMessage('transfer 100rb');
  assert.equal(ambiguous.ok, false);
  assert.equal(ambiguous.reason, 'ambiguous');
  assert.equal(ambiguous.amount, 100000);

  const noAmount = parseMessage('makan siang');
  assert.equal(noAmount.ok, false);
  assert.equal(noAmount.reason, 'no_amount');
});

test('perintah', () => {
  assert.equal(detectCommand('batal'), 'batal');
  assert.equal(detectCommand(' Rekap! '), 'rekap');
  assert.equal(detectCommand('sisa'), 'sisa');
  assert.equal(detectCommand('help'), 'bantuan');
  assert.equal(detectCommand('makan 25rb'), null);
});

test('format rupiah', () => {
  assert.equal(formatRupiah(25000), 'Rp 25.000');
  assert.equal(formatRupiah(1500000), 'Rp 1.500.000');
});
