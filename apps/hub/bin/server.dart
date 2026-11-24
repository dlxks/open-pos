import 'dart:async';
import 'dart:io';

import 'package:hub/hub_app.dart';
import 'package:hub/hub_store.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final databasePath =
      Platform.environment['POS_HUB_DATABASE'] ?? 'pos_hub.sqlite';
  final store = HubStore.open(databasePath);
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(createApp(store));
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Open POS hub listening on port ${server.port}');

  final stopped = Completer<void>();
  var shuttingDown = false;
  Future<void> shutdown() async {
    if (shuttingDown) return;
    shuttingDown = true;
    stdout.writeln('Open POS hub is draining requests.');
    try {
      await server.close().timeout(const Duration(seconds: 8));
    } on TimeoutException {
      stderr.writeln(
        'Hub shutdown drain timed out; forcing remaining connections closed.',
      );
      await server.close(force: true);
    } on Object catch (error) {
      stderr.writeln('Hub shutdown required a forced close: $error');
      exitCode = 1;
    } finally {
      store.close();
      if (!stopped.isCompleted) stopped.complete();
    }
  }

  final signals = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) => unawaited(shutdown())),
    if (!Platform.isWindows)
      ProcessSignal.sigterm.watch().listen((_) => unawaited(shutdown())),
  ];
  await stopped.future;
  await Future.wait(signals.map((signal) => signal.cancel()));
}
