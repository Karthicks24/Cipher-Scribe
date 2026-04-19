import 'package:flutter/material.dart';
import 'package:secure_application/secure_application.dart';
import 'package:cipherscribe/core/security/app_security_integrity.dart';
import 'package:cipherscribe/services/secure_storage_service.dart';
import 'package:cipherscribe/features/auth/auth_gate.dart';
import 'package:cipherscribe/core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize device integrity checks
  final secureStorage = SecureStorageService();
  await AppSecurityIntegrity.initializeIntegrityChecks(secureStorage);

  runApp(const CipherScribeApp());
}

class CipherScribeApp extends StatelessWidget {
  const CipherScribeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CipherScribe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      // Law 4 (Anti-Forensics): secure_application for OS task-switcher blur
      home: SecureApplication(
        nativeRemoveDelay: 100,
        onNeedUnlock: (secureApplicationState) {
          return null;
        },
        child: Builder(
          builder: (context) {
            return SecureGate(
              blurr: 60,
              opacity: 0.8,
              lockedBuilder: (context, secureNotifier) =>
                  const Center(child: Text('CipherScribe Locked')),
              child: const AuthGate(),
            );
          },
        ),
      ),
    );
  }
}
