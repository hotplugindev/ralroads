import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:matrix/matrix.dart';

import '../../repositories/app_repositories.dart';
import 'matrix_client_service.dart';

class MatrixOutboxWorker {
  MatrixOutboxWorker({
    required this.repositories,
    required MatrixClientService clientService,
  }) : _clientService = clientService;

  final AppRepositories repositories;
  final MatrixClientService _clientService;

  Client get _client => _clientService.client;

  Future<void> process() async {
    if (_client.userID == null || _client.accessToken == null) return;
    final now = DateTime.now();

    await _processMediaUploads(now);
    await _processOutgoingEvents(now);
  }

  Future<void> _processOutgoingEvents(DateTime now) async {
    final events = await repositories.sync.listDueEvents(now);
    for (final event in events) {
      if (event.roomId == null) continue;

      try {
        var payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
        final mxcUri = payload['mxc_uri'] as String?;
        if (mxcUri != null && mxcUri.startsWith('temp-upload-')) {
          final mediaUpload = await (repositories.sync.database.select(
            repositories.sync.database.pendingMediaUploads,
          )..where((row) => row.id.equals(mxcUri))).getSingleOrNull();

          if (mediaUpload == null ||
              mediaUpload.state != 'uploaded' ||
              mediaUpload.matrixUri == null) {
            // Media not uploaded yet, skip this event for now
            continue;
          }
          // Replace placeholder with final MXC URI
          payload = Map<String, dynamic>.from(payload);
          payload['mxc_uri'] = mediaUpload.matrixUri;
        }

        await repositories.sync.markEventState(event.id, 'sending');
        await _client.request(
          RequestType.PUT,
          '/client/v3/rooms/${Uri.encodeComponent(event.roomId!)}/send/${Uri.encodeComponent(event.eventType)}/${Uri.encodeComponent(event.id)}',
          data: payload,
        );
        await repositories.sync.markEventState(event.id, 'sent');
      } catch (error, stackTrace) {
        developer.log(
          'Matrix outbox event send failed.',
          name: 'ralroads.matrix.outbox',
          error: error,
          stackTrace: stackTrace,
        );
        await repositories.sync.markEventFailedWithRetry(
          event.id,
          const Duration(minutes: 1),
        );
      }
    }
  }

  Future<void> _processMediaUploads(DateTime now) async {
    final uploads = await repositories.sync.listDueMediaUploads(now);
    for (final upload in uploads) {
      await repositories.sync.markMediaState(upload.id, 'uploading');
      try {
        final file = File(upload.localPath);
        final fileBytes = await file.readAsBytes();

        final contentUri = await _client.uploadContent(
          fileBytes,
          filename: upload.id,
          contentType: 'application/octet-stream',
        );
        await repositories.sync.markMediaState(
          upload.id,
          'uploaded',
          matrixUri: contentUri.toString(),
        );
      } catch (error, stackTrace) {
        developer.log(
          'Matrix media upload failed.',
          name: 'ralroads.matrix.outbox',
          error: error,
          stackTrace: stackTrace,
        );
        await repositories.sync.markMediaFailedWithRetry(
          upload.id,
          const Duration(minutes: 1),
        );
      }
    }
  }
}
