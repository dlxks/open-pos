import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const _magic = <int>[0x4f, 0x50, 0x4f, 0x53, 0x42, 0x4b, 0x50, 0x31];
const _keyFingerprintLength = 8;
const _nonceLength = 12;
const _macLength = 16;
const _chunkSize = 1024 * 1024;

/// Encrypts a file in authenticated 1 MiB chunks using AES-256-GCM.
///
/// Each record has a random nonce and an authenticated sequence number. A
/// final authenticated marker detects truncated files, including truncation
/// exactly at a chunk boundary.
Future<void> encryptBackupFile({
  required File source,
  required File destination,
  required List<int> keyBytes,
}) async {
  _validateKey(keyBytes);
  if (!await source.exists()) {
    throw FileSystemException('Backup source does not exist.', source.path);
  }

  final key = SecretKey(keyBytes);
  final algorithm = AesGcm.with256bits();
  final fingerprint = await _keyFingerprint(keyBytes);
  final header = <int>[..._magic, ...fingerprint];
  final input = await source.open();
  RandomAccessFile? output;
  var ownsDestination = false;
  var completed = false;

  try {
    await destination.parent.create(recursive: true);
    await destination.create(exclusive: true);
    ownsDestination = true;
    output = await destination.open(mode: FileMode.writeOnly);
    await output.writeFrom(header);

    var counter = 0;
    while (true) {
      final clearText = await input.read(_chunkSize);
      if (clearText.isEmpty) break;

      final secretBox = await algorithm.encrypt(
        clearText,
        secretKey: key,
        aad: _associatedData(header, counter, clearText.length, isFinal: false),
      );
      _validateSecretBox(secretBox);
      await output.writeFrom(_encodeUint32(clearText.length));
      await output.writeFrom(secretBox.nonce);
      await output.writeFrom(secretBox.cipherText);
      await output.writeFrom(secretBox.mac.bytes);
      counter++;
    }

    final finalBox = await algorithm.encrypt(
      const <int>[],
      secretKey: key,
      aad: _associatedData(header, counter, 0, isFinal: true),
    );
    _validateSecretBox(finalBox);
    await output.writeFrom(_encodeUint32(0));
    await output.writeFrom(finalBox.nonce);
    await output.writeFrom(finalBox.mac.bytes);
    await output.flush();
    await output.close();
    output = null;
    completed = true;
  } finally {
    await input.close();
    await output?.close();
    if (ownsDestination && !completed && await destination.exists()) {
      await destination.delete();
    }
  }
}

/// Decrypts and authenticates a backup, deleting partial plaintext on failure.
Future<void> decryptBackupFile({
  required File source,
  required File destination,
  required List<int> keyBytes,
}) async {
  _validateKey(keyBytes);
  if (!await source.exists()) {
    throw FileSystemException('Encrypted backup does not exist.', source.path);
  }

  final key = SecretKey(keyBytes);
  final algorithm = AesGcm.with256bits();
  final fingerprint = await _keyFingerprint(keyBytes);
  final input = await source.open();
  RandomAccessFile? output;
  var ownsDestination = false;
  var completed = false;

  try {
    final header = await _readExactly(
      input,
      _magic.length + _keyFingerprintLength,
    );
    if (!_matches(header.take(_magic.length), _magic)) {
      throw const FormatException('Encrypted backup format is not supported.');
    }
    final storedFingerprint = header.skip(_magic.length);
    if (!_matches(storedFingerprint, fingerprint)) {
      throw const FormatException(
        'The supplied key does not match this encrypted backup.',
      );
    }

    await destination.parent.create(recursive: true);
    await destination.create(exclusive: true);
    ownsDestination = true;
    output = await destination.open(mode: FileMode.writeOnly);

    var counter = 0;
    while (true) {
      final lengthBytes = await _readExactly(input, 4);
      final length = _decodeUint32(lengthBytes);
      if (length > _chunkSize) {
        throw const FormatException(
          'Encrypted backup contains an oversized record.',
        );
      }

      final nonce = await _readExactly(input, _nonceLength);
      final cipherText = await _readExactly(input, length);
      final macBytes = await _readExactly(input, _macLength);
      final isFinal = length == 0;
      final clearText = await _decryptRecord(
        algorithm: algorithm,
        key: key,
        cipherText: cipherText,
        nonce: nonce,
        macBytes: macBytes,
        aad: _associatedData(header, counter, length, isFinal: isFinal),
      );

      if (isFinal) {
        if (clearText.isNotEmpty || (await input.read(1)).isNotEmpty) {
          throw const FormatException(
            'Encrypted backup has invalid trailing data.',
          );
        }
        break;
      }
      if (clearText.length != length) {
        throw const FormatException(
          'Encrypted backup record length is invalid.',
        );
      }
      await output.writeFrom(clearText);
      counter++;
    }

    await output.flush();
    await output.close();
    output = null;
    completed = true;
  } finally {
    await input.close();
    await output?.close();
    if (ownsDestination && !completed && await destination.exists()) {
      await destination.delete();
    }
  }
}

void _validateKey(List<int> keyBytes) {
  if (keyBytes.length != 32) {
    throw const FormatException('Backup encryption key must contain 32 bytes.');
  }
}

Future<List<int>> _keyFingerprint(List<int> keyBytes) async {
  final digest = await Sha256().hash(keyBytes);
  return digest.bytes.take(_keyFingerprintLength).toList(growable: false);
}

void _validateSecretBox(SecretBox secretBox) {
  if (secretBox.nonce.length != _nonceLength ||
      secretBox.mac.bytes.length != _macLength) {
    throw const FormatException(
      'The AES-GCM implementation returned invalid metadata.',
    );
  }
}

Future<List<int>> _decryptRecord({
  required AesGcm algorithm,
  required SecretKey key,
  required List<int> cipherText,
  required List<int> nonce,
  required List<int> macBytes,
  required List<int> aad,
}) async {
  try {
    return await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: key,
      aad: aad,
    );
  } on Object {
    throw const FormatException(
      'Encrypted backup authentication failed; verify the key and file.',
    );
  }
}

List<int> _associatedData(
  List<int> header,
  int counter,
  int length, {
  required bool isFinal,
}) => [
  ...header,
  ..._encodeUint64(counter),
  ..._encodeUint32(length),
  if (isFinal) 1 else 0,
];

Uint8List _encodeUint32(int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value, Endian.big);
  return bytes;
}

Uint8List _encodeUint64(int value) {
  final bytes = Uint8List(8);
  ByteData.sublistView(bytes).setUint64(0, value, Endian.big);
  return bytes;
}

int _decodeUint32(List<int> bytes) =>
    ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0, Endian.big);

Future<Uint8List> _readExactly(RandomAccessFile input, int length) async {
  final builder = BytesBuilder(copy: false);
  var remaining = length;
  while (remaining > 0) {
    final bytes = await input.read(remaining);
    if (bytes.isEmpty) {
      throw const FormatException(
        'Encrypted backup is truncated or malformed.',
      );
    }
    builder.add(bytes);
    remaining -= bytes.length;
  }
  return builder.takeBytes();
}

bool _matches(Iterable<int> left, Iterable<int> right) {
  final leftBytes = left.toList(growable: false);
  final rightBytes = right.toList(growable: false);
  if (leftBytes.length != rightBytes.length) return false;
  var difference = 0;
  for (var index = 0; index < leftBytes.length; index++) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference == 0;
}
