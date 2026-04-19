import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Handles hardware-bound secrets, password, security questions and device specific information.
class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kMasterKey = 'master_key';
  static const _kPasswordHash = 'cs_password_hash';
  static const _kSetupDone = 'cs_setup_complete';
  static const _kQuestion1 = 'cs_security_q1';
  static const _kAnswer1 = 'cs_security_a1_hash';
  static const _kQuestion2 = 'cs_security_q2';
  static const _kAnswer2 = 'cs_security_a2_hash';

  // ── Internal hash helper ──────────────────────────────────────────────────
  String _sha256(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  // ── Master Key (vault session) ────────────────────────────────────────────

  /// Saves the master key to Keystore (Android) / Keychain (iOS)
  Future<void> saveMasterKey(String key) async {
    await _storage.write(key: _kMasterKey, value: key);
  }

  /// Retrieves the master key
  Future<String?> getMasterKey() async {
    return await _storage.read(key: _kMasterKey);
  }

  /// Destroys the master key
  Future<void> clearMasterKey() async {
    await _storage.delete(key: _kMasterKey);
  }

  // ── First-launch setup ────────────────────────────────────────────────────

  /// Returns true if the user has completed initial setup.
  Future<bool> isSetupComplete() async {
    final val = await _storage.read(key: _kSetupDone);
    return val == 'true';
  }

  /// Marks setup as complete.
  Future<void> markSetupComplete() async {
    await _storage.write(key: _kSetupDone, value: 'true');
  }

  // ── Password ──────────────────────────────────────────────────────────────

  /// Stores a SHA-256 hash of the master password.
  Future<void> savePassword(String password) async {
    await _storage.write(key: _kPasswordHash, value: _sha256(password));
  }

  /// Verifies a candidate password against the stored hash.
  Future<bool> verifyPassword(String candidate) async {
    final stored = await _storage.read(key: _kPasswordHash);
    if (stored == null) return false;
    return stored == _sha256(candidate);
  }

  // ── Security Questions ────────────────────────────────────────────────────

  /// Stores two security questions and their hashed answers.
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

  /// Returns the stored security questions (plain text).
  Future<({String q1, String q2})> getSecurityQuestions() async {
    final q1 = await _storage.read(key: _kQuestion1) ?? '';
    final q2 = await _storage.read(key: _kQuestion2) ?? '';
    return (q1: q1, q2: q2);
  }

  /// Verifies a candidate answer for question [number] (1 or 2).
  Future<bool> verifySecurityAnswer(int number, String candidateAnswer) async {
    final key = number == 1 ? _kAnswer1 : _kAnswer2;
    final stored = await _storage.read(key: key);
    if (stored == null) return false;
    return stored == _sha256(candidateAnswer.trim().toLowerCase());
  }

  // ── Hardware Salt ─────────────────────────────────────────────────────────

  /// Retrieves a hardware-bound salt based on the device ID.
  /// This ensures Law 3: Hardware-Bound Master Key.
  Future<String> getDeviceHardwareSalt() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id; // Unique hardware ID
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'fallback_salt';
    }
    // Fallback for testing/unsupported platforms
    return 'cipherscribe_hardware_salt';
  }
}

