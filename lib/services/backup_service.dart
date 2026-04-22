import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:cipherscribe/services/crypto_service.dart';

class BackupService {
  final CryptoService _crypto;

  BackupService(this._crypto);

  /// ─── Atomic Export ────────────────────────────────────────────────────────
  
  /// Creates a containerized backup (.scribevault) containing the DB and bloated blobs.
  Future<File> exportVault(SecretKey sessionKey) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(appDir.path, 'cipher_scribe.sqlite'));
    final blobDir = Directory(p.join(appDir.path, 'blobs'));

    // 1. Create Archive (ZIP)
    final archive = Archive();
    
    // Add DB
    if (await dbFile.exists()) {
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('vault.sqlite', dbBytes.length, dbBytes));
    }

    // Add Blobs
    if (await blobDir.exists()) {
      await for (final file in blobDir.list()) {
        if (file is File && file.path.endsWith('.scribeblob')) {
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile('blobs/${p.basename(file.path)}', bytes.length, bytes));
        }
      }
    }

    // 2. Compress
    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);
    // 3. Encrypt the entire archive with Master DEK
    final encryptedContainer = await _crypto.encryptData(zipBytes, sessionKey);

    // 4. Atomic Write (temp -> rename)
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File(p.join(appDir.path, 'backup_$timestamp.tmp'));
    final finalFile = File(p.join(appDir.path, 'cipher_backup_$timestamp.scribevault'));

    await tempFile.writeAsBytes(encryptedContainer);
    await tempFile.rename(finalFile.path);

    return finalFile;
  }

  /// ─── Migration / Import ───────────────────────────────────────────────────

  /// Imports a .scribevault, decrypts it using provided mnemonic, and migrates to current session.
  Future<void> importVault({
    required File backupFile, 
    required String recoveryMnemonic,
    required SecretKey currentSessionKey,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    
    // 1. Derive original DEK from mnemonic
    final originalDekBytes = _crypto.dekFromMnemonic(recoveryMnemonic);
    final originalSecretKey = SecretKey(originalDekBytes);

    // 2. Decrypt container
    final encryptedData = await backupFile.readAsBytes();
    final zipBytes = await _crypto.decryptData(encryptedData, originalSecretKey);

    // 3. Extract Archive
    final archive = ZipDecoder().decodeBytes(zipBytes);
    
    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        
        if (filename == 'vault.sqlite') {
          // Logic to merge or replace DB
          // For senior MVP: Replace current (user warned) or import rows
        } else if (filename.startsWith('blobs/')) {
          // Re-encrypt blob with current session key if they are different
          // Actually, blobs are already encrypted with the DEK.
          // If the DEK is the same, just write them.
          // IF the DEK is different (migration), we must decrypt with originalSecretKey and re-encrypt with currentSessionKey.
          
          final blobBytes = Uint8List.fromList(data);
          final decryptedBlob = await _crypto.decryptData(blobBytes, originalSecretKey);
          final reEncryptedBlob = await _crypto.encryptData(decryptedBlob, currentSessionKey);
          
          final target = File(p.join(appDir.path, filename));
          await target.parent.create(recursive: true);
          await target.writeAsBytes(reEncryptedBlob);
        }
      }
    }
  }
}
