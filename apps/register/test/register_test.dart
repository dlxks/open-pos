// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_pos/data/local_database.dart';
import 'package:open_pos/data/sale_sync_client.dart';
import 'package:open_pos/data/session_vault.dart';
import 'package:open_pos/main.dart';
import 'package:pos_domain/pos_domain.dart';

void main() {
  late PosDatabase database;

  tearDown(() async {
    await database.close();
  });

  testWidgets('completes a cash sale and clears the cart', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    database = PosDatabase.forTesting(NativeDatabase.memory());
    final syncClient = _registeredApi(
      (request) async => http.Response('', 201),
    );
    addTearDown(syncClient.close);

    await tester.pumpWidget(
      SukiPosApp(
        database: database,
        syncClient: syncClient,
        sessionVault: MemorySessionVault(_testSession),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Iced latte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete cash sale'));
    await tester.pumpAndSettle();

    final savedSales = await database.select(database.localSales).get();
    expect(savedSales, hasLength(1));
    expect(savedSales.single.totalCents, 14_500);
    expect(savedSales.single.syncedAt, isNotNull);
    expect(find.text('Add products to start a sale'), findsOneWidget);
  });

  testWidgets('applies a reasoned discount after the dialog closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    database = PosDatabase.forTesting(NativeDatabase.memory());
    final syncClient = _registeredApi(
      (request) async => http.Response('', 201),
    );
    addTearDown(syncClient.close);

    await tester.pumpWidget(
      SukiPosApp(
        database: database,
        syncClient: syncClient,
        sessionVault: MemorySessionVault(_testSession),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Iced latte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discount'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1.00');
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'Promotion',
    );
    await tester.tap(find.text('Apply discount'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Complete cash sale'));
    await tester.pumpAndSettle();

    final sales = await database.select(database.localSales).get();
    expect(sales, hasLength(1));
    final sale = Sale.fromJson(
      jsonDecode(sales.single.payload) as Map<String, Object?>,
    );
    expect(sale.discountCents, 100);
    expect(sale.discountReason, 'Promotion');
  });

  testWidgets('keeps first-run setup usable on a phone and in landscape', (
    tester,
  ) async {
    database = PosDatabase.forTesting(NativeDatabase.memory());
    final api = SaleSyncClient(
      baseUrl: 'http://hub.test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/setup/status')) {
          return http.Response('{"needsSetup":true,"store":null}', 200);
        }
        return http.Response('', 404);
      }),
    );
    addTearDown(api.close);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      SukiPosApp(
        database: database,
        syncClient: api,
        sessionVault: MemorySessionVault(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set up your store'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(812, 375);
    await tester.pumpAndSettle();
    expect(find.text('Set up your store'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps a cash sale queued when the hub is unreachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    database = PosDatabase.forTesting(NativeDatabase.memory());
    final syncClient = _registeredApi((request) async {
      if (request.url.path.endsWith('/sales')) {
        throw const SocketException('offline');
      }
      return http.Response('', 201);
    });
    addTearDown(syncClient.close);

    await tester.pumpWidget(
      SukiPosApp(
        database: database,
        syncClient: syncClient,
        sessionVault: MemorySessionVault(_testSession),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pan de sal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete cash sale'));
    await tester.pumpAndSettle();

    final savedSales = await database.select(database.localSales).get();
    final savedPayments = await database.select(database.localPayments).get();
    expect(savedSales, hasLength(1));
    expect(savedSales.single.syncedAt, isNull);
    expect(savedPayments, hasLength(1));
    expect(savedPayments.single.syncedAt, isNull);
    expect(find.text('2 waiting to sync'), findsOneWidget);
  });

  testWidgets('completes a sale from the compact mobile cart sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    database = PosDatabase.forTesting(NativeDatabase.memory());
    final syncClient = _registeredApi(
      (request) async => http.Response('', 201),
    );
    addTearDown(syncClient.close);

    await tester.pumpWidget(
      SukiPosApp(
        database: database,
        syncClient: syncClient,
        sessionVault: MemorySessionVault(_testSession),
      ),
    );
    await tester.pumpAndSettle();

    final latte = find.text('Iced latte');
    await tester.ensureVisible(latte);
    await tester.tap(latte);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cart · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete cash sale'));
    await tester.pumpAndSettle();

    final sales = await database.select(database.localSales).get();
    expect(sales, hasLength(1));
    expect(find.text('1 waiting to sync'), findsNothing);
  });
}

final _testSession = HubSession(
  token: 'test-session-token',
  user: const PosUser(
    id: 'admin-1',
    name: 'Maria Santos',
    email: 'maria@example.test',
    role: AccountRole.admin,
  ),
  store: const PosStore(id: 'store-1', name: 'Mabini Market'),
);

SaleSyncClient _registeredApi(
  Future<http.Response> Function(http.Request) onRequest,
) => SaleSyncClient(
  baseUrl: 'http://hub.test',
  client: MockClient((request) async {
    if (request.url.path.endsWith('/auth/me')) {
      return http.Response(
        jsonEncode({
          'user': _testSession.user.toJson(),
          'store': _testSession.store.toJson(),
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/products')) {
      return http.Response(
        jsonEncode({
          'version': 1,
          'products': defaultProducts
              .map((product) => product.toJson())
              .toList(),
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/shifts/current')) {
      return http.Response(
        jsonEncode({
          'shift': {
            'id': 'shift-1',
            'openedAt': DateTime.utc(2026, 11, 23, 9).toIso8601String(),
            'openingFloatCents': 10000,
            'expectedCashCents': 10000,
            'isOpen': true,
            'closedAt': null,
            'countedCashCents': null,
            'varianceCents': null,
          },
        }),
        200,
      );
    }
    return onRequest(request);
  }),
);
