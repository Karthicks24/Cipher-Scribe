import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:cipherscribe/core/database/database.dart';
import 'package:cipherscribe/services/crypto_service.dart';

abstract class VaultLocalDataSource {
  Future<List<Document>> getDocuments();
  Future<Document> importDocument(File file, SecretKey sessionKey);
  Future<void> deleteDocument(int id);
  Future<void> renameDocument(int id, String newName);
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
  Future<Document> importDocument(File file, SecretKey sessionKey) async {
    final fileName = p.basename(file.path);
    final fileSize = await file.length();
    final extension = p.extension(file.path).toLowerCase();
    
    String fileType = 'other';
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(extension)) {
      fileType = 'image';
    } else if (extension == '.pdf') {
      fileType = 'pdf';
    }

    final clearText = await file.readAsBytes();
    
    // Encrypt file using the Master DEK (sessionKey)
    final encryptedData = await cryptoService.encryptData(clearText.toList(), sessionKey);
    
    // Securely wipe cleartext from memory
    cryptoService.wipeRAM(clearText);

    // Save encrypted blob to app storage
    final appDir = await getApplicationDocumentsDirectory();
    final blobDir = Directory(p.join(appDir.path, 'blobs'));
    if (!await blobDir.exists()) await blobDir.create(recursive: true);

    final encryptedFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName.scribeblob';
    final encryptedFile = File(p.join(blobDir.path, encryptedFileName));
    await encryptedFile.writeAsBytes(encryptedData);

    // Insert metadata into Drift
    final document = await database.into(database.documents).insertReturning(
      DocumentsCompanion.insert(
        fileName: fileName,
        filePath: encryptedFile.path,
        fileType: Value(fileType),
        fileSize: Value(fileSize),
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
  @override
  Future<void> renameDocument(int id, String newName) async {
    await (database.update(database.documents)..where((t) => t.id.equals(id))).write(
      DocumentsCompanion(fileName: Value(newName)),
    );
  }
}

