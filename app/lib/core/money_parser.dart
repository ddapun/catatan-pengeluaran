/// Parser jumlah gaya Indonesia: `25rb`, `25k`, `25.000`, `1,5jt`, `2jt`.
library;

final _withUnit = RegExp(
  r'(?:rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d+(?:[.,]\d+)?)\s*(jt|juta|rb|ribu|k)\b',
  caseSensitive: false,
);

final _plain = RegExp(r'(?:rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d+)',
    caseSensitive: false);

int? parseRupiah(String input) {
  int? best;

  for (final match in _withUnit.allMatches(input)) {
    final unit = match.group(2)!.toLowerCase();
    final multiplier = unit == 'jt' || unit == 'juta' ? 1000000 : 1000;
    final value = (_toNumber(match.group(1)!, hasUnit: true) * multiplier).round();
    if (value > 0 && (best == null || value > best)) best = value;
  }
  if (best != null) return best;

  for (final match in _plain.allMatches(input)) {
    final value = _toNumber(match.group(1)!, hasUnit: false).round();
    if (value > 0 && (best == null || value > best)) best = value;
  }
  return best;
}

double _toNumber(String raw, {required bool hasUnit}) {
  if (!raw.contains('.') && !raw.contains(',')) {
    return double.tryParse(raw) ?? 0;
  }
  final last = raw.lastIndexOf('.') > raw.lastIndexOf(',')
      ? raw.lastIndexOf('.')
      : raw.lastIndexOf(',');
  final decimals = raw.length - last - 1;
  if (!hasUnit && decimals == 3) {
    return double.tryParse(raw.replaceAll(RegExp(r'[.,]'), '')) ?? 0;
  }
  final intPart = raw.substring(0, last).replaceAll(RegExp(r'[.,]'), '');
  return double.tryParse('$intPart.${raw.substring(last + 1)}') ?? 0;
}
