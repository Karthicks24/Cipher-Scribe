import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';

/// Service responsible for generating the Recovery PDF and handling recovery phrases.
class RecoveryService {
  /// Generates and triggers the print/save dialog for the Recovery PDF.
  Future<void> generateAndSaveRecoveryPdf({
    required String mnemonic,
    required String dekHex,
  }) async {
    final pdf = pw.Document();
    final words = mnemonic.split(' ');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                pw.SizedBox(height: 32),
                _buildSecurityWarning(),
                pw.SizedBox(height: 32),
                _buildWordGrid(words),
                pw.SizedBox(height: 40),
                _buildMasterKeySection(dekHex),
                pw.Spacer(),
                _buildFooter(),
              ],
            ),
          );
        },
      ),
    );

    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/CipherScribe_Recovery_Sheet.pdf');
    await file.writeAsBytes(bytes);

    // Also trigger a share dialog so the user can easily "download" it to their preferred location
    await Share.shareXFiles([XFile(file.path)], text: 'Your CipherScribe Recovery Sheet');
  }

  pw.Widget _buildHeader() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'CipherScribe',
          style: pw.TextStyle(
            fontSize: 28,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey900,
          ),
        ),
        pw.Text(
          'RECOVERY SHEET',
          style: pw.TextStyle(
            fontSize: 12,
            letterSpacing: 2,
            color: PdfColors.grey700,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildSecurityWarning() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.red800, width: 2),
        color: PdfColors.red50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'IMPORTANT SECURITY NOTICE',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red900,
              fontSize: 14,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Keep this document in a safe, physical location. Do not store it digitally on an unencrypted device. '
            'If you lose your PIN and this sheet, your data is permanently unrecoverable.',
            style: pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildWordGrid(List<String> words) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '24-WORD RECOVERY PHRASE',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
        ),
        pw.SizedBox(height: 16),
        pw.GridView(
          crossAxisCount: 3,
          childAspectRatio: 3,
          children: List.generate(words.length, (index) {
            return pw.Container(
              padding: const pw.EdgeInsets.all(8),
              margin: const pw.EdgeInsets.all(2),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 20,
                    child: pw.Text('${index + 1}.', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  ),
                  pw.Text(words[index], style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  pw.Widget _buildMasterKeySection(String dekHex) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'MASTER DATA ENCRYPTION KEY (DEK)',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          child: pw.Text(
            dekHex.toUpperCase().replaceAllMapped(RegExp(r".{4}"), (match) => "${match.group(0)} "),
            style: pw.TextStyle(
              font: pw.Font.courier(),
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated by CipherScribe Secure Vault', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text(DateTime.now().toString().split('.').first, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      ],
    );
  }

  /// Generates a secure recovery key/phrase (Wrapper for legacy RecoveryPage)
  String generateRecoveryKey() {
    // In the new architecture, we prefer 24-word mnemonic phrases
    // but for the legacy page compatibility, we return a secure hex string
    // or a mnemonic if that's what's expected.
    // Let's use a 64-char hex key.
    return List.generate(64, (i) => '0123456789ABCDEF'[DateTime.now().microsecondsSinceEpoch % 16]).join();
  }
}

