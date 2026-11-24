import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:hub/backup_crypto.dart';
import 'package:hub/hub_store.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> main(List<String> args) async {
  try {
    if (args.isEmpty) throw const FormatException(_usage);
    final exit = switch (args.first) {
      'backup' => await _backupCommand(args),
      'backup-encrypted' => await _backupEncryptedCommand(args),
      'verify-encrypted' => await _verifyEncryptedBackupCommand(args),
      'restore' => await _restoreCommand(args),
      'restore-encrypted' => await _restoreEncryptedCommand(args),
      'generate-backup-key' => await _generateBackupKeyCommand(args),
      'prune-backups' => await _pruneBackupsCommand(args),
      'prune-sync-events' => _pruneSyncEventsCommand(args),
      'migrate' => _migrateCommand(args),
      _ => throw const FormatException(_usage),
    };
    stdout.writeln(exit);
  } on Object catch (error) {
    stderr.writeln('Maintenance failed: $error');
    exitCode = 1;
  }
}

const _usage = '''
Usage:
  dart run bin/maintenance.dart backup <database> <backup-file>
  dart run bin/maintenance.dart backup-encrypted <database> <backup-file>
  dart run bin/maintenance.dart verify-encrypted <backup-file>
  dart run bin/maintenance.dart restore <database> <backup-file> --force
  dart run bin/maintenance.dart restore-encrypted <database> <backup-file> --force
  dart run bin/maintenance.dart generate-backup-key
  dart run bin/maintenance.dart prune-backups <directory> [keep-count=30]
  dart run bin/maintenance.dart prune-sync-events <database> [retention-days=90]
  dart run bin/maintenance.dart migrate <database>
''';

Future<String> _generateBackupKeyCommand(List<String> args) async {
  if (args.length != 1) throw const FormatException(_usage);
  final key = await AesGcm.with256bits().newSecretKey();
  return 'Store this 32-byte backup key securely; it cannot be recovered: '
      '${base64.encode(await key.extractBytes())}';
}

List<int> _backupKeyFromEnvironment() {
  final encoded = Platform.environment['POS_BACKUP_KEY_BASE64'];
  if (encoded == null || encoded.isEmpty) {
    throw const FormatException(
      'Set POS_BACKUP_KEY_BASE64 for encrypted backup commands.',
    );
  }
  late final List<int> key;
  try {
    key = base64.decode(encoded);
  } on FormatException {
    throw const FormatException(
      'POS_BACKUP_KEY_BASE64 must be standard Base64.',
    );
  }
  if (key.length != 32) {
    throw const FormatException(
      'POS_BACKUP_KEY_BASE64 must decode to exactly 32 bytes.',
    );
  }
  return key;
}

String _migrateCommand(List<String> args) {
  if (args.length != 2) throw const FormatException(_usage);
  final store = HubStore.open(args[1]);
  try {
    return 'Hub database is at schema version ${store.schemaVersion}.';
  } finally {
    store.close();
  }
}

Future<String> _backupCommand(List<String> args) async {
  if (args.length != 3) throw const FormatException(_usage);
  final databasePath = args[1];
  final backupPath = args[2];
  if (_samePath(databasePath, backupPath)) {
    throw const FormatException(
      'The backup path must differ from the database path.',
    );
  }
  final sourceFile = File(databasePath);
  if (!await sourceFile.exists()) {
    throw FileSystemException('The hub database does not exist.', databasePath);
  }
  final destination = File(backupPath);
  if (await destination.exists()) {
    throw FileSystemException('The backup file already exists.', backupPath);
  }
  await destination.parent.create(recursive: true);
  await _copyDatabaseWithSqlite(sourceFile, destination);
  _validateDatabase(backupPath);
  return 'Created and validated backup: ${destination.absolute.path}';
}

