import 'dart:async';
import 'dart:developer' as developer;
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
    _outboxWorker = MatrixOutboxWorker(
      repositories: repositories,
      clientService: matrixAccount.clientService,
    );
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

      _eventSubscription = _client.onEvent.stream.listen((update) async {
        await _handleEventUpdate(update);
      });

      _syncSubscription = _client.onSync.stream.listen((_) async {
        // Invitations are deliberately not auto-joined. The UI must surface
        // them and call the explicit accept/decline path.
      });

      // 3. Process outbox periodically
      _outboxTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => processOutbox(),
      );

      // Trigger initial outbox check
      processOutbox();

      _clientService.startSync();
    });
  }

  Future<void> _handleEventUpdate(EventUpdate update) async {
    try {
      var eventUpdate = update;
      final room = _client.getRoomById(update.roomID);
      if (room != null) {
        eventUpdate = await update.decrypt(room);
      }
      final raw = eventUpdate.content;
      final eventId = raw['event_id'] as String?;
      final eventType = raw['type'] as String?;
      final sender = raw['sender'] as String?;
      final payload = raw['content'];
      final originServerTs =
          raw['origin_server_ts'] as int? ??
          DateTime.now().millisecondsSinceEpoch;

      if (eventId == null ||
          eventType == null ||
          payload is! Map<String, dynamic>) {
        developer.log(
          'Quarantined malformed Matrix event update.',
          name: 'ralroads.matrix.sync',
        );
        return;
      }

      final session = await matrixAccount.restoreSession();
      if (session == null) return;

      final token = await secureCredentials.readString(
        SecureCredentialKey.matrixAccessToken,
      );
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
    } catch (error, stackTrace) {
      developer.log(
        'Matrix event ingestion failed.',
        name: 'ralroads.matrix.sync',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void stop() {
    _running = false;
    _outboxTimer?.cancel();
    _outboxTimer = null;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _syncSubscription?.cancel();
    _syncSubscription = null;
    _clientService.stopSync();
  }

  Future<void> processOutbox() async {
    final session = await matrixAccount.restoreSession();
    if (session == null) return;
    final token = await secureCredentials.readString(
      SecureCredentialKey.matrixAccessToken,
    );
    if (token == null) return;

    await _outboxWorker.process();
  }

  Future<void> importSegment(Map<String, dynamic> package) =>
      _ingestor.importSegment(package);

  Future<void> importAttempt(Map<String, dynamic> package) =>
      _ingestor.importAttempt(package);

  Future<void> importProfileEvent(
    Map<String, dynamic> content, {
    String? sender,
  }) => _ingestor.importProfileEvent(content, sender: sender);

  Future<void> importFriendEvent(
    Map<String, dynamic> content, {
    String? currentUserId,
    MatrixSession? session,
    required String state,
  }) => _ingestor.importFriendEvent(
    content,
    currentUserId: currentUserId,
    session: session,
    state: state,
  );

  Future<void> importGroupEvent(
    Map<String, dynamic> content, {
    required String roomId,
  }) => _ingestor.importGroupEvent(content, roomId: roomId);

  Future<void> importChallengeEvent(
    Map<String, dynamic> content, {
    required String roomId,
    required String eventType,
    required DateTime originTimestamp,
    String? sender,
  }) => _ingestor.importChallengeEvent(
    content,
    roomId: roomId,
    eventType: eventType,
    originTimestamp: originTimestamp,
    sender: sender,
  );
}
