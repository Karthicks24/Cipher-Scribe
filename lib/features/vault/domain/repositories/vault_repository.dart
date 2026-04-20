import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:cipherscribe/core/error/failures.dart';
import 'package:cipherscribe/features/vault/domain/entities/vault_document.dart';

abstract class VaultRepository {
  Future<Result<List<VaultDocument>, Failure>> getDocuments();
  Future<Result<VaultDocument, Failure>> importDocument(File file, SecretKey sessionKey);
  Future<Result<void, Failure>> deleteDocument(int id);
}

