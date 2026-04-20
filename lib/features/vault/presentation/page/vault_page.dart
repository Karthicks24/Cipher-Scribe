import 'package:flutter/cupertino.dart';
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

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  late final BackupService _backupService;

  @override
  void initState() {
    super.initState();
    _backupService = BackupService(CryptoService());
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
          ShareParams(files: [XFile(file.path)], text: 'My Secure CipherScribe Backup'),
        );
        LifecycleManager.isIntentionalLeave = false;
      } else {
        // Save Local Copy (to Documents directory)
        final docsDir = await getApplicationDocumentsDirectory();
        final targetPath = '${docsDir.path}/cipherscribe_backup_${DateTime.now().millisecondsSinceEpoch}.scribevault';
        await file.copy(targetPath);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved to: $targetPath'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      LifecycleManager.isIntentionalLeave = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup failed. Ensure storage permissions are granted.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Secure Vault', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.cloud_upload),
            onPressed: _showBackupOptions,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlocConsumer<VaultBloc, VaultState>(
        listener: (context, state) {
          if (state is VaultError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: Colors.red),
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
        label: const Text('Add Item', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.lock_shield, size: 64, color: isDark ? Colors.white24 : Colors.black12),
          const SizedBox(height: 16),
          Text('Your Vault is Empty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white60 : Colors.black45)),
          const SizedBox(height: 8),
          const Text('Documents added here are locked with your Master Key.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildDocTile(dynamic doc, bool isDark, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(CupertinoIcons.doc_fill, color: primary, size: 24),
        ),
        title: Text(doc.fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Added ${doc.createdAt.toLocal().toString().split(' ').first}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: const Icon(CupertinoIcons.chevron_right, size: 16, color: Colors.grey),
        onTap: () {
          // View Document logic
        },
      ),
    );
  }
}

