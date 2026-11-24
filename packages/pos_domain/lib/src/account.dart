enum AccountRole {
  admin,
  manager,
  cashier;

  static AccountRole parse(Object? value) => switch (value) {
    'admin' => AccountRole.admin,
    'manager' => AccountRole.manager,
    'cashier' => AccountRole.cashier,
    _ => throw const FormatException('Account role is invalid.'),
  };

  String get wireValue => name;

  String get label => switch (this) {
    AccountRole.admin => 'Administrator',
    AccountRole.manager => 'Manager',
    AccountRole.cashier => 'Cashier',
  };
}

class PosStore {
  const PosStore({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory PosStore.fromJson(Map<String, Object?> json) =>
      PosStore(id: json['id'] as String, name: json['name'] as String);
}

class PosUser {
  const PosUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final AccountRole role;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.wireValue,
  };

  factory PosUser.fromJson(Map<String, Object?> json) => PosUser(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: AccountRole.parse(json['role']),
  );
}

class HubSession {
  const HubSession({
    required this.token,
    required this.user,
    required this.store,
  });

  final String token;
  final PosUser user;
  final PosStore store;

  Map<String, Object?> toJson() => {
    'token': token,
    'user': user.toJson(),
    'store': store.toJson(),
  };

  factory HubSession.fromJson(Map<String, Object?> json) => HubSession(
    token: json['token'] as String,
    user: PosUser.fromJson(json['user'] as Map<String, Object?>),
    store: PosStore.fromJson(json['store'] as Map<String, Object?>),
  );
}
