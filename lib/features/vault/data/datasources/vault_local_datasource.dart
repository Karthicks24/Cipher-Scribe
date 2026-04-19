import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:cipherscribe/core/database/database.dart';
import 'package:cipherscribe/services/crypto_service.dart';

abstract class VaultLocalDataSource {
  Future<List<Document>> getDocuments();
  Future<Document> importDocument(File file);
  Future<void> deleteDocument(int id);
}

class VaultLocalDataSourceImpl implements VaultLocalDataSource {
  final AppDatabase database;
  final CryptoService cryptoService;

  VaultLocalDataSourceImpl({
    required this.database,
    required this.cryptoService,
  });

  @override
  Future<List<Document>> getDocuments() async {
    return await database.select(database.documents).get();
  }

  @override
  Future<Document> importDocument(File file) async {
    final fileName = p.basename(file.path);
    final clearText = await file.readAsBytes();
    
    // Simulate derived session key
    final secretKey = await cryptoService.deriveKey(password: 'session_pin', salt: 'session_salt');
    
    // Encrypt file
    final encryptedData = await cryptoService.encryptData(clearText.toList(), secretKey);
    
    // Securely wipe cleartext from memory
    cryptoService.zeroOutMemory(clearText);

    // Save encrypted blob to app storage
    final appDir = await getApplicationDocumentsDirectory();
    final encryptedFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName.enc';
    final encryptedFile = File(p.join(appDir.path, encryptedFileName));
    await encryptedFile.writeAsBytes(encryptedData);

    // Insert metadata into Drift
    final document = await database.into(database.documents).insertReturning(
      DocumentsCompanion.insert(
        fileName: fileName,
        filePath: encryptedFile.path,
      ),
    );

    return document;
  }

  @override
  Future<void> deleteDocument(int id) async {
    // Delete from DB and file system
    final doc = await (database.select(database.documents)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (doc != null) {
      final file = File(doc.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      await (database.delete(database.documents)..where((t) => t.id.equals(id))).go();
    }
  }
}
