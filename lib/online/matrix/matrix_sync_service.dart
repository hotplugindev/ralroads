import 'dart:async';
import 'package:dio/dio.dart';
import 'package:matrix/matrix.dart';
import '../../database/app_database.dart';
import '../../repositories/app_repositories.dart';
import '../../services/secure_credential_service.dart';
import 'matrix_account_service.dart';
import 'matrix_client_service.dart';
import 'matrix_event_ingestor.dart';
import 'matrix_outbox_worker.dart';

class MatrixSyncService {
  MatrixSyncService({
    required this.repositories,
    required this.secureCredentials,
    required this.matrixAccount,
    Dio? dio,
  }) {
    _ingestor = MatrixEventIngestor(repositories: repositories, dio: dio);
    _outboxWorker = MatrixOutboxWorker(repositories: repositories, dio: dio);
  }

  final AppRepositories repositories;
  final SecureCredentialService secureCredentials;
  final MatrixAccountService matrixAccount;

  late final MatrixEventIngestor _ingestor;
  late final MatrixOutboxWorker _outboxWorker;

  MatrixClientService get _clientService => matrixAccount.clientService;
  Client get _client => _clientService.client;

  bool _running = false;
  Timer? _outboxTimer;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _syncSubscription;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;

    _clientService.init().then((_) {
      if (!_running) return;

      // 1. Subscribe to events stream
      _eventSubscription = _client.onEvent.stream.listen((update) async {
        var eventUpdate = update;
        final room = _client.getRoomById(update.roomID);
        if (room != null) {
          eventUpdate = await update.decrypt(room);
        }
        final content = eventUpdate.content;
        final eventId = content['event_id'] as String?;
        final eventType = content['type'] as String?;
        final payload = content['content'] as Map<String, dynamic>?;
        final sender = content['sender'] as String?;
        final originServerTs = content['origin_server_ts'] as int? ?? DateTime.now().millisecondsSinceEpoch;

        if (eventId == null || eventType == null || payload == null) return;

        final session = await matrixAccount.restoreSession();
        if (session == null) return;

        final token = await secureCredentials.readString(SecureCredentialKey.matrixAccessToken);
        if (token == null) return;

        await _ingestor.ingestEvent(
          eventId: eventId,
          roomId: update.roomID,
          eventType: eventType,
          content: payload,
          originServerTs: originServerTs,
          sender: sender,
          currentUserId: session.matrixUserId,
          homeserverUrl: session.homeserverUrl,
          accessToken: token,
        );
      });

      // 2. Subscribe to sync stream for auto-joining invites
      _syncSubscription = _client.onSync.stream.listen((_) async {
        for (final room in _client.rooms) {
          if (room.membership == Membership.invite) {
            try {
              await room.join();
            } catch (_) {}
          }
        }
      });

      // 3. Process outbox periodically
      _outboxTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => processOutbox(),
      );

      // Trigger initial outbox check
      processOutbox();

      // Start background sync loop
      _client.backgroundSync = false;
      _client.backgroundSync = true;
    });
  }

  void stop() {
    _running = false;
    _outboxTimer?.cancel();
    _outboxTimer = null;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _syncSubscription?.cancel();
    _syncSubscription = null;
    _client.backgroundSync = false;
  }

  Future<void> processOutbox() async {
    final session = await matrixAccount.restoreSession();
    if (session == null) return;
    final token = await secureCredentials.readString(SecureCredentialKey.matrixAccessToken);
    if (token == null) return;

    await _outboxWorker.process(
      homeserverUrl: session.homeserverUrl,
      accessToken: token,
    );
  }

  Future<void> importSegment(Map<String, dynamic> package) =>
      _ingestor.importSegment(package);

  Future<void> importAttempt(Map<String, dynamic> package) =>
      _ingestor.importAttempt(package);

  Future<void> importProfileEvent(
    Map<String, dynamic> content, {
    String? sender,
  }) =>
      _ingestor.importProfileEvent(content, sender: sender);

  Future<void> importFriendEvent(
    Map<String, dynamic> content, {
    String? currentUserId,
    MatrixSession? session,
    required String state,
  }) =>
      _ingestor.importFriendEvent(
        content,
        currentUserId: currentUserId,
        session: session,
        state: state,
      );

  Future<void> importGroupEvent(
    Map<String, dynamic> content, {
    required String roomId,
  }) =>
      _ingestor.importGroupEvent(content, roomId: roomId);
}