Future<String> _backupEncryptedCommand(List<String> args) async {
  if (args.length != 3) throw const FormatException(_usage);
  final databasePath = args[1];
  final backupPath = args[2];
  if (_samePath(databasePath, backupPath)) {
    throw const FormatException(
      'The backup path must differ from the database path.',
    );
  }
  final source = File(databasePath);
  if (!await source.exists()) {
    throw FileSystemException('The hub database does not exist.', databasePath);
  }
  final destination = File(backupPath);
  if (await destination.exists()) {
    throw FileSystemException('The backup file already exists.', backupPath);
  }

  final key = _backupKeyFromEnvironment();
  final temporaryDirectory = await _createPrivateTemporaryDirectory(
    destination.parent,
  );
  try {
    final snapshot = File('${temporaryDirectory.path}/snapshot.sqlite');
    await _copyDatabaseWithSqlite(source, snapshot);
    _validateDatabase(snapshot.path);
    await encryptBackupFile(
      source: snapshot,
      destination: destination,
      keyBytes: key,
    );

    final verified = File('${temporaryDirectory.path}/verified.sqlite');
    await decryptBackupFile(
      source: destination,
      destination: verified,
      keyBytes: key,
    );
    _validateDatabase(verified.path);
    return 'Created and validated encrypted backup: '
        '${destination.absolute.path}; key fingerprint is embedded in the file.';
  } finally {
    await temporaryDirectory.delete(recursive: true);
  }
}

Future<String> _verifyEncryptedBackupCommand(List<String> args) async {
  if (args.length != 2) throw const FormatException(_usage);
  final backup = File(args[1]);
  final key = _backupKeyFromEnvironment();
  final temporaryDirectory = await _createPrivateTemporaryDirectory(
    backup.parent,
  );
  try {
    final verified = File('${temporaryDirectory.path}/verified.sqlite');
    await decryptBackupFile(
      source: backup,
      destination: verified,
      keyBytes: key,
    );
    _validateDatabase(verified.path);
    return 'Encrypted backup authenticated and SQLite integrity check passed.';
  } finally {
    await temporaryDirectory.delete(recursive: true);
  }
}

Future<String> _restoreCommand(List<String> args) async {
  if (args.length != 4 || args[3] != '--force') {
    throw const FormatException('Restore requires --force.\n$_usage');
  }
  final databasePath = args[1];
  final backupPath = args[2];
  if (_samePath(databasePath, backupPath)) {
    throw const FormatException(
      'The restore source must differ from the database path.',
    );
  }
  _validateDatabase(backupPath);
  return _restoreVerifiedDatabase(databasePath, backupPath);
}

Future<String> _restoreEncryptedCommand(List<String> args) async {
  if (args.length != 4 || args[3] != '--force') {
    throw const FormatException('Restore requires --force.\n$_usage');
  }
  final databasePath = args[1];
  final backupPath = args[2];
  if (_samePath(databasePath, backupPath)) {
    throw const FormatException(
      'The restore source must differ from the database path.',
    );
  }

  final key = _backupKeyFromEnvironment();
  final backup = File(backupPath);
  final temporaryDirectory = await _createPrivateTemporaryDirectory(
    File(databasePath).parent,
  );
  try {
    final decrypted = File('${temporaryDirectory.path}/decrypted.sqlite');
    await decryptBackupFile(
      source: backup,
      destination: decrypted,
      keyBytes: key,
    );
    _validateDatabase(decrypted.path);
    return await _restoreVerifiedDatabase(
      databasePath,
      decrypted.path,
      displayBackupPath: backupPath,
    );
  } finally {
    await temporaryDirectory.delete(recursive: true);
  }
}

Future<String> _restoreVerifiedDatabase(
  String databasePath,
  String backupPath, {
  String? displayBackupPath,
}) async {
  final target = File(databasePath);
  await target.parent.create(recursive: true);
  final timestamp = _timestamp();
  final recoveryPath =
      '${target.parent.path}${Platform.pathSeparator}open-pos-pre-restore-$timestamp.sqlite';
  if (await target.exists()) {
    await _copyDatabaseWithSqlite(target, File(recoveryPath));
    _validateDatabase(recoveryPath);
  }
  final temporary = File('$databasePath.restore-$timestamp.tmp');
  await File(backupPath).copy(temporary.path);
  _validateDatabase(temporary.path);
  await _removeIfExists(File('$databasePath-wal'));
  await _removeIfExists(File('$databasePath-shm'));
  if (await target.exists()) await target.delete();
  await temporary.rename(target.path);
  return 'Restored database from '
      '${File(displayBackupPath ?? backupPath).absolute.path}.'
      '${await File(recoveryPath).exists() ? ' Pre-restore recovery copy: ${File(recoveryPath).absolute.path}.' : ''}';
}

