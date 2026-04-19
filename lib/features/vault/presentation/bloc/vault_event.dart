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
