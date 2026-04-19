import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Service responsible for handling encryption, decryption, and key derivation.
class CryptoService {
  final AesGcm _cipher;
  final Argon2id _kdf;

  CryptoService()
      : _cipher = AesGcm.with256bits(),
        _kdf = Argon2id(
          memory: 65536, // 64 MB
          iterations: 3,
          parallelism: 4,
          hashLength: 32, // 256 bits
        );

  /// Derives a Master Key using Argon2id. Uses the hardware salt.
  Future<SecretKey> deriveKey({
    required String password,
    required String salt,
  }) async {
    final secretKey = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: utf8.encode(salt),
    );
    return secretKey;
  }

  /// Encrypts data using AES-256-GCM.
  /// Returns a combined byte list: [nonce (12 bytes)] + [mac (16 bytes)] + [cipherText]
  Future<List<int>> encryptData(List<int> clearText, SecretKey secretKey) async {
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      clearText,
      secretKey: secretKey,
      nonce: nonce,
    );
    
    return [
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ];
  }

  /// Decrypts data using AES-256-GCM.
  /// Expects format produced by [encryptData].
  Future<Uint8List> decryptData(List<int> encryptedData, SecretKey secretKey) async {
    // Nonce is 12 bytes, MAC is 16 bytes.
    if (encryptedData.length < 28) {
      throw Exception('Invalid encrypted data length.');
    }
    
    final nonce = encryptedData.sublist(0, 12);
    final macBytes = encryptedData.sublist(12, 28);
    final cipherText = encryptedData.sublist(28);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final clearText = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );
    
    return Uint8List.fromList(clearText);
  }

  /// Law 2: Volatile Memory. Securely clears a byte array in memory.
  void zeroOutMemory(Uint8List data) {
    if (data.isNotEmpty) {
      data.fillRange(0, data.length, 0);
    }
  }
}
