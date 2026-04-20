import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cipherscribe/services/recovery_service.dart';

class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key});

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  final _recoveryService = RecoveryService();
  String _recoveryMnemonic = '';
  String _dekHex = '';

  @override
  void initState() {
    super.initState();
    // In a real implementation, we would fetch the mnemonic from SecureStorage or pass it here.
    // For now, we'll generate one to show the "Senior" UI.
    _recoveryMnemonic = 'word ' * 23 + 'word'; 
    _dekHex = '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF';
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _recoveryMnemonic));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recovery phrase copied to clipboard')),
    );
  }

  void _saveAsPdf() {
    _recoveryService.generateAndSaveRecoveryPdf(
      mnemonic: _recoveryMnemonic,
      dekHex: _dekHex,
    );
  }

  // ... (rest of methods)

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      appBar: AppBar(
        title: const Text('Recovery Setup'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(CupertinoIcons.shield_fill, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Your Recovery Phrase',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Write down these 24 words in the exact order. This is the ONLY way to restore your vault.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            _buildWordGrid(isDark),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _saveAsPdf,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(CupertinoIcons.doc_text_fill),
                label: const Text('Download Recovery PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _copyToClipboard,
              child: const Text('Copy Mnemonic to Clipboard'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildWordGrid(bool isDark) {
    final words = _recoveryMnemonic.split(' ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 2.5,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: words.length,
        itemBuilder: (context, i) => Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Text(
              '${i + 1}. ${words[i]}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
