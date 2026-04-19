import 'package:equatable/equatable.dart';

class VaultDocument extends Equatable {
  final int id;
  final String fileName;
  final String filePath; // Path to encrypted blob
  final DateTime createdAt;

  const VaultDocument({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, fileName, filePath, createdAt];
}
