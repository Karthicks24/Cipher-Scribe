part of 'vault_bloc.dart';

abstract class VaultEvent extends Equatable {
  const VaultEvent();

  @override
  List<Object> get props => [];
}

class LoadVaultDocuments extends VaultEvent {}

class ImportNewDocument extends VaultEvent {
  final File file;

  const ImportNewDocument(this.file);

  @override
  List<Object> get props => [file];
}

class DeleteDocument extends VaultEvent {
  final int id;

  const DeleteDocument(this.id);

  @override
  List<Object> get props => [id];
}

class RenameDocument extends VaultEvent {
  final int id;
  final String newName;

  const RenameDocument(this.id, this.newName);

  @override
  List<Object> get props => [id, newName];
}
