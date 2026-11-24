import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pos_domain/pos_domain.dart';

abstract interface class SessionVault {
  Future<HubSession?> read();
  Future<void> write(HubSession session);
  Future<void> clear();
}

class SecureSessionVault implements SessionVault {
  SecureSessionVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'open_pos_hub_session';
  final FlutterSecureStorage _storage;

  @override
  Future<HubSession?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    try {
      return HubSession.fromJson(jsonDecode(value) as Map<String, Object?>);
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(HubSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemorySessionVault implements SessionVault {
  MemorySessionVault([this.session]);

  HubSession? session;

  @override
  Future<HubSession?> read() async => session;

  @override
  Future<void> write(HubSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}
