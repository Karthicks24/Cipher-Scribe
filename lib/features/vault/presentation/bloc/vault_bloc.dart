import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:cipherscribe/features/vault/domain/entities/vault_document.dart';
import 'package:cipherscribe/features/vault/domain/usecases/vault_usecases.dart';
import 'package:cipherscribe/core/error/failures.dart';

import 'package:cryptography/cryptography.dart';

part 'vault_event.dart';
part 'vault_state.dart';

class VaultBloc extends Bloc<VaultEvent, VaultState> {
  final GetDocumentsUseCase getDocuments;
  final ImportDocumentUseCase importDocument;
  final DeleteDocumentUseCase deleteDocument;
  final RenameDocumentUseCase renameDocument;
  final SecretKey sessionKey;

  VaultBloc({
    required this.getDocuments,
    required this.importDocument,
    required this.deleteDocument,
    required this.renameDocument,
    required this.sessionKey,
  }) : super(VaultInitial()) {
    on<LoadVaultDocuments>(_onLoadDocuments);
    on<ImportNewDocument>(_onImportDocument);
    on<DeleteDocument>(_onDeleteDocument);
    on<RenameDocument>(_onRenameDocument);
  }

  Future<void> _onLoadDocuments(LoadVaultDocuments event, Emitter<VaultState> emit) async {
    emit(VaultLoading());
    final result = await getDocuments();
    if (result is Success<List<VaultDocument>, Failure>) {
      emit(VaultLoaded(result.value));
    } else if (result is ErrorResult<List<VaultDocument>, Failure>) {
      emit(const VaultError('Failed to load documents from secure storage'));
    }
  }

  Future<void> _onImportDocument(ImportNewDocument event, Emitter<VaultState> emit) async {
    final currentState = state;
    if (currentState is VaultLoaded) {
      emit(VaultLoading());
      final result = await importDocument(event.file, sessionKey);
      
      if (result is Success<VaultDocument, Failure>) {
        final updatedList = List<VaultDocument>.from(currentState.documents)..add(result.value);
        emit(VaultLoaded(updatedList));
      } else {
        emit(const VaultError('Failed to uniquely encrypt and store document'));
        emit(currentState); // Revert to loaded
      }
    } else {
      // If not loaded yet, just ignore or load first
      add(LoadVaultDocuments());
    }
  }
  Future<void> _onDeleteDocument(DeleteDocument event, Emitter<VaultState> emit) async {
    final currentState = state;
    if (currentState is VaultLoaded) {
      final result = await deleteDocument(event.id);
      if (result is Success<void, Failure>) {
        final updatedList = currentState.documents.where((doc) => doc.id != event.id).toList();
        emit(VaultLoaded(updatedList));
      } else {
        emit(const VaultError('Failed to delete document'));
        emit(currentState);
      }
    }
  }

  Future<void> _onRenameDocument(RenameDocument event, Emitter<VaultState> emit) async {
    final currentState = state;
    if (currentState is VaultLoaded) {
      final result = await renameDocument(event.id, event.newName);
      if (result is Success<void, Failure>) {
        final updatedList = currentState.documents.map((doc) {
          if (doc.id == event.id) {
            return VaultDocument(
              id: doc.id,
              fileName: event.newName,
              filePath: doc.filePath,
              fileType: doc.fileType,
              fileSize: doc.fileSize,
              createdAt: doc.createdAt,
            );
          }
          return doc;
        }).toList();
        emit(VaultLoaded(updatedList));
      } else {
        emit(const VaultError('Failed to rename document'));
        emit(currentState);
      }
    }
  }
}
