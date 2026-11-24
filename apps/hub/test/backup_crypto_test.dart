import 'dart:io';
import 'dart:typed_data';

import 'package:hub/backup_crypto.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File source;
  late File encrypted;
  late File decrypted;
  final key = List<int>.generate(32, (index) => index * 7 % 256);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'open-pos-backup-crypto-',
    );
    source = File('${directory.path}/source.sqlite');
    encrypted = File('${directory.path}/backup.sqlite.enc');
    decrypted = File('${directory.path}/decrypted.sqlite');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('encrypts and decrypts files larger than one record', () async {
    final original = List<int>.generate(
      1024 * 1024 + 317,
      (index) => index % 251,
    );
    await source.writeAsBytes(original);

    await encryptBackupFile(
      source: source,
      destination: encrypted,
      keyBytes: key,
    );
    await decryptBackupFile(
      source: encrypted,
      destination: decrypted,
      keyBytes: key,
    );

    expect(
      (await encrypted.readAsBytes()).take(16).toList(),
      isNot(original.take(16).toList()),
    );
    expect(await decrypted.readAsBytes(), original);
  });

  test('rejects the wrong key without leaving plaintext', () async {
    await source.writeAsBytes(List<int>.generate(4096, (index) => index % 251));
    await encryptBackupFile(
      source: source,
      destination: encrypted,
      keyBytes: key,
    );

    await expectLater(
      decryptBackupFile(
        source: encrypted,
        destination: decrypted,
        keyBytes: List<int>.filled(32, 9),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await decrypted.exists(), isFalse);
  });

  test(
    'rejects tampered or truncated records and removes partial output',
    () async {
      await source.writeAsBytes(
        List<int>.generate(8192, (index) => index % 251),
      );
      await encryptBackupFile(
        source: source,
        destination: encrypted,
        keyBytes: key,
      );
      final bytes = await encrypted.readAsBytes();
      bytes[bytes.length - 1] ^= 1;
      final tampered = File('${directory.path}/tampered.sqlite.enc');
      await tampered.writeAsBytes(bytes);

      await expectLater(
        decryptBackupFile(
          source: tampered,
          destination: decrypted,
          keyBytes: key,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await decrypted.exists(), isFalse);

      final truncated = File('${directory.path}/truncated.sqlite.enc');
      await truncated.writeAsBytes(bytes.sublist(0, bytes.length - 9));
      await expectLater(
        decryptBackupFile(
          source: truncated,
          destination: decrypted,
          keyBytes: key,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await decrypted.exists(), isFalse);
    },
  );

  test('authenticates encrypted record ordering', () async {
    await source.writeAsBytes(
      List<int>.generate(1024 * 1024 + 37, (index) => index % 251),
    );
    await encryptBackupFile(
      source: source,
      destination: encrypted,
      keyBytes: key,
    );
    final bytes = await encrypted.readAsBytes();
    const firstStart = 16;
    final firstEnd = _recordEnd(bytes, firstStart);
    final secondEnd = _recordEnd(bytes, firstEnd);
    final reordered = BytesBuilder(copy: false)
      ..add(bytes.sublist(0, firstStart))
      ..add(bytes.sublist(firstEnd, secondEnd))
      ..add(bytes.sublist(firstStart, firstEnd))
      ..add(bytes.sublist(secondEnd));
    final reorderedFile = File('${directory.path}/reordered.sqlite.enc');
    await reorderedFile.writeAsBytes(reordered.takeBytes());

    await expectLater(
      decryptBackupFile(
        source: reorderedFile,
        destination: decrypted,
        keyBytes: key,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await decrypted.exists(), isFalse);
  });

  test('requires a 256-bit key and never overwrites a backup', () async {
    await source.writeAsBytes([1, 2, 3]);
    await expectLater(
      encryptBackupFile(
        source: source,
        destination: encrypted,
        keyBytes: List<int>.filled(16, 1),
      ),
      throwsA(isA<FormatException>()),
    );

    await encrypted.writeAsBytes([7]);
    await expectLater(
      encryptBackupFile(source: source, destination: encrypted, keyBytes: key),
      throwsA(isA<FileSystemException>()),
    );
    expect(await encrypted.readAsBytes(), [7]);
  });
}

int _recordEnd(Uint8List bytes, int offset) {
  final length = ByteData.sublistView(bytes).getUint32(offset, Endian.big);
  return offset + 4 + 12 + length + 16;
}
