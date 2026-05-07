import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'package:cipherscribe/features/settings/presentation/page/security_settings_page.dart';

/// The sidebar drawer for the vault page.
/// 
/// Contains actions for importing/exporting backups, accessing security settings,
/// and account deletion.
class VaultDrawer extends StatelessWidget {
  final VoidCallback onImportBackup;
  final VoidCallback onExportBackup;
  final VoidCallback onDeleteAccount;

  const VaultDrawer({
    super.key,
    required this.onImportBackup,
    required this.onExportBackup,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return Drawer(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header with logo
          DrawerHeader(
            decoration: BoxDecoration(color: primary.withValues(alpha: 0.1)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.shield_fill, size: 48, color: AppColors.darkPrimary),
                const SizedBox(height: 12),
                Text(
                  'CipherScribe',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          
          // Backup Actions
          ListTile(
            leading: const Icon(CupertinoIcons.cloud_upload),
            title: const Text('Import Vault Backup'),
            onTap: () {
              Navigator.pop(context);
              onImportBackup();
            },
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.cloud_download),
            title: const Text('Export Vault Archive'),
            onTap: () {
              Navigator.pop(context);
              onExportBackup();
            },
          ),
          
          const Divider(),
          
          // Security Settings
          ListTile(
            leading: const Icon(CupertinoIcons.lock_shield),
            title: const Text('Security Settings'),
            onTap: () {
              Navigator.pop(context); // Close drawer
              Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (context) => const SecuritySettingsPage(),
                ),
              );
            },
          ),
          
          // Danger Zone
          ListTile(
            leading: const Icon(CupertinoIcons.trash, color: Colors.red),
            title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              onDeleteAccount();
            },
          ),
        ],
      ),
    );
  }
}
