import 'dart:io';
import 'package:cipherscribe/core/error/failures.dart';
import 'package:cipherscribe/features/vault/domain/entities/vault_document.dart';
import 'package:cipherscribe/features/vault/domain/repositories/vault_repository.dart';

class ImportDocumentUseCase {
  final VaultRepository repository;

  ImportDocumentUseCase(this.repository);

  Future<Result<VaultDocument, Failure>> call(File file) async {
    return await repository.importDocument(file);
  }
}

class GetDocumentsUseCase {
  final VaultRepository repository;

  GetDocumentsUseCase(this.repository);

  Future<Result<List<VaultDocument>, Failure>> call() async {
    return await repository.getDocuments();
  }
}
