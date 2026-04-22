import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:cipherscribe/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'package:cipherscribe/services/backup_service.dart';
import 'package:cipherscribe/services/crypto_service.dart';
import 'package:cipherscribe/core/utils/lifecycle_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cipherscribe/services/secure_storage_service.dart';
import 'package:cipherscribe/features/vault/presentation/page/document_viewer_page.dart';
import 'package:cipherscribe/features/auth/set_password_page.dart';
import 'package:cipherscribe/features/vault/domain/entities/vault_document.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  late final BackupService _backupService;
  final _storage = SecureStorageService();
  final _crypto = CryptoService();

  @override
  void initState() {
    super.initState();
    _backupService = BackupService(_crypto);
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return "${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}";
  }

  Future<void> _viewDocument(VaultDocument doc) async {
    final bloc = context.read<VaultBloc>();
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => DocumentViewerPage(
          document: doc,
          sessionKey: bloc.sessionKey,
        ),
      ),
    );
  }

  Future<void> _showDocActions(VaultDocument doc) async {
    final bloc = context.read<VaultBloc>();
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _renameDialog(doc);
            },
            child: const Text('Rename'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              _deleteConfirm(doc);
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _renameDialog(VaultDocument doc) {
    final ctrl = TextEditingController(text: doc.fileName);
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Rename File'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(controller: ctrl),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty) {
                context.read<VaultBloc>().add(RenameDocument(doc.id, newName));
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteConfirm(VaultDocument doc) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Are you sure you want to delete "${doc.fileName}"? This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              context.read<VaultBloc>().add(DeleteDocument(doc.id));
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // --- Drawer Actions ---

  Future<void> _handleChangePassword() async {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl1 = TextEditingController();
    final newPassCtrl2 = TextEditingController();
    final isPin = await _storage.getAuthMethod() == 'pin';

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Change ${isPin ? 'PIN' : 'Password'}'),
        content: Column(
          children: [
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: oldPassCtrl,
              placeholder: 'Current ${isPin ? 'PIN' : 'Password'}',
              obscureText: true,
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: newPassCtrl1,
              placeholder: 'New ${isPin ? 'PIN' : 'Password'}',
              obscureText: true,
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: newPassCtrl2,
              placeholder: 'Confirm New',
              obscureText: true,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              if (newPassCtrl1.text != newPassCtrl2.text || newPassCtrl1.text.isEmpty) return;
              
              final sessionKey = context.read<VaultBloc>().sessionKey;
              final salt = await _storage.getDeviceHardwareSalt();
              
              try {
                // Verify old password
                final oldKek = await _crypto.deriveKEK(pin: oldPassCtrl.text, salt: salt);
                final wrappedDek = await _storage.getWrappedDEK();
                if (wrappedDek == null) return;

                final testDek = await _crypto.unwrapDEK(wrappedDek, oldKek);
                final sessionBytes = await sessionKey.extractBytes();
                
                // Compare bytes (timing-safe comparison would be better but this is a local check)
                if (listEquals(testDek, sessionBytes)) {
                  // Authorized: Re-wrap with NEW KEK
                  final newKek = await _crypto.deriveKEK(pin: newPassCtrl1.text, salt: salt);
                  final reWrapped = await _crypto.wrapDEK(testDek, newKek);
                  await _storage.saveWrappedDEK(reWrapped);
                  
                  // Wrap it for security questions too? 
                  // The user didn't ask for security question update, but usually they share the same DEK.
                  // For now, only the main wrap is updated as requested.

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated successfully')));
                  }
                } else {
                  throw Exception('Incorrect current password');
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification failed: Incorrect current password'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  void _handleDeleteAccount() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('NUCLEAR OPTION'),
        content: const Text('This will PERMANENTLY WIPE your vault, all files, and your account. This cannot be reversed.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              await _storage.nukeAccount();
              exit(0); // Exit app to force reset
            },
            child: const Text('WIPE EVERYTHING'),
          ),
        ],
      ),
    );
  }

  Future<void> _importDocument() async {
    LifecycleManager.isIntentionalLeave = true;
    final FilePickerResult? result = await FilePicker.pickFiles();
    LifecycleManager.isIntentionalLeave = false;

    if (result != null) {
      final pathStr = result.files.single.path;
      if (pathStr == null) return;

      if (!mounted) return;
      context.read<VaultBloc>().add(ImportNewDocument(File(pathStr)));
    }
  }

  Future<void> _showBackupOptions() async {
    final bloc = context.read<VaultBloc>();

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Vault Archive'),
        message: const Text('Manage your secure .scribevault container.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _performBackup(bloc, share: true);
            },
            child: const Text('Share Secure Backup'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _performBackup(bloc, share: false);
            },
            child: const Text('Save Local Copy'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _performBackup(VaultBloc bloc, {bool share = true}) async {
    try {
      final file = await _backupService.exportVault(bloc.sessionKey);

      if (share) {
        LifecycleManager.isIntentionalLeave = true;
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'My Secure CipherScribe Backup',
          ),
        );
        LifecycleManager.isIntentionalLeave = false;
      } else {
        // Save Local Copy (to Documents directory)
        final docsDir = await getApplicationDocumentsDirectory();
        final targetPath =
            '${docsDir.path}/cipherscribe_backup_${DateTime.now().millisecondsSinceEpoch}.scribevault';
        await file.copy(targetPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to: $targetPath'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      LifecycleManager.isIntentionalLeave = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Backup failed. Ensure storage permissions are granted.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text(
          'Secure Vault',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      drawer: Drawer(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: primary.withValues(alpha: 0.1)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.shield_fill, size: 48, color: AppColors.darkPrimary),
                  const SizedBox(height: 12),
                  Text('CipherScribe', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.cloud_upload),
              title: const Text('Import Vault Backup'),
              onTap: () {
                Navigator.pop(context);
                // Implementation for restoration
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.cloud_download),
              title: const Text('Export Vault Archive'),
              onTap: () {
                Navigator.pop(context);
                _showBackupOptions();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(CupertinoIcons.lock_shield),
              title: const Text('Change Password'),
              onTap: () {
                Navigator.pop(context);
                _handleChangePassword();
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.trash, color: Colors.red),
              title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _handleDeleteAccount();
              },
            ),
          ],
        ),
      ),
      body: BlocConsumer<VaultBloc, VaultState>(
        listener: (context, state) {
          if (state is VaultError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is VaultLoading) {
            return const Center(child: CupertinoActivityIndicator());
          } else if (state is VaultLoaded) {
            if (state.documents.isEmpty) {
              return _buildEmptyState(isDark);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.documents.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = state.documents[index];
                return _buildDocTile(doc, isDark, primary);
              },
            );
          }
          return const Center(child: CupertinoActivityIndicator());
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importDocument,
        backgroundColor: primary,
        icon: const Icon(CupertinoIcons.add, color: Colors.white),
        label: const Text(
          'Add Item',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.lock_shield,
            size: 64,
            color: isDark ? Colors.white24 : Colors.black12,
          ),
          const SizedBox(height: 16),
          Text(
            'Your Vault is Empty',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Documents added here are locked with your Master Key.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDocTile(VaultDocument doc, bool isDark, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _buildThumbnail(doc, primary),
          ),
        ),
        title: Text(
          doc.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${_formatFileSize(doc.fileSize ?? 0)} • ${doc.createdAt.toLocal().toString().split(' ').first}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: IconButton(
          icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 20),
          onPressed: () => _showDocActions(doc),
        ),
        onTap: () => _viewDocument(doc),
      ),
    );
  }
}

Widget _buildThumbnail(VaultDocument doc, Color primary) {
  // If it's an image, we could show a thumbnail if we had a thumbnailing service
  // For now, use high-quality icons per type
  IconData iconData = CupertinoIcons.doc_fill;
  if (doc.fileType == 'image') {
    iconData = CupertinoIcons.photo_fill;
  } else if (doc.fileType == 'pdf') {
    iconData = CupertinoIcons.doc_text_fill;
  }
  
  return Icon(
    iconData,
    color: primary,
    size: 24,
  );
}
