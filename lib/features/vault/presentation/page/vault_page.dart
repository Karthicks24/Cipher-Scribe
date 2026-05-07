import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:cipherscribe/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'package:cipherscribe/services/backup_service.dart';
import 'package:cipherscribe/services/crypto_service.dart';
import 'package:cipherscribe/core/utils/lifecycle_manager.dart';
import 'package:cipherscribe/services/secure_storage_service.dart';
import 'package:cipherscribe/features/vault/presentation/page/document_viewer_page.dart';
import 'package:cipherscribe/features/vault/domain/entities/vault_document.dart';

// Import new widgets
import 'package:cipherscribe/features/vault/presentation/widgets/vault_drawer.dart';
import 'package:cipherscribe/features/vault/presentation/widgets/vault_document_tile.dart';
import 'package:cipherscribe/features/vault/presentation/widgets/empty_vault_view.dart';

/// The main vault page displaying the list of secure documents.
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

  // --- Document Navigation ---

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

  // --- Document Actions ---

  Future<void> _showDocActions(VaultDocument doc) async {
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

  // --- Account & Backup Actions ---

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
            content: Text('Backup failed. Ensure storage permissions are granted.'),
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text(
          'Secure Vault',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(
              CupertinoIcons.bars,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      
      // Refactored Drawer
      drawer: VaultDrawer(
        onImportBackup: () {
          // TODO: Implement backup import
        },
        onExportBackup: _showBackupOptions,
        onDeleteAccount: _handleDeleteAccount,
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
              return const EmptyVaultView();
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.documents.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = state.documents[index];
                return VaultDocumentTile(
                  doc: doc,
                  onTap: () => _viewDocument(doc),
                  onActions: () => _showDocActions(doc),
                );
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
}