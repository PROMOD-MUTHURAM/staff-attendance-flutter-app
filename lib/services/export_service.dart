import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';
import 'package:file_saver/file_saver.dart';

class ExportService {
  static final FileSaver _fileSaver =
      FileSaver.instance;

  // ============================================================
  // EXACT EXCEL / CSV COLUMNS
  // ============================================================

  static const List<String> _headers = [
    'Employee',
    'Designation',
    'Status',
    'Check In 1',
    'Check Out 1',
    'Check In 2',
    'Check Out 2',
    'QR Location',
    'Latitude',
    'Longitude',
    'Device',
    'OS',
  ];

  // ============================================================
  // CSV EXPORT
  // ============================================================

  static Future<void> exportCsv(
      List<Map<String, dynamic>> records,
      ) async {
    final rows = <List<String>>[];

    // Header row
    rows.add(_headers);

    // Data rows
    for (final data in records) {
      rows.add(_recordToRow(data));
    }

    final csv = rows
        .map(
          (row) => row
          .map(_escapeCsv)
          .join(','),
    )
        .join('\r\n');

    await _fileSaver.saveAs(
      name: 'attendance_export',
      bytes: Uint8List.fromList(
        utf8.encode(csv),
      ),
      fileExtension: 'csv',
      includeExtension: true,
      mimeType: MimeType.text,
      dialogTitle: 'Save Attendance CSV',
    );
  }

  // ============================================================
  // EXCEL EXPORT
  // ============================================================

  static Future<void> exportExcel(
      List<Map<String, dynamic>> records,
      ) async {
    final workbook =
    Excel.createExcel();

    final sheet =
    workbook['Attendance'];

    // ----------------------------------------------------------
    // HEADER ROW
    // ----------------------------------------------------------

    sheet.appendRow(
      _headers
          .map(
            (header) =>
            TextCellValue(header),
      )
          .toList(),
    );

    // ----------------------------------------------------------
    // DATA ROWS
    // ----------------------------------------------------------

    for (final data in records) {
      sheet.appendRow(
        _recordToRow(data)
            .map(
              (value) =>
              TextCellValue(value),
        )
            .toList(),
      );
    }

    // ----------------------------------------------------------
    // SAVE WORKBOOK
    // ----------------------------------------------------------

    final List<int>? encoded =
    workbook.save();

    if (encoded == null) {
      throw Exception(
        'Unable to create Excel file.',
      );
    }

    await _fileSaver.saveAs(
      name: 'attendance_export',
      bytes:
      Uint8List.fromList(encoded),
      fileExtension: 'xlsx',
      includeExtension: true,
      mimeType:
      MimeType.microsoftExcel,
      dialogTitle:
      'Save Attendance Excel File',
    );
  }

  // ============================================================
  // CONVERT ONE RECORD TO EXACTLY 12 COLUMNS
  // ============================================================

  static List<String> _recordToRow(
      Map<String, dynamic> data,
      ) {
    return [
      _string(data['Employee']),
      _string(data['Designation']),
      _string(data['Status']),
      _string(data['Check In 1']),
      _string(data['Check Out 1']),
      _string(data['Check In 2']),
      _string(data['Check Out 2']),
      _string(data['QR Location']),
      _string(data['Latitude']),
      _string(data['Longitude']),
      _string(data['Device']),
      _string(data['OS']),
    ];
  }

  // ============================================================
  // STRING HELPER
  // ============================================================

  static String _string(
      dynamic value,
      ) {
    if (value == null) {
      return '';
    }

    return value.toString();
  }

  // ============================================================
  // CSV ESCAPE
  // ============================================================

  static String _escapeCsv(
      String value,
      ) {
    final escaped =
    value.replaceAll('"', '""');

    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n') ||
        escaped.contains('\r')) {
      return '"$escaped"';
    }

    return escaped;
  }
}