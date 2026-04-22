import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/foundation.dart';

/// Service responsible for handling Master DEK, key wrapping, PBKDF2, and memory management.
class CryptoService {
  final AesGcm _cipher;
  
  CryptoService() : _cipher = AesGcm.with256bits();

  // ─── PBKDF2 (100,000 Iterations) ───────────────────────────────────────────

  /// Derives a Key Encryption Key (KEK) using PBKDF2 in a separate Isolate.
  static Future<SecretKeyData> _deriveKEKIsolate(Map<String, dynamic> params) async {
    final password = params['password'] as String;
    final salt = params['salt'] as String;
    
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );

    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: utf8.encode(salt),
    );
    
    return await secretKey.extract();
  }

  /// Public wrapper for PBKDF2 Isolate call.
  Future<SecretKey> deriveKEK({
    required String pin,
    required String salt,
  }) async {
    final secretKeyData = await compute(_deriveKEKIsolate, {
      'password': pin,
      'salt': salt,
    });
    return SecretKey(secretKeyData.bytes);
  }

  // ─── Master DEK Management ──────────────────────────────────────────────────

  /// Generates a Master Data Encryption Key (DEK) using CSPRNG.
  Future<Uint8List> generateDEK() async {
    final key = await _cipher.newSecretKey();
    final data = await key.extractBytes();
    return Uint8List.fromList(data);
  }

  /// Generates a 24-word BIP-39 mnemonic for the provided DEK bytes.
  String generateMnemonic(Uint8List dekBytes) {
    // Note: 256 bits of entropy = 24 words.
    return bip39.entropyToMnemonic(hexEncode(dekBytes));
  }

  /// Recovers DEK bytes from a 24-word BIP-39 mnemonic.
  Uint8List dekFromMnemonic(String mnemonic) {
    final entropyHex = bip39.mnemonicToEntropy(mnemonic);
    return hexDecode(entropyHex);
  }

  // ─── Key Wrapping ──────────────────────────────────────────────────────────

  /// Wraps (encrypts) the DEK using the KEK derived from PIN/Password.
  Future<List<int>> wrapDEK(Uint8List dek, SecretKey kek) async {
    return await encryptData(dek, kek);
  }

  /// Unwraps (decrypts) the DEK using the KEK.
  Future<Uint8List> unwrapDEK(List<int> wrappedDek, SecretKey kek) async {
    return await decryptData(wrappedDek, kek);
  }

  // ─── Core Encryption ───────────────────────────────────────────────────────

  /// Encrypts data using AES-256-GCM.
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
  Future<Uint8List> decryptData(List<int> encryptedData, SecretKey secretKey) async {
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

  // ─── Secure Memory Management ──────────────────────────────────────────────

  /// Explicitly zeros out sensitive byte arrays in RAM.
  void wipeRAM(Uint8List? data) {
    if (data != null && data.isNotEmpty) {
      data.fillRange(0, data.length, 0);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List hexDecode(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}

