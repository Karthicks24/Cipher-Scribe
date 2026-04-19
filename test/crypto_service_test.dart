import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cipherscribe/services/crypto_service.dart';

void main() {
  group('CryptoService Tests', () {
    late CryptoService cryptoService;

    setUp(() {
      cryptoService = CryptoService();
    });

    test('deriveKey produces consistent SecretKey for same inputs', () async {
      final key1 = await cryptoService.deriveKey(password: 'my_secure_pin', salt: 'device_salt_123');
      final key2 = await cryptoService.deriveKey(password: 'my_secure_pin', salt: 'device_salt_123');

      final bytes1 = await key1.extractBytes();
      final bytes2 = await key2.extractBytes();

      expect(bytes1, equals(bytes2));
    });

    test('deriveKey produces different SecretKey for different inputs', () async {
      final key1 = await cryptoService.deriveKey(password: 'my_secure_pin', salt: 'device_salt_123');
      final key2 = await cryptoService.deriveKey(password: 'wrong_pin', salt: 'device_salt_123');

      final bytes1 = await key1.extractBytes();
      final bytes2 = await key2.extractBytes();

      expect(bytes1, isNot(equals(bytes2)));
    });

    test('encryptData and decryptData perform a successful cycle', () async {
      final key = await cryptoService.deriveKey(password: 'pin', salt: 'salt');
      final clearText = [1, 2, 3, 4, 5, 255];
      
      final encrypted = await cryptoService.encryptData(clearText, key);
      
      expect(encrypted.length, equals(clearText.length + 12 + 16)); // Nonce (12) + MAC (16)
      
      final decrypted = await cryptoService.decryptData(encrypted, key);
      
      expect(decrypted.toList(), equals(clearText));
    });

    test('decryptData fails if data is tampered with', () async {
      final key = await cryptoService.deriveKey(password: 'pin', salt: 'salt');
      final clearText = [1, 2, 3, 4, 5];
      
      final encrypted = await cryptoService.encryptData(clearText, key);
      
      // Tamper with the MAC part
      encrypted[15] = encrypted[15] ^ 1;
      
      expect(
        () => cryptoService.decryptData(encrypted, key),
        throwsA(anything), 
      );
    });

    test('zeroOutMemory turns all bytes to zero', () {
      final data = Uint8List.fromList([10, 20, 30, 40]);
      cryptoService.zeroOutMemory(data);
      expect(data, equals(Uint8List.fromList([0, 0, 0, 0])));
    });
  });
}
