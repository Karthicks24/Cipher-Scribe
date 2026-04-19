import 'dart:io';
import 'package:cipherscribe/core/error/failures.dart';
import 'package:cipherscribe/features/vault/domain/entities/vault_document.dart';

abstract class VaultRepository {
  Future<Result<List<VaultDocument>, Failure>> getDocuments();
  Future<Result<VaultDocument, Failure>> importDocument(File file);
  Future<Result<void, Failure>> deleteDocument(int id);
}
