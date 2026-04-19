import 'dart:math';

/// Service responsible for the 64-character Signal model recovery key.
class RecoveryService {
  /// Generates a 64-character hexadecimal recovery key.
  String generateRecoveryKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    // 32 bytes = 64 hex characters
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Parses and validates the recovery key.
  bool validateRecoveryKey(String key) {
    if (key.length != 64) return false;
    final validHex = RegExp(r'^[0-9a-fA-F]+$');
    return validHex.hasMatch(key);
  }
}
