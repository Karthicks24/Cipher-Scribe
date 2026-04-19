import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'database.g.dart';

class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fileName => text()();
  TextColumn get filePath => text()(); // path to the encrypted file chunk
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Documents])
class AppDatabase extends _$AppDatabase {
  final String dbPassword;

  AppDatabase(this.dbPassword) : super(_openConnection(dbPassword));

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection(String password) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'vault.sqlite'));

    // Apply sqlcipher PRAGMA to encrypt the database
    return NativeDatabase.createInBackground(file, setup: (db) {
      db.execute("PRAGMA key = '$password';");
    });
  });
}
