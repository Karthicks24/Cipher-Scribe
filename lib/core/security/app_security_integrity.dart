import 'package:cipherscribe/core/config/security_config.dart';
import 'package:freerasp/freerasp.dart';
import 'package:cipherscribe/services/secure_storage_service.dart';
import 'dart:io';

class AppSecurityIntegrity {
  static Future<void> initializeIntegrityChecks(SecureStorageService secureStorage) async {
    // Law 4: Fail-Safe.
    final config = TalsecConfig(
      androidConfig: AndroidConfig(
        packageName: 'com.example.cipherscribe',
        signingCertHashes: [SecurityConfig.androidSigninghash],
      ),
      iosConfig: IOSConfig(
        bundleIds: ['com.example.cipherscribe'],
        teamId: SecurityConfig.iosTeamId,
      ),
      watcherMail: 'security@example.com',
    );

    final callback = ThreatCallback(
      onPrivilegedAccess: () => _failSafe(secureStorage),
      onSimulator: () => _printWarning('Emulator detected'),
      onAppIntegrity: () => _failSafe(secureStorage),
      onHooks: () => _failSafe(secureStorage),
      onDeviceBinding: () => _failSafe(secureStorage),
      onUnofficialStore: () => _printWarning('Untrusted install'),
      onPasscode: () => _printWarning('No passcode'),
      onDebug: () => _printWarning('Debugger detected'),
    );

    Talsec.instance.attachListener(callback);
    await Talsec.instance.start(config);
  }

  static void _printWarning(String msg) {
    // In production, avoid prints. Using debugPrint or custom logger.
    // print('[SECURITY WARNING]: $msg');
  }

  static Future<void> _failSafe(SecureStorageService secureStorage) async {
    // print('[CRITICAL SEC] Integrity compromised. Executing fail-safe self-destruct.');
    await secureStorage.clearMasterDEK();
    exit(0);
  }
}
