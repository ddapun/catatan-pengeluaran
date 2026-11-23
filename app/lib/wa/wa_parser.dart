/// Parser pesan WhatsApp (versi Dart untuk simulator di aplikasi).
/// Logika ini kembar dengan `supabase/functions/_shared/parser.ts`.
library;

import '../core/money_parser.dart';

const categoryKeywords = <String, List<String>>{
  'Makan': [
    'makan', 'sarapan', 'brunch', 'kopi', 'nasi', 'ayam', 'bakso', 'mie', 'soto',
    'resto', 'restoran', 'warung', 'jajan', 'snack', 'camilan', 'minum', 'cafe',
    'kafe', 'gofood', 'grabfood', 'shopeefood', 'es', 'teh', 'roti', 'kue',
  ],
  'Transport': [
    'ojek', 'gojek', 'grab', 'bensin', 'bbm', 'parkir', 'tol', 'bus', 'kereta',
    'krl', 'mrt', 'lrt', 'taksi', 'taxi', 'ongkos', 'transport', 'angkot', 'travel',
  ],
  'Belanja': [
    'belanja', 'beli', 'supermarket', 'indomaret', 'alfamart', 'shopee',
    'tokopedia', 'lazada', 'baju', 'sepatu', 'celana', 'pasar', 'groceries',
    'sembako', 'sabun', 'shampoo', 'odol',
  ],
  'Tagihan': [
    'listrik', 'token', 'air', 'internet', 'wifi', 'pulsa', 'kuota', 'tagihan',
    'bpjs', 'sewa', 'kos', 'kontrakan', 'langganan', 'netflix', 'spotify',
    'youtube', 'icloud', 'google one',
  ],
  'Kesehatan': [
    'obat', 'dokter', 'klinik', 'rumah sakit', 'rs', 'vitamin', 'apotek',
    'kesehatan', 'periksa', 'gym', 'olahraga',
  ],
  'Hiburan': [
    'nonton', 'bioskop', 'film', 'game', 'konser', 'liburan', 'hiburan',
    'rekreasi', 'wisata', 'karaoke',
  ],
};

const _incomeWords = [
  'gaji', 'masuk', 'terima', 'diterima', 'pemasukan', 'bonus', 'thr', 'fee',
  'honor', 'pendapatan', 'refund', 'cashback', 'dividen', 'bunga',
];

const _commands = <String, WaCommand>{
  'batal': WaCommand.batal,
  'undo': WaCommand.batal,
  'rekap': WaCommand.rekap,
  'sisa': WaCommand.sisa,
  'bantuan': WaCommand.bantuan,
  'help': WaCommand.bantuan,
  'menu': WaCommand.bantuan,
};

enum WaCommand { batal, rekap, sisa, bantuan }

enum WaFailReason { empty, noAmount, ambiguous }

class WaParseResult {
  const WaParseResult({
    required this.ok,
    required this.type,
    required this.amount,
    required this.note,
    this.categoryHint,
    this.reason,
  });

  final bool ok;
  final String type; // 'expense' | 'income'
  final int? amount;
  final String note;
  final String? categoryHint;
  final WaFailReason? reason;
}

WaCommand? detectWaCommand(String text) {
  final word = text.trim().toLowerCase().replaceAll(RegExp(r'[!.]'), '').trim();
  return _commands[word];
}

String detectType(String text) {
  final lower = text.toLowerCase();
  final isIncome = _incomeWords.any(
    (word) => RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(lower),
  );
  return isIncome ? 'income' : 'expense';
}

String? detectCategory(String text, String type) {
  final lower = text.toLowerCase();
  if (type == 'income') {
    const salaryWords = ['gaji', 'bonus', 'thr', 'honor', 'fee', 'pendapatan'];
    return salaryWords.any(lower.contains) ? 'Gaji' : 'Lainnya';
  }
  String? best;
  var bestIndex = 1 << 30;
  for (final entry in categoryKeywords.entries) {
    for (final word in entry.value) {
      final index = lower.indexOf(word);
      if (index != -1 && index < bestIndex) {
        bestIndex = index;
        best = entry.key;
      }
    }
  }
  return best;
}

final _amountWithUnit = RegExp(
  r'(?:rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d+(?:[.,]\d+)?)\s*(jt|juta|rb|ribu|k)\b',
  caseSensitive: false,
);
final _amountPlain =
    RegExp(r'(?:rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d+)', caseSensitive: false);

WaParseResult parseWaMessage(String text) {
  final clean = text.trim();
  if (clean.isEmpty) {
    return const WaParseResult(
      ok: false,
      type: 'expense',
      amount: null,
      note: '',
      reason: WaFailReason.empty,
    );
  }

  final type = detectType(clean);
  final amount = parseRupiah(clean);
  final categoryHint = detectCategory(clean, type);
  final amountMatch =
      _amountWithUnit.firstMatch(clean) ?? _amountPlain.firstMatch(clean);
  final note = _buildNote(
    clean,
    amountMatch?.group(0),
    categoryHint ?? 'Transaksi',
  );

  if (amount == null) {
    return WaParseResult(
      ok: false,
      type: type,
      amount: null,
      note: note,
      reason: WaFailReason.noAmount,
    );
  }
  if (type == 'expense' && categoryHint == null) {
    return WaParseResult(
      ok: false,
      type: type,
      amount: amount,
      note: note,
      reason: WaFailReason.ambiguous,
    );
  }
  return WaParseResult(
    ok: true,
    type: type,
    amount: amount,
    note: note,
    categoryHint: categoryHint,
  );
}

String _buildNote(String text, String? amountMatch, String fallback) {
  var note = amountMatch == null ? text : text.replaceFirst(amountMatch, ' ');
  note = note
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s,.;:-]+|[\s,.;:-]+$'), '')
      .trim();
  if (note.isEmpty) note = fallback;
  note = note[0].toUpperCase() + note.substring(1);
  return note.length > 120 ? note.substring(0, 120) : note;
}
