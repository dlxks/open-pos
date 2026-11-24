import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File database;
  late File encryptedBackup;

  const key = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
  const wrongKey = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('open-pos-maintenance-');
    database = File('${directory.path}/hub.sqlite');
    encryptedBackup = File('${directory.path}/open-pos-test.sqlite.enc');
    final store = sqlite3.open(database.path);
    store.execute('CREATE TABLE backup_probe (value TEXT NOT NULL)');
    store.execute("INSERT INTO backup_probe(value) VALUES ('original')");
    store.close();
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'encrypted backup can be verified and restored with recovery copy',
    () async {
      final create = await _runMaintenance([
        'backup-encrypted',
        database.path,
        encryptedBackup.path,
      ], key: key);
      expect(create.exitCode, 0, reason: create.stderr.toString());
      expect(create.stdout, contains('Created and validated encrypted backup'));
      expect(await encryptedBackup.exists(), isTrue);
      expect(await encryptedBackup.length(), greaterThan(44));

      final verification = await _runMaintenance([
        'verify-encrypted',
        encryptedBackup.path,
      ], key: key);
      expect(verification.exitCode, 0, reason: verification.stderr.toString());
      expect(verification.stdout, contains('SQLite integrity check passed'));

      final wrongKeyAttempt = await _runMaintenance([
        'restore-encrypted',
        database.path,
        encryptedBackup.path,
        '--force',
      ], key: wrongKey);
      expect(wrongKeyAttempt.exitCode, 1);
      expect(_probeValue(database), 'original');

      final live = sqlite3.open(database.path);
      live.execute("UPDATE backup_probe SET value = 'changed'");
      live.close();

      final restore = await _runMaintenance([
        'restore-encrypted',
        database.path,
        encryptedBackup.path,
        '--force',
      ], key: key);
      expect(restore.exitCode, 0, reason: restore.stderr.toString());
      expect(restore.stdout, contains('Restored database from'));
      expect(restore.stdout, contains('Pre-restore recovery copy'));
      expect(_probeValue(database), 'original');
      expect(
        directory.listSync().whereType<File>().any(
          (file) => file.basename.startsWith('open-pos-pre-restore-'),
        ),
        isTrue,
      );
    },
  );

  test('generated backup key is a random 32-byte Base64 value', () async {
    final result = await _runMaintenance(['generate-backup-key']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final encoded = RegExp(
      r'[A-Za-z0-9+/]{43}=',
    ).firstMatch(result.stdout.toString())?.group(0);
    expect(encoded, isNotNull);
    expect(base64.decode(encoded!).length, 32);
  });

  test('backup pruning includes encrypted SQLite files', () async {
    final older = File('${directory.path}/open-pos-old.sqlite.enc');
    final newer = File('${directory.path}/open-pos-new.sqlite.enc');
    await older.writeAsBytes([1]);
    await newer.writeAsBytes([2]);
    await older.setLastModified(DateTime.utc(2020));
    await newer.setLastModified(DateTime.utc(2021));

    final result = await _runMaintenance([
      'prune-backups',
      directory.path,
      '1',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(await older.exists(), isFalse);
    expect(await newer.exists(), isTrue);
  });
}

Future<ProcessResult> _runMaintenance(List<String> arguments, {String? key}) {
  final environment = <String, String>{};
  if (key != null) environment['POS_BACKUP_KEY_BASE64'] = key;
  if (key == null) environment['POS_BACKUP_KEY_BASE64'] = '';

  return Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/maintenance.dart', ...arguments],
    workingDirectory: Directory.current.path,
    environment: environment,
  );
}

String _probeValue(File database) {
  final store = sqlite3.open(database.path);
  try {
    return store.select('SELECT value FROM backup_probe').single['value']
        as String;
  } finally {
    store.close();
  }
}

extension on FileSystemEntity {
  String get basename => uri.pathSegments.where((part) => part.isNotEmpty).last;
}
