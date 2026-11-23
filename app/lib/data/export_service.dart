import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import 'repository.dart';

class ExportService {
  ExportService(this.repo);

  final ExpenseRepository repo;

  Future<String> buildCsv(DateTime month) async {
    final rows =
        await repo.transactionsBetween(month.monthStart, month.monthEnd);
    final buffer = StringBuffer('\uFEFFTanggal,Jenis,Kategori,Catatan,Jumlah,Sumber\r\n');
    for (final row in rows) {
      final values = [
        isoDate(row.tx.occurredOn),
        row.tx.type == 'expense' ? 'Pengeluaran' : 'Pemasukan',
        row.categoryName,
        row.tx.note ?? '',
        row.tx.amount.toString(),
        row.tx.source,
      ];
      buffer.writeln(values.map(_csvField).join(','));
    }
    return buffer.toString();
  }

  Future<void> shareCsv(DateTime month) async {
    final bytes = Uint8List.fromList(utf8.encode(await buildCsv(month)));
    final name = 'catatan-${fileStamp(month)}.csv';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, mimeType: 'text/csv', name: name),
        ],
        // XFile.fromData mengabaikan `name` di Android/iOS.
        fileNameOverrides: [name],
        subject: 'Catatan pengeluaran ${monthLabel(month)}',
      ),
    );
  }

  Future<Uint8List> buildPdf(DateTime month) async {
    final summary = await repo.summaryFor(month);
    final rows =
        await repo.transactionsBetween(month.monthStart, month.monthEnd);
    final doc = pw.Document(title: 'Laporan ${monthLabel(month)}');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Halaman ${context.pageNumber} dari ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.Text(
            'Laporan ${monthLabel(month)}',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Catatan Pengeluaran',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            children: [
              _summaryBox('Pengeluaran', rupiah(summary.expense)),
              pw.SizedBox(width: 10),
              _summaryBox('Pemasukan', rupiah(summary.income)),
              pw.SizedBox(width: 10),
              _summaryBox('Sisa', rupiah(summary.balance)),
            ],
          ),
          pw.SizedBox(height: 22),
          if (summary.byCategory.isNotEmpty) ...[
            pw.Text(
              'Pengeluaran per kategori',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FixedColumnWidth(90),
                2: const pw.FixedColumnWidth(55),
              },
              children: [
                _headerRow(['Kategori', 'Jumlah', 'Proporsi']),
                for (final item in summary.byCategory)
                  pw.TableRow(
                    children: [
                      _cell(item.name),
                      _cell(rupiah(item.total), align: pw.TextAlign.right),
                      _cell(
                        summary.expense == 0
                            ? '0%'
                            : '${(item.total * 100 / summary.expense).round()}%',
                        align: pw.TextAlign.right,
                      ),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 22),
          ],
          pw.Text(
            'Daftar transaksi',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            columnWidths: {
              0: const pw.FixedColumnWidth(48),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FixedColumnWidth(80),
            },
            children: [
              _headerRow(['Tanggal', 'Catatan', 'Kategori', 'Jumlah']),
              for (final row in rows)
                pw.TableRow(
                  children: [
                    _cell(_shortDate(row.tx.occurredOn)),
                    _cell(row.tx.note ?? '-'),
                    _cell(row.categoryName),
                    _cell(
                      '${row.tx.type == 'expense' ? '-' : '+'}${thousands(row.tx.amount)}',
                      align: pw.TextAlign.right,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  Future<void> sharePdf(DateTime month) async {
    final bytes = await buildPdf(month);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'laporan-${fileStamp(month)}.pdf',
    );
  }

  pw.Widget _summaryBox(String label, String value) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.TableRow _headerRow(List<String> labels) {
    return pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        for (var i = 0; i < labels.length; i++)
          _cell(
            labels[i],
            bold: true,
            align: i == labels.length - 1
                ? pw.TextAlign.right
                : pw.TextAlign.left,
          ),
      ],
    );
  }

  pw.Widget _cell(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

  String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
