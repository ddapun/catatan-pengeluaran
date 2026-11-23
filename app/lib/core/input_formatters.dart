import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Memformat angka menjadi pemisah ribuan gaya Indonesia saat diketik.
/// [prefix] ikut ditampilkan di dalam nilai, mis. `Rp 25.000`.
class ThousandsInputFormatter extends TextInputFormatter {
  ThousandsInputFormatter({this.prefix = ''});

  final String prefix;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final text = '$prefix${NumberFormat.decimalPattern('id_ID').format(
      int.tryParse(digits) ?? 0,
    )}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