Future<String> _pruneBackupsCommand(List<String> args) async {
  if (args.length < 2 || args.length > 3) throw const FormatException(_usage);
  final keep = args.length == 3 ? int.tryParse(args[2]) : 30;
  if (keep == null || keep < 1) {
    throw const FormatException(
      'Backup retention must keep at least one file.',
    );
  }
  final directory = Directory(args[1]);
  if (!await directory.exists()) {
    throw FileSystemException(
      'Backup directory does not exist.',
      directory.path,
    );
  }
  final files = <File>[];
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is File &&
        RegExp(
          r'^open-pos-.*\.sqlite(?:\.enc)?$',
        ).hasMatch(_basename(entry.path))) {
      files.add(entry);
    }
  }
  final ordered = <({File file, DateTime modified})>[];
  for (final file in files) {
    ordered.add((file: file, modified: await file.lastModified()));
  }
  ordered.sort((a, b) => b.modified.compareTo(a.modified));
  final removed = ordered.skip(keep).toList(growable: false);
  for (final item in removed) {
    await item.file.delete();
  }
  return 'Retained ${ordered.length - removed.length} backups and removed ${removed.length} older files.';
}

Future<Directory> _createPrivateTemporaryDirectory(Directory parent) async {
  await parent.create(recursive: true);
  final directory = await parent.createTemp('.open-pos-backup-');
  if (!Platform.isWindows) {
    final permissions = (await directory.stat()).mode & 0x1ff;
    if ((permissions & 0x3f) != 0 || (permissions & 0x1c0) != 0x1c0) {
      await directory.delete(recursive: true);
      throw FileSystemException(
        'The temporary backup directory is not private.',
        directory.path,
      );
    }
  }
  return directory;
}

String _pruneSyncEventsCommand(List<String> args) {
  if (args.length < 2 || args.length > 3) throw const FormatException(_usage);
  final retentionDays = args.length == 3 ? int.tryParse(args[2]) : 90;
  if (retentionDays == null || retentionDays < 1) {
    throw const FormatException(
      'Sync event retention must be at least one day.',
    );
  }
  final path = args[1];
  final database = sqlite3.open(path);
  try {
    final minimumCursor =
        database.select('''
      SELECT MIN(COALESCE(sync_cursors.cursor, 0)) AS cursor
      FROM registers
      LEFT JOIN sync_cursors ON sync_cursors.register_id = registers.id
    ''').first['cursor']
            as int?;
    final maximumCursor =
        database
                .select(
                  'SELECT COALESCE(MAX(cursor), 0) AS cursor FROM sync_events',
                )
                .first['cursor']
            as int;
    final acknowledgedThrough = minimumCursor ?? maximumCursor;
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: retentionDays))
        .toIso8601String();
    final before =
        database.select(
              'SELECT COUNT(*) AS count FROM sync_events WHERE cursor <= ? AND created_at < ?',
              [acknowledgedThrough, cutoff],
            ).first['count']
            as int;
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute(
        'DELETE FROM sync_events WHERE cursor <= ? AND created_at < ?',
        [acknowledgedThrough, cutoff],
      );
      database.execute('COMMIT');
    } on Object {
      database.execute('ROLLBACK');
      rethrow;
    }
    return 'Pruned $before acknowledged sync events older than $retentionDays days. Audit records were retained.';
  } finally {
    database.close();
  }
}

Future<void> _copyDatabaseWithSqlite(
  File sourceFile,
  File destinationFile,
) async {
  final source = sqlite3.open(sourceFile.path);
  final destination = sqlite3.open(destinationFile.path);
  try {
    await source.backup(destination).drain<void>();
  } finally {
    destination.close();
    source.close();
  }
}

void _validateDatabase(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('Database file does not exist.', path);
  }
  final database = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final result = database.select('PRAGMA integrity_check');
    if (result.isEmpty || result.first.values.first != 'ok') {
      throw FormatException('SQLite integrity check failed for $path.');
    }
    final hasTables = database.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' LIMIT 1",
    );
    if (hasTables.isEmpty) {
      throw FormatException('The database $path has no tables.');
    }
  } finally {
    database.close();
  }
}

Future<void> _removeIfExists(File file) async {
  if (await file.exists()) await file.delete();
}

String _timestamp() =>
    DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');

String _basename(String path) => path.split(Platform.pathSeparator).last;

bool _samePath(String first, String second) {
  String canonical(String path) => Uri.file(
    File(path).absolute.path,
  ).normalizePath().toFilePath(windows: Platform.isWindows);
  final a = canonical(first);
  final b = canonical(second);
  return Platform.isWindows ? a.toLowerCase() == b.toLowerCase() : a == b;
}
