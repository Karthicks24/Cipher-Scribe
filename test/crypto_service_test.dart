import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cipherscribe/services/crypto_service.dart';

void main() {
  group('CryptoService Tests', () {
    late CryptoService cryptoService;

    setUp(() {
      cryptoService = CryptoService();
    });

    test('deriveKEK produces consistent key for same inputs', () async {
      final key1 = await cryptoService.deriveKEK(pin: '123456', salt: 'device_salt');
      final key2 = await cryptoService.deriveKEK(pin: '123456', salt: 'device_salt');

      final bytes1 = await key1.extractBytes();
      final bytes2 = await key2.extractBytes();

      expect(bytes1, equals(bytes2));
    });

    test('deriveKEK produces different key for different inputs', () async {
      final key1 = await cryptoService.deriveKEK(pin: '123456', salt: 'device_salt');
      final key2 = await cryptoService.deriveKEK(pin: 'wrong_pin', salt: 'device_salt');

      final bytes1 = await key1.extractBytes();
      final bytes2 = await key2.extractBytes();

      expect(bytes1, isNot(equals(bytes2)));
    });

    test('encryptData and decryptData perform a successful cycle', () async {
      final kek = await cryptoService.deriveKEK(pin: 'pin', salt: 'salt');
      final clearText = [1, 2, 3, 4, 5, 255];
      
      final encrypted = await cryptoService.encryptData(clearText, kek);
      
      expect(encrypted.length, equals(clearText.length + 12 + 16)); // Nonce (12) + MAC (16)
      
      final decrypted = await cryptoService.decryptData(encrypted, kek);
      
      expect(decrypted.toList(), equals(clearText));
    });

    test('decryptData fails if data is tampered with', () async {
      final kek = await cryptoService.deriveKEK(pin: 'pin', salt: 'salt');
      final clearText = [1, 2, 3, 4, 5];
      
      final encrypted = await cryptoService.encryptData(clearText, kek);
      
      // Tamper with the MAC part
      encrypted[15] = encrypted[15] ^ 1;
      
      expect(
        () => cryptoService.decryptData(encrypted, kek),
        throwsA(anything), 
      );
    });

    test('wipeRAM turns all bytes to zero', () {
      final data = Uint8List.fromList([10, 20, 30, 40]);
      cryptoService.wipeRAM(data);
      expect(data, equals(Uint8List.fromList([0, 0, 0, 0])));
    });

    test('wrapDEK and unwrapDEK perform a successful cycle', () async {
      final kek = await cryptoService.deriveKEK(pin: 'secret_pin', salt: 'salt');
      final dek = await cryptoService.generateDEK();
      
      final wrapped = await cryptoService.wrapDEK(dek, kek);
      final unwrapped = await cryptoService.unwrapDEK(wrapped, kek);
      
      expect(unwrapped, equals(dek));
    });
  });
}
