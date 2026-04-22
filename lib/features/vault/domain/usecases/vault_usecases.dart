import 'dart:io';
import 'package:cipherscribe/core/error/failures.dart';
import 'package:cipherscribe/features/vault/domain/entities/vault_document.dart';
import 'package:cipherscribe/features/vault/domain/repositories/vault_repository.dart';
import 'package:cryptography/cryptography.dart';

class ImportDocumentUseCase {
  final VaultRepository repository;

  ImportDocumentUseCase(this.repository);

  Future<Result<VaultDocument, Failure>> call(File file, SecretKey sessionKey) async {
    return await repository.importDocument(file, sessionKey);
  }
}


class GetDocumentsUseCase {
  final VaultRepository repository;

  GetDocumentsUseCase(this.repository);

  Future<Result<List<VaultDocument>, Failure>> call() async {
    return await repository.getDocuments();
  }
}

class DeleteDocumentUseCase {
  final VaultRepository repository;

  DeleteDocumentUseCase(this.repository);

  Future<Result<void, Failure>> call(int id) async {
    return await repository.deleteDocument(id);
  }
}

class RenameDocumentUseCase {
  final VaultRepository repository;

  RenameDocumentUseCase(this.repository);

  Future<Result<void, Failure>> call(int id, String newName) async {
    return await repository.renameDocument(id, newName);
  }
}
