import 'dart:io';
import 'package:cipherscribe/core/error/failures.dart';
import 'package:cipherscribe/features/vault/domain/entities/vault_document.dart';
import 'package:cipherscribe/features/vault/domain/repositories/vault_repository.dart';
import 'package:cipherscribe/features/vault/data/datasources/vault_local_datasource.dart';
import 'package:cryptography/cryptography.dart';

class VaultRepositoryImpl implements VaultRepository {
  final VaultLocalDataSource localDataSource;

  VaultRepositoryImpl(this.localDataSource);

  @override
  Future<Result<List<VaultDocument>, Failure>> getDocuments() async {
    try {
      final documents = await localDataSource.getDocuments();
      final entities = documents.map((doc) => VaultDocument(
        id: doc.id,
        fileName: doc.fileName,
        filePath: doc.filePath,
        createdAt: doc.createdAt,
      )).toList();
      return Success<List<VaultDocument>, Failure>(entities);
    } catch (e) {
      return ErrorResult<List<VaultDocument>, Failure>(StorageFailure());
    }
  }



  @override
  Future<Result<VaultDocument, Failure>> importDocument(File file, SecretKey sessionKey) async {
    try {
      final storedDocument = await localDataSource.importDocument(file, sessionKey);
      final entity = VaultDocument(
        id: storedDocument.id,
        fileName: storedDocument.fileName,
        filePath: storedDocument.filePath,
        createdAt: storedDocument.createdAt,
      );
      return Success<VaultDocument, Failure>(entity);
    } catch (e) {
      return ErrorResult<VaultDocument, Failure>(CryptoFailure());
    }
  }


  @override
  Future<Result<void, Failure>> deleteDocument(int id) async {
    try {
      await localDataSource.deleteDocument(id);
      return Success<void, Failure>(null);
    } catch (e) {
      return ErrorResult<void, Failure>(StorageFailure());
    }
  }
}
