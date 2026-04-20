import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cipherscribe/services/backup_service.dart';
import 'package:cipherscribe/services/crypto_service.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

class RestoreVaultPage extends StatefulWidget {
  final VoidCallback onRestoreComplete;

  const RestoreVaultPage({super.key, required this.onRestoreComplete});

  @override
  State<RestoreVaultPage> createState() => _RestoreVaultPageState();
}

class _RestoreVaultPageState extends State<RestoreVaultPage> {
  final _phraseController = TextEditingController();
  final _crypto = CryptoService();
  late final BackupService _backupService;

  File? _selectedBackup;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _backupService = BackupService(_crypto);
  }

  @override
  void dispose() {
    _phraseController.dispose();
    super.dispose();
  }

  Future<void> _pickBackup() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.any,
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _selectedBackup = File(result.files.single.path!));
    }
  }

  Future<void> _performRestore() async {
    final phrase = _phraseController.text.trim();
    if (phrase.split(' ').length != 24) {
      setState(() => _errorMessage = 'Please enter exactly 24 words.');
      return;
    }
    if (_selectedBackup == null) {
      setState(() => _errorMessage = 'Please select a .scribevault backup file.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final dekBytes = _crypto.dekFromMnemonic(phrase);
      final recoveredKey = SecretKey(dekBytes);

      await _backupService.importVault(
        backupFile: _selectedBackup!,
        recoveryMnemonic: phrase,
        currentSessionKey: recoveredKey,
      );

      widget.onRestoreComplete();
    } catch (e) {
      setState(() {
        _errorMessage = 'Restore failed. Check your phrase or backup file.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: CupertinoNavigationBar(
        backgroundColor: (isDark ? AppColors.darkBackground : AppColors.lightBackground)
            .withValues(alpha: 0.9),
        middle: const Text('Restore Vault'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Icon(CupertinoIcons.arrow_counterclockwise_circle_fill, color: primary, size: 44),
              const SizedBox(height: 14),
              Text('Restore Your Vault',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 8),
              Text('Enter your 24-word recovery phrase and select your .scribevault backup file.',
                style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54)),
              const SizedBox(height: 32),

              // ── Phrase Input ──────────────────────────────────────────────
              Text('Recovery Phrase',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.08)),
                ),
                child: TextField(
                  controller: _phraseController,
                  maxLines: 5,
                  style: TextStyle(
                    fontSize: 15, height: 1.6,
                    color: isDark ? Colors.white : Colors.black87,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'word1 word2 word3 ... word24',
                    hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── File Picker ───────────────────────────────────────────────
              Text('Backup File (.scribevault)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54)),
              const SizedBox(height: 8),
              _buildFilePicker(isDark, primary),
              const SizedBox(height: 24),

              // ── Error ─────────────────────────────────────────────────────
              if (_errorMessage.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(CupertinoIcons.exclamationmark_circle, color: Colors.red, size: 15),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMessage,
                      style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ]),
                ),
                const SizedBox(height: 20),
              ],

              // ── CTA ───────────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: _isLoading
                  ? const Center(child: CupertinoActivityIndicator())
                  : CupertinoButton(
                      color: primary,
                      borderRadius: BorderRadius.circular(14),
                      onPressed: _performRestore,
                      child: const Text('Start Restoration',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                    ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilePicker(bool isDark, Color primary) {
    return GestureDetector(
      onTap: _pickBackup,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primary.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(_selectedBackup == null
            ? CupertinoIcons.cloud_download : CupertinoIcons.doc_fill,
            color: primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _selectedBackup == null
                  ? 'Tap to choose backup file'
                  : p.basename(_selectedBackup!.path),
                style: TextStyle(fontWeight: FontWeight.w600,
                  color: _selectedBackup == null
                    ? Colors.grey : (isDark ? Colors.white : Colors.black87)),
              ),
              if (_selectedBackup != null)
                Text('Selected', style: TextStyle(fontSize: 12, color: primary)),
            ]),
          ),
          Icon(CupertinoIcons.chevron_right, color: Colors.grey.withValues(alpha: 0.5), size: 16),
        ]),
      ),
    );
  }
}
