import 'package:intl/intl.dart';

final _thousands = NumberFormat.decimalPattern('id_ID');
final _month = DateFormat('MMMM yyyy', 'id_ID');
final _shortDate = DateFormat('d MMM', 'id_ID');
final _fullDate = DateFormat('d MMM yyyy', 'id_ID');
final _weekday = DateFormat('EEEE, d MMM', 'id_ID');

/// Rupiah tanpa desimal, contoh: `Rp 25.000`.
String rupiah(int value) => 'Rp ${_thousands.format(value)}';

/// Angka tanpa simbol, contoh: `25.000`.
String thousands(int value) => _thousands.format(value);

/// Label bulan, contoh: `November 2026`.
String monthLabel(DateTime date) => _month.format(date);

/// Nama bulan saja, contoh: `November`.
String monthName(DateTime date) => DateFormat('MMMM', 'id_ID').format(date);

/// `Hari ini, 22 Nov`, `Kemarin, 21 Nov`, atau `22 Nov 2026`.
String dateLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hari ini, ${_shortDate.format(day)}';
  if (diff == 1) return 'Kemarin, ${_shortDate.format(day)}';
  if (day.year == now.year) return _shortDate.format(day);
  return _fullDate.format(day);
}

/// `Sabtu, 22 Nov` untuk header riwayat.
String weekdayLabel(DateTime date) => _weekday.format(date);

/// Tanggal untuk ekspor, contoh: `2026-11-22`.
String isoDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

/// Nama berkas, contoh: `laporan-2026-11`.
String fileStamp(DateTime month) => DateFormat('yyyy-MM').format(month);

extension DateX on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);

  DateTime get monthStart => DateTime(year, month);

  DateTime get monthEnd => DateTime(year, month + 1, 0);

  DateTime get nextMonth => DateTime(year, month + 1);

  DateTime get prevMonth => DateTime(year, month - 1);

  bool sameMonth(DateTime other) => year == other.year && month == other.month;

  bool sameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;
}
