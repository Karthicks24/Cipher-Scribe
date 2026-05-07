import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Handles hardware-bound secrets, wrapped DEK, failed attempts, and vault security.
class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kWrappedDEK = 'wrapped_dek_v2';
  static const _kSetupDone = 'cs_setup_complete';
  static const _kFailedAttempts = 'cs_failed_login_attempts';
  static const _kAuthMethod = 'cs_auth_method'; // 'pin' or 'password'
  static const _kBiometricDEK = 'cs_biometric_dek';
  static const _kMaxAttempts = 10;
  
  static const _kQuestion1 = 'cs_security_q1';
  static const _kAnswer1 = 'cs_security_a1_hash';
  static const _kQuestion2 = 'cs_security_q2';
  static const _kAnswer2 = 'cs_security_a2_hash';
  static const _kDekHash = 'cs_dek_hash';

  // ── DEK Verification ──────────────────────────────────────────────────────

  /// Saves a SHA-256 hash of the DEK for validation purposes.
  Future<void> saveDekHash(Uint8List dek) async {
    final hash = sha256.convert(dek).toString();
    await _storage.write(key: _kDekHash, value: hash);
  }

  /// Retrieves the stored DEK hash.
  Future<String?> getDekHash() async {
    return await _storage.read(key: _kDekHash);
  }

  // ── Internal hash helper ──────────────────────────────────────────────────
  String _sha256(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  // ── Wrapped DEK ───────────────────────────────────────────────────────────

  /// Saves the KEK-wrapped DEK (hex encoded).
  Future<void> saveWrappedDEK(List<int> wrappedBytes) async {
    final hex = wrappedBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: _kWrappedDEK, value: hex);
  }

  /// Retrieves the KEK-wrapped DEK.
  Future<List<int>?> getWrappedDEK() async {
    final hex = await _storage.read(key: _kWrappedDEK);
    if (hex == null) return null;
    
    final bytes = List<int>.generate(hex.length ~/ 2, (i) {
      return int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    });
    return bytes;
  }

  /// Destroys the wrapped DEK ("Nuke" feature).
  Future<void> clearMasterDEK() async {
    await _storage.delete(key: _kWrappedDEK);
    await _storage.delete(key: _kBiometricDEK);
    await resetFailedAttempts();
  }

  // ── Biometric Caching ─────────────────────────────────────────────────────

  /// Saves the raw DEK (hex encoded) securely for biometric unlock
  Future<void> saveBiometricDEK(String hexDek) async {
    await _storage.write(key: _kBiometricDEK, value: hexDek);
  }

  /// Retrieves the cached DEK for biometric unlock
  Future<String?> getBiometricDEK() async {
    return await _storage.read(key: _kBiometricDEK);
  }

  // ── Failed Attempts Tracking ──────────────────────────────────────────────

  /// Returns current failed attempts.
  Future<int> getFailedAttempts() async {
    final val = await _storage.read(key: _kFailedAttempts);
    return int.tryParse(val ?? '0') ?? 0;
  }

  /// Increments failed attempts counter.
  Future<int> incrementFailedAttempts() async {
    final current = await getFailedAttempts();
    final next = current + 1;
    await _storage.write(key: _kFailedAttempts, value: next.toString());
    
    if (next >= _kMaxAttempts) {
      await clearMasterDEK();
    }
    return next;
  }

  /// Resets failed attempts to 0.
  Future<void> resetFailedAttempts() async {
    await _storage.write(key: _kFailedAttempts, value: '0');
  }

  // ── First-launch setup ────────────────────────────────────────────────────

  Future<bool> isSetupComplete() async {
    final val = await _storage.read(key: _kSetupDone);
    return val == 'true';
  }

  Future<void> markSetupComplete() async {
    await _storage.write(key: _kSetupDone, value: 'true');
  }

  // ── Security Questions (Legacy support) ───────────────────────────────────

  Future<void> saveSecurityQuestions({
    required String q1,
    required String a1,
    required String q2,
    required String a2,
  }) async {
    await _storage.write(key: _kQuestion1, value: q1);
    await _storage.write(key: _kAnswer1, value: _sha256(a1));
    await _storage.write(key: _kQuestion2, value: q2);
    await _storage.write(key: _kAnswer2, value: _sha256(a2));
  }

  Future<bool> verifySecurityAnswer(int number, String candidateAnswer) async {
    final key = number == 1 ? _kAnswer1 : _kAnswer2;
    final stored = await _storage.read(key: key);
    if (stored == null) return false;
    return stored == _sha256(candidateAnswer.trim().toLowerCase());
  }

  // ── Hardware Salt ─────────────────────────────────────────────────────────

  Future<String> getDeviceHardwareSalt() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id; 
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'fallback_salt';
    }
    return 'cipherscribe_hardware_salt';
  }

  // ── Auth Method (PIN vs PASSWORD) ─────────────────────────────────────────

  Future<String> getAuthMethod() async {
    final val = await _storage.read(key: _kAuthMethod);
    return val ?? 'pin'; // Default to pin for existing users
  }

  Future<void> setAuthMethod(String method) async {
    await _storage.write(key: _kAuthMethod, value: method);
  }

  // ── Generic Key-Value ─────────────────────────────────────────────────────

  Future<void> writeString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> readString(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> deleteKey(String key) async {
    await _storage.delete(key: key);
  }

  Future<void> nukeAccount() async {
    await _storage.deleteAll();
    // Also delete the DB file and blobs
    final docDir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(docDir.path, 'cipher_scribe.sqlite'));
    final blobDir = Directory(p.join(docDir.path, 'blobs'));
    if (await dbFile.exists()) await dbFile.delete();
    if (await blobDir.exists()) await blobDir.delete(recursive: true);
  }
}



