import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:cipherscribe/features/vault/domain/entities/vault_document.dart';
import 'package:cipherscribe/services/crypto_service.dart';
import 'package:printing/printing.dart';
import 'dart:typed_data';
import 'package:cipherscribe/core/theme/app_colors.dart';

class DocumentViewerPage extends StatefulWidget {
  final VaultDocument document;
  final SecretKey sessionKey;

  const DocumentViewerPage({
    super.key,
    required this.document,
    required this.sessionKey,
  });

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  final _crypto = CryptoService();
  Uint8List? _decryptedData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decryptFile();
  }

  @override
  void dispose() {
    // SECURITY: Securely wipe the decrypted data from RAM as soon as we leave
    if (_decryptedData != null) {
      _crypto.wipeRAM(_decryptedData!);
    }
    super.dispose();
  }

  Future<void> _decryptFile() async {
    try {
      final file = File(widget.document.filePath);
      if (!await file.exists()) {
        throw Exception('File not found at: ${widget.document.filePath}');
      }

      final encryptedBytes = await file.readAsBytes();
      final decrypted = await _crypto.decryptData(encryptedBytes, widget.sessionKey);

      if (mounted) {
        setState(() {
          _decryptedData = decrypted;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: CupertinoNavigationBar(
        backgroundColor: (isDark ? AppColors.darkBackground : AppColors.lightBackground).withValues(alpha: 0.9),
        middle: Text(
          widget.document.fileName,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
      ),
      body: SafeArea(
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'Decryption Failed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[700]),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (_decryptedData == null) {
      return const Center(child: Text('No data found.'));
    }

    if (widget.document.fileType == 'image') {
      return Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            _decryptedData!,
            fit: BoxFit.contain,
          ),
        ),
      );
    } else if (widget.document.fileType == 'pdf') {
      return PdfPreview(
        build: (format) => _decryptedData!,
        allowPrinting: false,
        allowSharing: false,
        useActions: false,
        // canPrint: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        previewPageMargin: EdgeInsets.zero,
        // backgroundColor: Colors.transparent,
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.doc_text, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Preview not supported for this file type.'),
            const SizedBox(height: 8),
            Text(
              'File: ${widget.document.fileName}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }
  }
}
