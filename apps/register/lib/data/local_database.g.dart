// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $LocalSalesTable extends LocalSales
    with TableInfo<$LocalSalesTable, LocalSale> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalCentsMeta = const VerificationMeta(
    'totalCents',
  );
  @override
  late final GeneratedColumn<int> totalCents = GeneratedColumn<int>(
    'total_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    payload,
    totalCents,
    createdAt,
    syncedAt,
    attempts,
    nextAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sales';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSale> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('total_cents')) {
      context.handle(
        _totalCentsMeta,
        totalCents.isAcceptableOrUnknown(data['total_cents']!, _totalCentsMeta),
      );
    } else if (isInserting) {
      context.missing(_totalCentsMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalSale map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSale(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      totalCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_cents'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $LocalSalesTable createAlias(String alias) {
    return $LocalSalesTable(attachedDatabase, alias);
  }
}

class LocalSale extends DataClass implements Insertable<LocalSale> {
  final String id;
  final String payload;
  final int totalCents;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;
  const LocalSale({
    required this.id,
    required this.payload,
    required this.totalCents,
    required this.createdAt,
    this.syncedAt,
    required this.attempts,
    this.nextAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['payload'] = Variable<String>(payload);
    map['total_cents'] = Variable<int>(totalCents);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  LocalSalesCompanion toCompanion(bool nullToAbsent) {
    return LocalSalesCompanion(
      id: Value(id),
      payload: Value(payload),
      totalCents: Value(totalCents),
      createdAt: Value(createdAt),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory LocalSale.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSale(
      id: serializer.fromJson<String>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
      totalCents: serializer.fromJson<int>(json['totalCents']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payload': serializer.toJson<String>(payload),
      'totalCents': serializer.toJson<int>(totalCents),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  LocalSale copyWith({
    String? id,
    String? payload,
    int? totalCents,
    DateTime? createdAt,
    Value<DateTime?> syncedAt = const Value.absent(),
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => LocalSale(
    id: id ?? this.id,
    payload: payload ?? this.payload,
    totalCents: totalCents ?? this.totalCents,
    createdAt: createdAt ?? this.createdAt,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  LocalSale copyWithCompanion(LocalSalesCompanion data) {
    return LocalSale(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
      totalCents: data.totalCents.present
          ? data.totalCents.value
          : this.totalCents,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSale(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('totalCents: $totalCents, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    payload,
    totalCents,
    createdAt,
    syncedAt,
    attempts,
    nextAttemptAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSale &&
          other.id == this.id &&
          other.payload == this.payload &&
          other.totalCents == this.totalCents &&
          other.createdAt == this.createdAt &&
          other.syncedAt == this.syncedAt &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError);
}

class LocalSalesCompanion extends UpdateCompanion<LocalSale> {
  final Value<String> id;
  final Value<String> payload;
  final Value<int> totalCents;
  final Value<DateTime> createdAt;
  final Value<DateTime?> syncedAt;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const LocalSalesCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.totalCents = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSalesCompanion.insert({
    required String id,
    required String payload,
    required int totalCents,
    required DateTime createdAt,
    this.syncedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       payload = Value(payload),
       totalCents = Value(totalCents),
       createdAt = Value(createdAt);
  static Insertable<LocalSale> custom({
    Expression<String>? id,
    Expression<String>? payload,
    Expression<int>? totalCents,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? syncedAt,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (totalCents != null) 'total_cents': totalCents,
      if (createdAt != null) 'created_at': createdAt,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSalesCompanion copyWith({
    Value<String>? id,
    Value<String>? payload,
    Value<int>? totalCents,
    Value<DateTime>? createdAt,
    Value<DateTime?>? syncedAt,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return LocalSalesCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
      totalCents: totalCents ?? this.totalCents,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (totalCents.present) {
      map['total_cents'] = Variable<int>(totalCents.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSalesCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('totalCents: $totalCents, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalProductsTable extends LocalProducts
    with TableInfo<$LocalProductsTable, LocalProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_products';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalProduct> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalProduct(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $LocalProductsTable createAlias(String alias) {
    return $LocalProductsTable(attachedDatabase, alias);
  }
}

class LocalProduct extends DataClass implements Insertable<LocalProduct> {
  final String id;
  final String payload;
  const LocalProduct({required this.id, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  LocalProductsCompanion toCompanion(bool nullToAbsent) {
    return LocalProductsCompanion(id: Value(id), payload: Value(payload));
  }

  factory LocalProduct.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalProduct(
      id: serializer.fromJson<String>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payload': serializer.toJson<String>(payload),
    };
  }

  LocalProduct copyWith({String? id, String? payload}) =>
      LocalProduct(id: id ?? this.id, payload: payload ?? this.payload);
  LocalProduct copyWithCompanion(LocalProductsCompanion data) {
    return LocalProduct(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalProduct(')
          ..write('id: $id, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalProduct &&
          other.id == this.id &&
          other.payload == this.payload);
}

class LocalProductsCompanion extends UpdateCompanion<LocalProduct> {
  final Value<String> id;
  final Value<String> payload;
  final Value<int> rowid;
  const LocalProductsCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalProductsCompanion.insert({
    required String id,
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       payload = Value(payload);
  static Insertable<LocalProduct> custom({
    Expression<String>? id,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalProductsCompanion copyWith({
    Value<String>? id,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return LocalProductsCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalProductsCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCatalogVersionsTable extends LocalCatalogVersions
    with TableInfo<$LocalCatalogVersionsTable, LocalCatalogVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCatalogVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, version];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_catalog_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCatalogVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalCatalogVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCatalogVersion(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  $LocalCatalogVersionsTable createAlias(String alias) {
    return $LocalCatalogVersionsTable(attachedDatabase, alias);
  }
}

class LocalCatalogVersion extends DataClass
    implements Insertable<LocalCatalogVersion> {
  final int id;
  final int version;
  const LocalCatalogVersion({required this.id, required this.version});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['version'] = Variable<int>(version);
    return map;
  }

  LocalCatalogVersionsCompanion toCompanion(bool nullToAbsent) {
    return LocalCatalogVersionsCompanion(
      id: Value(id),
      version: Value(version),
    );
  }

  factory LocalCatalogVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCatalogVersion(
      id: serializer.fromJson<int>(json['id']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'version': serializer.toJson<int>(version),
    };
  }

  LocalCatalogVersion copyWith({int? id, int? version}) =>
      LocalCatalogVersion(id: id ?? this.id, version: version ?? this.version);
  LocalCatalogVersion copyWithCompanion(LocalCatalogVersionsCompanion data) {
    return LocalCatalogVersion(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCatalogVersion(')
          ..write('id: $id, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, version);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCatalogVersion &&
          other.id == this.id &&
          other.version == this.version);
}

class LocalCatalogVersionsCompanion
    extends UpdateCompanion<LocalCatalogVersion> {
  final Value<int> id;
  final Value<int> version;
  const LocalCatalogVersionsCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
  });
  LocalCatalogVersionsCompanion.insert({
    this.id = const Value.absent(),
    required int version,
  }) : version = Value(version);
  static Insertable<LocalCatalogVersion> custom({
    Expression<int>? id,
    Expression<int>? version,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
    });
  }

  LocalCatalogVersionsCompanion copyWith({
    Value<int>? id,
    Value<int>? version,
  }) {
    return LocalCatalogVersionsCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCatalogVersionsCompanion(')
          ..write('id: $id, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }
}

class $LocalOperationalStateTable extends LocalOperationalState
    with TableInfo<$LocalOperationalStateTable, LocalOperationalStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalOperationalStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_operational_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalOperationalStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  LocalOperationalStateData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalOperationalStateData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $LocalOperationalStateTable createAlias(String alias) {
    return $LocalOperationalStateTable(attachedDatabase, alias);
  }
}

class LocalOperationalStateData extends DataClass
    implements Insertable<LocalOperationalStateData> {
  final String key;
  final String payload;
  const LocalOperationalStateData({required this.key, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  LocalOperationalStateCompanion toCompanion(bool nullToAbsent) {
    return LocalOperationalStateCompanion(
      key: Value(key),
      payload: Value(payload),
    );
  }

  factory LocalOperationalStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalOperationalStateData(
      key: serializer.fromJson<String>(json['key']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'payload': serializer.toJson<String>(payload),
    };
  }

  LocalOperationalStateData copyWith({String? key, String? payload}) =>
      LocalOperationalStateData(
        key: key ?? this.key,
        payload: payload ?? this.payload,
      );
  LocalOperationalStateData copyWithCompanion(
    LocalOperationalStateCompanion data,
  ) {
    return LocalOperationalStateData(
      key: data.key.present ? data.key.value : this.key,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalOperationalStateData(')
          ..write('key: $key, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalOperationalStateData &&
          other.key == this.key &&
          other.payload == this.payload);
}

class LocalOperationalStateCompanion
    extends UpdateCompanion<LocalOperationalStateData> {
  final Value<String> key;
  final Value<String> payload;
  final Value<int> rowid;
  const LocalOperationalStateCompanion({
    this.key = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalOperationalStateCompanion.insert({
    required String key,
    required String payload,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       payload = Value(payload);
  static Insertable<LocalOperationalStateData> custom({
    Expression<String>? key,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalOperationalStateCompanion copyWith({
    Value<String>? key,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return LocalOperationalStateCompanion(
      key: key ?? this.key,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalOperationalStateCompanion(')
          ..write('key: $key, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalStockOperationsTable extends LocalStockOperations
    with TableInfo<$LocalStockOperationsTable, LocalStockOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalStockOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    payload,
    createdAt,
    status,
    error,
    attempts,
    nextAttemptAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_stock_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalStockOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalStockOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalStockOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
    );
  }

  @override
  $LocalStockOperationsTable createAlias(String alias) {
    return $LocalStockOperationsTable(attachedDatabase, alias);
  }
}

class LocalStockOperation extends DataClass
    implements Insertable<LocalStockOperation> {
  final String id;
  final String payload;
  final DateTime createdAt;
  final String status;
  final String? error;
  final int attempts;
  final DateTime? nextAttemptAt;
  const LocalStockOperation({
    required this.id,
    required this.payload,
    required this.createdAt,
    required this.status,
    this.error,
    required this.attempts,
    this.nextAttemptAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    return map;
  }

  LocalStockOperationsCompanion toCompanion(bool nullToAbsent) {
    return LocalStockOperationsCompanion(
      id: Value(id),
      payload: Value(payload),
      createdAt: Value(createdAt),
      status: Value(status),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
    );
  }

  factory LocalStockOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalStockOperation(
      id: serializer.fromJson<String>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      status: serializer.fromJson<String>(json['status']),
      error: serializer.fromJson<String?>(json['error']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'status': serializer.toJson<String>(status),
      'error': serializer.toJson<String?>(error),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
    };
  }

  LocalStockOperation copyWith({
    String? id,
    String? payload,
    DateTime? createdAt,
    String? status,
    Value<String?> error = const Value.absent(),
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
  }) => LocalStockOperation(
    id: id ?? this.id,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    status: status ?? this.status,
    error: error.present ? error.value : this.error,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
  );
  LocalStockOperation copyWithCompanion(LocalStockOperationsCompanion data) {
    return LocalStockOperation(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      status: data.status.present ? data.status.value : this.status,
      error: data.error.present ? data.error.value : this.error,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalStockOperation(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    payload,
    createdAt,
    status,
    error,
    attempts,
    nextAttemptAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalStockOperation &&
          other.id == this.id &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.status == this.status &&
          other.error == this.error &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt);
}

class LocalStockOperationsCompanion
    extends UpdateCompanion<LocalStockOperation> {
  final Value<String> id;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<String> status;
  final Value<String?> error;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<int> rowid;
  const LocalStockOperationsCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalStockOperationsCompanion.insert({
    required String id,
    required String payload,
    required DateTime createdAt,
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<LocalStockOperation> custom({
    Expression<String>? id,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<String>? status,
    Expression<String>? error,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (status != null) 'status': status,
      if (error != null) 'error': error,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalStockOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? payload,
    Value<DateTime>? createdAt,
    Value<String>? status,
    Value<String?>? error,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
    Value<int>? rowid,
  }) {
    return LocalStockOperationsCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      error: error ?? this.error,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalStockOperationsCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCatalogOperationsTable extends LocalCatalogOperations
    with TableInfo<$LocalCatalogOperationsTable, LocalCatalogOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCatalogOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _basePayloadMeta = const VerificationMeta(
    'basePayload',
  );
  @override
  late final GeneratedColumn<String> basePayload = GeneratedColumn<String>(
    'base_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conflictPayloadMeta = const VerificationMeta(
    'conflictPayload',
  );
  @override
  late final GeneratedColumn<String> conflictPayload = GeneratedColumn<String>(
    'conflict_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expectedVersionMeta = const VerificationMeta(
    'expectedVersion',
  );
  @override
  late final GeneratedColumn<int> expectedVersion = GeneratedColumn<int>(
    'expected_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    productId,
    payload,
    basePayload,
    conflictPayload,
    expectedVersion,
    status,
    attempts,
    nextAttemptAt,
    error,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_catalog_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCatalogOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('base_payload')) {
      context.handle(
        _basePayloadMeta,
        basePayload.isAcceptableOrUnknown(
          data['base_payload']!,
          _basePayloadMeta,
        ),
      );
    }
    if (data.containsKey('conflict_payload')) {
      context.handle(
        _conflictPayloadMeta,
        conflictPayload.isAcceptableOrUnknown(
          data['conflict_payload']!,
          _conflictPayloadMeta,
        ),
      );
    }
    if (data.containsKey('expected_version')) {
      context.handle(
        _expectedVersionMeta,
        expectedVersion.isAcceptableOrUnknown(
          data['expected_version']!,
          _expectedVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedVersionMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalCatalogOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCatalogOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      basePayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_payload'],
      ),
      conflictPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_payload'],
      ),
      expectedVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_version'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LocalCatalogOperationsTable createAlias(String alias) {
    return $LocalCatalogOperationsTable(attachedDatabase, alias);
  }
}

class LocalCatalogOperation extends DataClass
    implements Insertable<LocalCatalogOperation> {
  final String id;
  final String productId;
  final String payload;
  final String? basePayload;
  final String? conflictPayload;
  final int expectedVersion;
  final String status;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? error;
  final DateTime createdAt;
  const LocalCatalogOperation({
    required this.id,
    required this.productId,
    required this.payload,
    this.basePayload,
    this.conflictPayload,
    required this.expectedVersion,
    required this.status,
    required this.attempts,
    this.nextAttemptAt,
    this.error,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || basePayload != null) {
      map['base_payload'] = Variable<String>(basePayload);
    }
    if (!nullToAbsent || conflictPayload != null) {
      map['conflict_payload'] = Variable<String>(conflictPayload);
    }
    map['expected_version'] = Variable<int>(expectedVersion);
    map['status'] = Variable<String>(status);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LocalCatalogOperationsCompanion toCompanion(bool nullToAbsent) {
    return LocalCatalogOperationsCompanion(
      id: Value(id),
      productId: Value(productId),
      payload: Value(payload),
      basePayload: basePayload == null && nullToAbsent
          ? const Value.absent()
          : Value(basePayload),
      conflictPayload: conflictPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(conflictPayload),
      expectedVersion: Value(expectedVersion),
      status: Value(status),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      createdAt: Value(createdAt),
    );
  }

  factory LocalCatalogOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCatalogOperation(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      payload: serializer.fromJson<String>(json['payload']),
      basePayload: serializer.fromJson<String?>(json['basePayload']),
      conflictPayload: serializer.fromJson<String?>(json['conflictPayload']),
      expectedVersion: serializer.fromJson<int>(json['expectedVersion']),
      status: serializer.fromJson<String>(json['status']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      error: serializer.fromJson<String?>(json['error']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'payload': serializer.toJson<String>(payload),
      'basePayload': serializer.toJson<String?>(basePayload),
      'conflictPayload': serializer.toJson<String?>(conflictPayload),
      'expectedVersion': serializer.toJson<int>(expectedVersion),
      'status': serializer.toJson<String>(status),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'error': serializer.toJson<String?>(error),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LocalCatalogOperation copyWith({
    String? id,
    String? productId,
    String? payload,
    Value<String?> basePayload = const Value.absent(),
    Value<String?> conflictPayload = const Value.absent(),
    int? expectedVersion,
    String? status,
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> error = const Value.absent(),
    DateTime? createdAt,
  }) => LocalCatalogOperation(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    payload: payload ?? this.payload,
    basePayload: basePayload.present ? basePayload.value : this.basePayload,
    conflictPayload: conflictPayload.present
        ? conflictPayload.value
        : this.conflictPayload,
    expectedVersion: expectedVersion ?? this.expectedVersion,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    error: error.present ? error.value : this.error,
    createdAt: createdAt ?? this.createdAt,
  );
  LocalCatalogOperation copyWithCompanion(
    LocalCatalogOperationsCompanion data,
  ) {
    return LocalCatalogOperation(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      payload: data.payload.present ? data.payload.value : this.payload,
      basePayload: data.basePayload.present
          ? data.basePayload.value
          : this.basePayload,
      conflictPayload: data.conflictPayload.present
          ? data.conflictPayload.value
          : this.conflictPayload,
      expectedVersion: data.expectedVersion.present
          ? data.expectedVersion.value
          : this.expectedVersion,
      status: data.status.present ? data.status.value : this.status,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      error: data.error.present ? data.error.value : this.error,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCatalogOperation(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('payload: $payload, ')
          ..write('basePayload: $basePayload, ')
          ..write('conflictPayload: $conflictPayload, ')
          ..write('expectedVersion: $expectedVersion, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    productId,
    payload,
    basePayload,
    conflictPayload,
    expectedVersion,
    status,
    attempts,
    nextAttemptAt,
    error,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCatalogOperation &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.payload == this.payload &&
          other.basePayload == this.basePayload &&
          other.conflictPayload == this.conflictPayload &&
          other.expectedVersion == this.expectedVersion &&
          other.status == this.status &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.error == this.error &&
          other.createdAt == this.createdAt);
}

class LocalCatalogOperationsCompanion
    extends UpdateCompanion<LocalCatalogOperation> {
  final Value<String> id;
  final Value<String> productId;
  final Value<String> payload;
  final Value<String?> basePayload;
  final Value<String?> conflictPayload;
  final Value<int> expectedVersion;
  final Value<String> status;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> error;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LocalCatalogOperationsCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.payload = const Value.absent(),
    this.basePayload = const Value.absent(),
    this.conflictPayload = const Value.absent(),
    this.expectedVersion = const Value.absent(),
    this.status = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.error = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCatalogOperationsCompanion.insert({
    required String id,
    required String productId,
    required String payload,
    this.basePayload = const Value.absent(),
    this.conflictPayload = const Value.absent(),
    required int expectedVersion,
    this.status = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.error = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       productId = Value(productId),
       payload = Value(payload),
       expectedVersion = Value(expectedVersion),
       createdAt = Value(createdAt);
  static Insertable<LocalCatalogOperation> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<String>? payload,
    Expression<String>? basePayload,
    Expression<String>? conflictPayload,
    Expression<int>? expectedVersion,
    Expression<String>? status,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? error,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (payload != null) 'payload': payload,
      if (basePayload != null) 'base_payload': basePayload,
      if (conflictPayload != null) 'conflict_payload': conflictPayload,
      if (expectedVersion != null) 'expected_version': expectedVersion,
      if (status != null) 'status': status,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (error != null) 'error': error,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCatalogOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? productId,
    Value<String>? payload,
    Value<String?>? basePayload,
    Value<String?>? conflictPayload,
    Value<int>? expectedVersion,
    Value<String>? status,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? error,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return LocalCatalogOperationsCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      payload: payload ?? this.payload,
      basePayload: basePayload ?? this.basePayload,
      conflictPayload: conflictPayload ?? this.conflictPayload,
      expectedVersion: expectedVersion ?? this.expectedVersion,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (basePayload.present) {
      map['base_payload'] = Variable<String>(basePayload.value);
    }
    if (conflictPayload.present) {
      map['conflict_payload'] = Variable<String>(conflictPayload.value);
    }
    if (expectedVersion.present) {
      map['expected_version'] = Variable<int>(expectedVersion.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCatalogOperationsCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('payload: $payload, ')
          ..write('basePayload: $basePayload, ')
          ..write('conflictPayload: $conflictPayload, ')
          ..write('expectedVersion: $expectedVersion, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalPaymentsTable extends LocalPayments
    with TableInfo<$LocalPaymentsTable, LocalPayment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _saleIdMeta = const VerificationMeta('saleId');
  @override
  late final GeneratedColumn<String> saleId = GeneratedColumn<String>(
    'sale_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    saleId,
    payload,
    syncedAt,
    attempts,
    nextAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalPayment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sale_id')) {
      context.handle(
        _saleIdMeta,
        saleId.isAcceptableOrUnknown(data['sale_id']!, _saleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_saleIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPayment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPayment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      saleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sale_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $LocalPaymentsTable createAlias(String alias) {
    return $LocalPaymentsTable(attachedDatabase, alias);
  }
}

class LocalPayment extends DataClass implements Insertable<LocalPayment> {
  final String id;
  final String saleId;
  final String payload;
  final DateTime? syncedAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;
  const LocalPayment({
    required this.id,
    required this.saleId,
    required this.payload,
    this.syncedAt,
    required this.attempts,
    this.nextAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sale_id'] = Variable<String>(saleId);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  LocalPaymentsCompanion toCompanion(bool nullToAbsent) {
    return LocalPaymentsCompanion(
      id: Value(id),
      saleId: Value(saleId),
      payload: Value(payload),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory LocalPayment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPayment(
      id: serializer.fromJson<String>(json['id']),
      saleId: serializer.fromJson<String>(json['saleId']),
      payload: serializer.fromJson<String>(json['payload']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'saleId': serializer.toJson<String>(saleId),
      'payload': serializer.toJson<String>(payload),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  LocalPayment copyWith({
    String? id,
    String? saleId,
    String? payload,
    Value<DateTime?> syncedAt = const Value.absent(),
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => LocalPayment(
    id: id ?? this.id,
    saleId: saleId ?? this.saleId,
    payload: payload ?? this.payload,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  LocalPayment copyWithCompanion(LocalPaymentsCompanion data) {
    return LocalPayment(
      id: data.id.present ? data.id.value : this.id,
      saleId: data.saleId.present ? data.saleId.value : this.saleId,
      payload: data.payload.present ? data.payload.value : this.payload,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPayment(')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('payload: $payload, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    saleId,
    payload,
    syncedAt,
    attempts,
    nextAttemptAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPayment &&
          other.id == this.id &&
          other.saleId == this.saleId &&
          other.payload == this.payload &&
          other.syncedAt == this.syncedAt &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError);
}

class LocalPaymentsCompanion extends UpdateCompanion<LocalPayment> {
  final Value<String> id;
  final Value<String> saleId;
  final Value<String> payload;
  final Value<DateTime?> syncedAt;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const LocalPaymentsCompanion({
    this.id = const Value.absent(),
    this.saleId = const Value.absent(),
    this.payload = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalPaymentsCompanion.insert({
    required String id,
    required String saleId,
    required String payload,
    this.syncedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       saleId = Value(saleId),
       payload = Value(payload);
  static Insertable<LocalPayment> custom({
    Expression<String>? id,
    Expression<String>? saleId,
    Expression<String>? payload,
    Expression<DateTime>? syncedAt,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (saleId != null) 'sale_id': saleId,
      if (payload != null) 'payload': payload,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalPaymentsCompanion copyWith({
    Value<String>? id,
    Value<String>? saleId,
    Value<String>? payload,
    Value<DateTime?>? syncedAt,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return LocalPaymentsCompanion(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      payload: payload ?? this.payload,
      syncedAt: syncedAt ?? this.syncedAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (saleId.present) {
      map['sale_id'] = Variable<String>(saleId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPaymentsCompanion(')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('payload: $payload, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$PosDatabase extends GeneratedDatabase {
  _$PosDatabase(QueryExecutor e) : super(e);
  $PosDatabaseManager get managers => $PosDatabaseManager(this);
  late final $LocalSalesTable localSales = $LocalSalesTable(this);
  late final $LocalProductsTable localProducts = $LocalProductsTable(this);
  late final $LocalCatalogVersionsTable localCatalogVersions =
      $LocalCatalogVersionsTable(this);
  late final $LocalOperationalStateTable localOperationalState =
      $LocalOperationalStateTable(this);
  late final $LocalStockOperationsTable localStockOperations =
      $LocalStockOperationsTable(this);
  late final $LocalCatalogOperationsTable localCatalogOperations =
      $LocalCatalogOperationsTable(this);
  late final $LocalPaymentsTable localPayments = $LocalPaymentsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localSales,
    localProducts,
    localCatalogVersions,
    localOperationalState,
    localStockOperations,
    localCatalogOperations,
    localPayments,
  ];
}

typedef $$LocalSalesTableCreateCompanionBuilder =
    LocalSalesCompanion Function({
      required String id,
      required String payload,
      required int totalCents,
      required DateTime createdAt,
      Value<DateTime?> syncedAt,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$LocalSalesTableUpdateCompanionBuilder =
    LocalSalesCompanion Function({
      Value<String> id,
      Value<String> payload,
      Value<int> totalCents,
      Value<DateTime> createdAt,
      Value<DateTime?> syncedAt,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$LocalSalesTableFilterComposer
    extends Composer<_$PosDatabase, $LocalSalesTable> {
  $$LocalSalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalCents => $composableBuilder(
    column: $table.totalCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSalesTableOrderingComposer
    extends Composer<_$PosDatabase, $LocalSalesTable> {
  $$LocalSalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalCents => $composableBuilder(
    column: $table.totalCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSalesTableAnnotationComposer
    extends Composer<_$PosDatabase, $LocalSalesTable> {
  $$LocalSalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get totalCents => $composableBuilder(
    column: $table.totalCents,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$LocalSalesTableTableManager
    extends
        RootTableManager<
          _$PosDatabase,
          $LocalSalesTable,
          LocalSale,
          $$LocalSalesTableFilterComposer,
          $$LocalSalesTableOrderingComposer,
          $$LocalSalesTableAnnotationComposer,
          $$LocalSalesTableCreateCompanionBuilder,
          $$LocalSalesTableUpdateCompanionBuilder,
          (
            LocalSale,
            BaseReferences<_$PosDatabase, $LocalSalesTable, LocalSale>,
          ),
          LocalSale,
          PrefetchHooks Function()
        > {
  $$LocalSalesTableTableManager(_$PosDatabase db, $LocalSalesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> totalCents = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSalesCompanion(
                id: id,
                payload: payload,
                totalCents: totalCents,
                createdAt: createdAt,
                syncedAt: syncedAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String payload,
                required int totalCents,
                required DateTime createdAt,
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSalesCompanion.insert(
                id: id,
                payload: payload,
                totalCents: totalCents,
                createdAt: createdAt,
                syncedAt: syncedAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalSalesTable, LocalSale>(table),
                  BaseReferences<_$PosDatabase, $LocalSalesTable, LocalSale>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSalesTableProcessedTableManager =
    ProcessedTableManager<
      _$PosDatabase,
      $LocalSalesTable,
      LocalSale,
      $$LocalSalesTableFilterComposer,
      $$LocalSalesTableOrderingComposer,
      $$LocalSalesTableAnnotationComposer,
      $$LocalSalesTableCreateCompanionBuilder,
      $$LocalSalesTableUpdateCompanionBuilder,
      (LocalSale, BaseReferences<_$PosDatabase, $LocalSalesTable, LocalSale>),
      LocalSale,
      PrefetchHooks Function()
    >;
typedef $$LocalProductsTableCreateCompanionBuilder =
    LocalProductsCompanion Function({
      required String id,
      required String payload,
      Value<int> rowid,
    });
typedef $$LocalProductsTableUpdateCompanionBuilder =
    LocalProductsCompanion Function({
      Value<String> id,
      Value<String> payload,
      Value<int> rowid,
    });

class $$LocalProductsTableFilterComposer
    extends Composer<_$PosDatabase, $LocalProductsTable> {
  $$LocalProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalProductsTableOrderingComposer
    extends Composer<_$PosDatabase, $LocalProductsTable> {
  $$LocalProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalProductsTableAnnotationComposer
    extends Composer<_$PosDatabase, $LocalProductsTable> {
  $$LocalProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$LocalProductsTableTableManager
    extends
        RootTableManager<
          _$PosDatabase,
          $LocalProductsTable,
          LocalProduct,
          $$LocalProductsTableFilterComposer,
          $$LocalProductsTableOrderingComposer,
          $$LocalProductsTableAnnotationComposer,
          $$LocalProductsTableCreateCompanionBuilder,
          $$LocalProductsTableUpdateCompanionBuilder,
          (
            LocalProduct,
            BaseReferences<_$PosDatabase, $LocalProductsTable, LocalProduct>,
          ),
          LocalProduct,
          PrefetchHooks Function()
        > {
  $$LocalProductsTableTableManager(_$PosDatabase db, $LocalProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalProductsCompanion(
                id: id,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => LocalProductsCompanion.insert(
                id: id,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalProductsTable, LocalProduct>(table),
                  BaseReferences<
                    _$PosDatabase,
                    $LocalProductsTable,
                    LocalProduct
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$PosDatabase,
      $LocalProductsTable,
      LocalProduct,
      $$LocalProductsTableFilterComposer,
      $$LocalProductsTableOrderingComposer,
      $$LocalProductsTableAnnotationComposer,
      $$LocalProductsTableCreateCompanionBuilder,
      $$LocalProductsTableUpdateCompanionBuilder,
      (
        LocalProduct,
        BaseReferences<_$PosDatabase, $LocalProductsTable, LocalProduct>,
      ),
      LocalProduct,
      PrefetchHooks Function()
    >;
typedef $$LocalCatalogVersionsTableCreateCompanionBuilder =
    LocalCatalogVersionsCompanion Function({
      Value<int> id,
      required int version,
    });
typedef $$LocalCatalogVersionsTableUpdateCompanionBuilder =
    LocalCatalogVersionsCompanion Function({Value<int> id, Value<int> version});

class $$LocalCatalogVersionsTableFilterComposer
    extends Composer<_$PosDatabase, $LocalCatalogVersionsTable> {
  $$LocalCatalogVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCatalogVersionsTableOrderingComposer
    extends Composer<_$PosDatabase, $LocalCatalogVersionsTable> {
  $$LocalCatalogVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCatalogVersionsTableAnnotationComposer
    extends Composer<_$PosDatabase, $LocalCatalogVersionsTable> {
  $$LocalCatalogVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
}

class $$LocalCatalogVersionsTableTableManager
    extends
        RootTableManager<
          _$PosDatabase,
          $LocalCatalogVersionsTable,
          LocalCatalogVersion,
          $$LocalCatalogVersionsTableFilterComposer,
          $$LocalCatalogVersionsTableOrderingComposer,
          $$LocalCatalogVersionsTableAnnotationComposer,
          $$LocalCatalogVersionsTableCreateCompanionBuilder,
          $$LocalCatalogVersionsTableUpdateCompanionBuilder,
          (
            LocalCatalogVersion,
            BaseReferences<
              _$PosDatabase,
              $LocalCatalogVersionsTable,
              LocalCatalogVersion
            >,
          ),
          LocalCatalogVersion,
          PrefetchHooks Function()
        > {
  $$LocalCatalogVersionsTableTableManager(
    _$PosDatabase db,
    $LocalCatalogVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCatalogVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCatalogVersionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalCatalogVersionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> version = const Value.absent(),
              }) => LocalCatalogVersionsCompanion(id: id, version: version),
          createCompanionCallback:
              ({Value<int> id = const Value.absent(), required int version}) =>
                  LocalCatalogVersionsCompanion.insert(
                    id: id,
                    version: version,
                  ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalCatalogVersionsTable, LocalCatalogVersion>(
                    table,
                  ),
                  BaseReferences<
                    _$PosDatabase,
                    $LocalCatalogVersionsTable,
                    LocalCatalogVersion
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCatalogVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$PosDatabase,
      $LocalCatalogVersionsTable,
      LocalCatalogVersion,
      $$LocalCatalogVersionsTableFilterComposer,
      $$LocalCatalogVersionsTableOrderingComposer,
      $$LocalCatalogVersionsTableAnnotationComposer,
      $$LocalCatalogVersionsTableCreateCompanionBuilder,
      $$LocalCatalogVersionsTableUpdateCompanionBuilder,
      (
        LocalCatalogVersion,
        BaseReferences<
          _$PosDatabase,
          $LocalCatalogVersionsTable,
          LocalCatalogVersion
        >,
      ),
      LocalCatalogVersion,
      PrefetchHooks Function()
    >;
typedef $$LocalOperationalStateTableCreateCompanionBuilder =
    LocalOperationalStateCompanion Function({
      required String key,
      required String payload,
      Value<int> rowid,
    });
typedef $$LocalOperationalStateTableUpdateCompanionBuilder =
    LocalOperationalStateCompanion Function({
      Value<String> key,
      Value<String> payload,
      Value<int> rowid,
    });

class $$LocalOperationalStateTableFilterComposer
    extends Composer<_$PosDatabase, $LocalOperationalStateTable> {
  $$LocalOperationalStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalOperationalStateTableOrderingComposer
    extends Composer<_$PosDatabase, $LocalOperationalStateTable> {
  $$LocalOperationalStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalOperationalStateTableAnnotationComposer
    extends Composer<_$PosDatabase, $LocalOperationalStateTable> {
  $$LocalOperationalStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$LocalOperationalStateTableTableManager
    extends
        RootTableManager<
          _$PosDatabase,
          $LocalOperationalStateTable,
          LocalOperationalStateData,
          $$LocalOperationalStateTableFilterComposer,
          $$LocalOperationalStateTableOrderingComposer,
          $$LocalOperationalStateTableAnnotationComposer,
          $$LocalOperationalStateTableCreateCompanionBuilder,
          $$LocalOperationalStateTableUpdateCompanionBuilder,
          (
            LocalOperationalStateData,
            BaseReferences<
              _$PosDatabase,
              $LocalOperationalStateTable,
              LocalOperationalStateData
            >,
          ),
          LocalOperationalStateData,
          PrefetchHooks Function()
        > {
  $$LocalOperationalStateTableTableManager(
    _$PosDatabase db,
    $LocalOperationalStateTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalOperationalStateTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalOperationalStateTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalOperationalStateTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalOperationalStateCompanion(
                key: key,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => LocalOperationalStateCompanion.insert(
                key: key,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $LocalOperationalStateTable,
                    LocalOperationalStateData
                  >(table),
                  BaseReferences<
                    _$PosDatabase,
                    $LocalOperationalStateTable,
                    LocalOperationalStateData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalOperationalStateTableProcessedTableManager =
    ProcessedTableManager<
      _$PosDatabase,
      $LocalOperationalStateTable,
      LocalOperationalStateData,
      $$LocalOperationalStateTableFilterComposer,
      $$LocalOperationalStateTableOrderingComposer,
      $$LocalOperationalStateTableAnnotationComposer,
      $$LocalOperationalStateTableCreateCompanionBuilder,
      $$LocalOperationalStateTableUpdateCompanionBuilder,
      (
        LocalOperationalStateData,
        BaseReferences<
          _$PosDatabase,
          $LocalOperationalStateTable,
          LocalOperationalStateData
        >,
      ),
      LocalOperationalStateData,
      PrefetchHooks Function()
    >;
typedef $$LocalStockOperationsTableCreateCompanionBuilder =
    LocalStockOperationsCompanion Function({
      required String id,
      required String payload,
      required DateTime createdAt,
      Value<String> status,
      Value<String?> error,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<int> rowid,
    });
typedef $$LocalStockOperationsTableUpdateCompanionBuilder =
    LocalStockOperationsCompanion Function({
      Value<String> id,
      Value<String> payload,
      Value<DateTime> createdAt,
      Value<String> status,
      Value<String?> error,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<int> rowid,
    });

class $$LocalStockOperationsTableFilterComposer
    extends Composer<_$PosDatabase, $LocalStockOperationsTable> {
  $$LocalStockOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalStockOperationsTableOrderingComposer
    extends Composer<_$PosDatabase, $LocalStockOperationsTable> {
  $$LocalStockOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalStockOperationsTableAnnotationComposer
    extends Composer<_$PosDatabase, $LocalStockOperationsTable> {
  $$LocalStockOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );
}

class $$LocalStockOperationsTableTableManager
    extends
        RootTableManager<
          _$PosDatabase,
          $LocalStockOperationsTable,
          LocalStockOperation,
          $$LocalStockOperationsTableFilterComposer,
          $$LocalStockOperationsTableOrderingComposer,
          $$LocalStockOperationsTableAnnotationComposer,
          $$LocalStockOperationsTableCreateCompanionBuilder,
          $$LocalStockOperationsTableUpdateCompanionBuilder,
          (
            LocalStockOperation,
            BaseReferences<
              _$PosDatabase,
              $LocalStockOperationsTable,
              LocalStockOperation
            >,
          ),
          LocalStockOperation,
          PrefetchHooks Function()
        > {
  $$LocalStockOperationsTableTableManager(
    _$PosDatabase db,
    $LocalStockOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalStockOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalStockOperationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalStockOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalStockOperationsCompanion(
                id: id,
                payload: payload,
                createdAt: createdAt,
                status: status,
                error: error,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String payload,
                required DateTime createdAt,
                Value<String> status = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalStockOperationsCompanion.insert(
                id: id,
                payload: payload,
                createdAt: createdAt,
                status: status,
                error: error,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalStockOperationsTable, LocalStockOperation>(
                    table,
                  ),
                  BaseReferences<
                    _$PosDatabase,
                    $LocalStockOperationsTable,
                    LocalStockOperation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalStockOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$PosDatabase,
      $LocalStockOperationsTable,
      LocalStockOperation,
      $$LocalStockOperationsTableFilterComposer,
      $$LocalStockOperationsTableOrderingComposer,
      $$LocalStockOperationsTableAnnotationComposer,
      $$LocalStockOperationsTableCreateCompanionBuilder,
      $$LocalStockOperationsTableUpdateCompanionBuilder,
      (
        LocalStockOperation,
        BaseReferences<
          _$PosDatabase,
          $LocalStockOperationsTable,
          LocalStockOperation
        >,
      ),
      LocalStockOperation,
      PrefetchHooks Function()
    >;
typedef $$LocalCatalogOperationsTableCreateCompanionBuilder =
    LocalCatalogOperationsCompanion Function({
      required String id,
      required String productId,
      required String payload,
      Value<String?> basePayload,
      Value<String?> conflictPayload,
      required int expectedVersion,
      Value<String> status,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> error,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$LocalCatalogOperationsTableUpdateCompanionBuilder =
    LocalCatalogOperationsCompanion Function({
      Value<String> id,
      Value<String> productId,
      Value<String> payload,
      Value<String?> basePayload,
      Value<String?> conflictPayload,
      Value<int> expectedVersion,
      Value<String> status,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> error,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$LocalCatalogOperationsTableFilterComposer
    extends Composer<_$PosDatabase, $LocalCatalogOperationsTable> {
  $$LocalCatalogOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get basePayload => $composableBuilder(
    column: $table.basePayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conflictPayload => $composableBuilder(
    column: $table.conflictPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedVersion => $composableBuilder(
    column: $table.expectedVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCatalogOperationsTableOrderingComposer
    extends Composer<_$PosDatabase, $LocalCatalogOperationsTable> {
  $$LocalCatalogOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get basePayload => $composableBuilder(
    column: $table.basePayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conflictPayload => $composableBuilder(
    column: $table.conflictPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedVersion => $composableBuilder(
    column: $table.expectedVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCatalogOperationsTableAnnotationComposer
    extends Composer<_$PosDatabase, $LocalCatalogOperationsTable> {
  $$LocalCatalogOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get basePayload => $composableBuilder(
    column: $table.basePayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conflictPayload => $composableBuilder(
    column: $table.conflictPayload,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expectedVersion => $composableBuilder(
    column: $table.expectedVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LocalCatalogOperationsTableTableManager
    extends
        RootTableManager<
          _$PosDatabase,
          $LocalCatalogOperationsTable,
          LocalCatalogOperation,
          $$LocalCatalogOperationsTableFilterComposer,
          $$LocalCatalogOperationsTableOrderingComposer,
          $$LocalCatalogOperationsTableAnnotationComposer,
          $$LocalCatalogOperationsTableCreateCompanionBuilder,
          $$LocalCatalogOperationsTableUpdateCompanionBuilder,
          (
            LocalCatalogOperation,
            BaseReferences<
              _$PosDatabase,
              $LocalCatalogOperationsTable,
              LocalCatalogOperation
            >,
          ),
          LocalCatalogOperation,
          PrefetchHooks Function()
        > {
  $$LocalCatalogOperationsTableTableManager(
    _$PosDatabase db,
    $LocalCatalogOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCatalogOperationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalCatalogOperationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalCatalogOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String?> basePayload = const Value.absent(),
                Value<String?> conflictPayload = const Value.absent(),
                Value<int> expectedVersion = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCatalogOperationsCompanion(
                id: id,
                productId: productId,
                payload: payload,
                basePayload: basePayload,
                conflictPayload: conflictPayload,
                expectedVersion: expectedVersion,
                status: status,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                error: error,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String productId,
                required String payload,
                Value<String?> basePayload = const Value.absent(),
                Value<String?> conflictPayload = const Value.absent(),
                required int expectedVersion,
                Value<String> status = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> error = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalCatalogOperationsCompanion.insert(
                id: id,
                productId: productId,
                payload: payload,
                basePayload: basePayload,
                conflictPayload: conflictPayload,
                expectedVersion: expectedVersion,
                status: status,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                error: error,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $LocalCatalogOperationsTable,
                    LocalCatalogOperation
                  >(table),
                  BaseReferences<
                    _$PosDatabase,
                    $LocalCatalogOperationsTable,
                    LocalCatalogOperation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCatalogOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$PosDatabase,
      $LocalCatalogOperationsTable,
      LocalCatalogOperation,
      $$LocalCatalogOperationsTableFilterComposer,
      $$LocalCatalogOperationsTableOrderingComposer,
      $$LocalCatalogOperationsTableAnnotationComposer,
      $$LocalCatalogOperationsTableCreateCompanionBuilder,
      $$LocalCatalogOperationsTableUpdateCompanionBuilder,
      (
        LocalCatalogOperation,
        BaseReferences<
          _$PosDatabase,
          $LocalCatalogOperationsTable,
          LocalCatalogOperation
        >,
      ),
      LocalCatalogOperation,
      PrefetchHooks Function()
    >;
typedef $$LocalPaymentsTableCreateCompanionBuilder =
    LocalPaymentsCompanion Function({
      required String id,
      required String saleId,
      required String payload,
      Value<DateTime?> syncedAt,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$LocalPaymentsTableUpdateCompanionBuilder =
    LocalPaymentsCompanion Function({
      Value<String> id,
      Value<String> saleId,
      Value<String> payload,
      Value<DateTime?> syncedAt,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$LocalPaymentsTableFilterComposer
    extends Composer<_$PosDatabase, $LocalPaymentsTable> {
  $$LocalPaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get saleId => $composableBuilder(
    column: $table.saleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalPaymentsTableOrderingComposer
    extends Composer<_$PosDatabase, $LocalPaymentsTable> {
  $$LocalPaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get saleId => $composableBuilder(
    column: $table.saleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalPaymentsTableAnnotationComposer
    extends Composer<_$PosDatabase, $LocalPaymentsTable> {
  $$LocalPaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get saleId =>
      $composableBuilder(column: $table.saleId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$LocalPaymentsTableTableManager
    extends
        RootTableManager<
          _$PosDatabase,
          $LocalPaymentsTable,
          LocalPayment,
          $$LocalPaymentsTableFilterComposer,
          $$LocalPaymentsTableOrderingComposer,
          $$LocalPaymentsTableAnnotationComposer,
          $$LocalPaymentsTableCreateCompanionBuilder,
          $$LocalPaymentsTableUpdateCompanionBuilder,
          (
            LocalPayment,
            BaseReferences<_$PosDatabase, $LocalPaymentsTable, LocalPayment>,
          ),
          LocalPayment,
          PrefetchHooks Function()
        > {
  $$LocalPaymentsTableTableManager(_$PosDatabase db, $LocalPaymentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> saleId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPaymentsCompanion(
                id: id,
                saleId: saleId,
                payload: payload,
                syncedAt: syncedAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String saleId,
                required String payload,
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPaymentsCompanion.insert(
                id: id,
                saleId: saleId,
                payload: payload,
                syncedAt: syncedAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalPaymentsTable, LocalPayment>(table),
                  BaseReferences<
                    _$PosDatabase,
                    $LocalPaymentsTable,
                    LocalPayment
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalPaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$PosDatabase,
      $LocalPaymentsTable,
      LocalPayment,
      $$LocalPaymentsTableFilterComposer,
      $$LocalPaymentsTableOrderingComposer,
      $$LocalPaymentsTableAnnotationComposer,
      $$LocalPaymentsTableCreateCompanionBuilder,
      $$LocalPaymentsTableUpdateCompanionBuilder,
      (
        LocalPayment,
        BaseReferences<_$PosDatabase, $LocalPaymentsTable, LocalPayment>,
      ),
      LocalPayment,
      PrefetchHooks Function()
    >;

class $PosDatabaseManager {
  final _$PosDatabase _db;
  $PosDatabaseManager(this._db);
  $$LocalSalesTableTableManager get localSales =>
      $$LocalSalesTableTableManager(_db, _db.localSales);
  $$LocalProductsTableTableManager get localProducts =>
      $$LocalProductsTableTableManager(_db, _db.localProducts);
  $$LocalCatalogVersionsTableTableManager get localCatalogVersions =>
      $$LocalCatalogVersionsTableTableManager(_db, _db.localCatalogVersions);
  $$LocalOperationalStateTableTableManager get localOperationalState =>
      $$LocalOperationalStateTableTableManager(_db, _db.localOperationalState);
  $$LocalStockOperationsTableTableManager get localStockOperations =>
      $$LocalStockOperationsTableTableManager(_db, _db.localStockOperations);
  $$LocalCatalogOperationsTableTableManager get localCatalogOperations =>
      $$LocalCatalogOperationsTableTableManager(
        _db,
        _db.localCatalogOperations,
      );
  $$LocalPaymentsTableTableManager get localPayments =>
      $$LocalPaymentsTableTableManager(_db, _db.localPayments);
}
