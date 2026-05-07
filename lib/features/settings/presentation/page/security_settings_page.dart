import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cipherscribe/core/theme/app_colors.dart';
import 'package:cipherscribe/features/auth/presentation/page/verify_auth_page.dart';
import 'package:cipherscribe/features/auth/presentation/page/update_security_questions_page.dart';
import 'package:cipherscribe/features/auth/presentation/page/change_password_page.dart';
import 'dart:typed_data';

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  Future<void> _handleChangePassword() async {
    // 1. Verify Current PIN/Password
    final Uint8List? dek = await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => const VerifyAuthPage(level: VerificationLevel.standard),
      ),
    );

    if (dek == null || !mounted) return;

    // 2. Set New Password
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => ChangePasswordPage(
          importedDek: dek,
        ),
      ),
    );
  }

  Future<void> _handleChangeSecurityQuestions() async {
    // 1. Verify via Recovery Phrase (or PDF)
    final Uint8List? dek = await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => const VerifyAuthPage(level: VerificationLevel.recoveryOnly),
      ),
    );

    if (dek == null || !mounted) return;

    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => UpdateSecurityQuestionsPage(
          importedDek: dek,
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
      appBar: CupertinoNavigationBar(
        backgroundColor: (isDark ? AppColors.darkBackground : AppColors.lightBackground).withValues(alpha: 0.9),
        middle: const Text('Security Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Authentication',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildListTile(
              title: 'Change Master PIN/Password',
              subtitle: 'Requires current PIN or Security Questions',
              icon: CupertinoIcons.lock_fill,
              isDark: isDark,
              primary: primary,
              onTap: _handleChangePassword,
            ),
            const SizedBox(height: 16),
            const Text(
              'Account Recovery',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildListTile(
              title: 'Change Security Questions',
              subtitle: 'Requires 24-word Recovery Phrase',
              icon: CupertinoIcons.question_circle_fill,
              isDark: isDark,
              primary: primary,
              onTap: _handleChangeSecurityQuestions,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required Color primary,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: primary, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }
}
