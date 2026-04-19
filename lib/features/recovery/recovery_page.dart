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
  String _recoveryKey = '';

  @override
  void initState() {
    super.initState();
    _recoveryKey = _recoveryService.generateRecoveryKey();
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _recoveryKey));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recovery key copied to clipboard')),
    );
  }

  void _saveAsPdf() {
    // PDF generation logic here (Placeholder)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saving as PDF (Feature coming soon)')),
    );
  }

  void _shareToSecureNotes() {
    // Sharing logic here (Placeholder)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sharing to Secure Notes (Feature coming soon)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recovery Key Setup')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.redAccent),
            const SizedBox(height: 24),
            const Text(
              'This is the only way to recover your data. If you lose this key, even we cannot help you.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade800),
              ),
              child: Text(
                _recoveryKey.replaceAllMapped(RegExp(r".{8}"), (match) => "${match.group(0)} "),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 20, letterSpacing: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _copyToClipboard,
              icon: const Icon(Icons.copy),
              label: const Text('Copy to Clipboard'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _saveAsPdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Save as PDF'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _shareToSecureNotes,
              icon: const Icon(Icons.share),
              label: const Text('Share to Secure Notes'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
