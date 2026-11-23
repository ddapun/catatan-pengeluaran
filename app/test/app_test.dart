import 'package:flutter_test/flutter_test.dart';

import 'package:catatan_pengeluaran/core/money_parser.dart';
import 'package:catatan_pengeluaran/wa/wa_parser.dart';

void main() {
  test('parser jumlah Indonesia', () {
    expect(parseRupiah('25rb'), 25000);
    expect(parseRupiah('25k'), 25000);
    expect(parseRupiah('25.000'), 25000);
    expect(parseRupiah('1,5jt'), 1500000);
    expect(parseRupiah('2jt'), 2000000);
    expect(parseRupiah('bayar Rp 1.500.000'), 1500000);
    expect(parseRupiah('2 orang 50rb'), 50000);
    expect(parseRupiah('beli 2 baju 150000'), 150000);
    expect(parseRupiah('tanpa angka'), isNull);
  });

  test('pesan pengeluaran dengan kategori', () {
    final result = parseWaMessage('makan siang 25rb');
    expect(result.ok, isTrue);
    expect(result.type, 'expense');
    expect(result.amount, 25000);
    expect(result.categoryHint, 'Makan');
    expect(result.note, 'Makan siang');
  });

  test('kata kunci kategori', () {
    const cases = {
      'ojek ke kampus 18k': 'Transport',
      'beli baju 150.000': 'Belanja',
      'token listrik 300rb': 'Tagihan',
      'obat apotek 45rb': 'Kesehatan',
      'nonton bioskop 50k': 'Hiburan',
    };
    for (final entry in cases.entries) {
      final result = parseWaMessage(entry.key);
      expect(result.ok, isTrue, reason: entry.key);
      expect(result.categoryHint, entry.value, reason: entry.key);
    }
  });

  test('pemasukan dan perintah', () {
    final income = parseWaMessage('gaji 6jt masuk');
    expect(income.ok, isTrue);
    expect(income.type, 'income');
    expect(income.amount, 6000000);
    expect(income.categoryHint, 'Gaji');

    expect(detectWaCommand('batal'), WaCommand.batal);
    expect(detectWaCommand(' Rekap! '), WaCommand.rekap);
    expect(detectWaCommand('makan 25rb'), isNull);
  });

  test('kategori ambigu dan tanpa jumlah', () {
    final ambiguous = parseWaMessage('transfer 100rb');
    expect(ambiguous.ok, isFalse);
    expect(ambiguous.reason, WaFailReason.ambiguous);
    expect(ambiguous.amount, 100000);

    final noAmount = parseWaMessage('makan siang');
    expect(noAmount.ok, isFalse);
    expect(noAmount.reason, WaFailReason.noAmount);
  });
}
