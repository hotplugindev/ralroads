import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

import '../../repositories/app_repositories.dart';

class MatrixOutboxWorker {
  MatrixOutboxWorker({
    required this.repositories,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final AppRepositories repositories;
  final Dio _dio;

  Future<void> process({
    required String homeserverUrl,
    required String accessToken,
  }) async {
    final now = DateTime.now();

    // 1. Process Outgoing Events
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
          
          if (mediaUpload == null || mediaUpload.state != 'uploaded' || mediaUpload.matrixUri == null) {
            // Media not uploaded yet, skip this event for now
            continue;
          }
          // Replace placeholder with final MXC URI
          payload = Map<String, dynamic>.from(payload);
          payload['mxc_uri'] = mediaUpload.matrixUri;
        }

        await repositories.sync.markEventState(event.id, 'sending');
        await _dio.put<Map<String, dynamic>>(
          '$homeserverUrl/_matrix/client/v3/rooms/${event.roomId}/send/${event.eventType}/${event.id}',
          data: payload,
          options: Options(
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
          ),
        );
        await repositories.sync.markEventState(event.id, 'sent');
      } catch (e) {
        await repositories.sync.markEventFailedWithRetry(
          event.id,
          const Duration(minutes: 1),
        );
      }
    }

    // 2. Process Media Uploads
    final uploads = await repositories.sync.listDueMediaUploads(now);
    for (final upload in uploads) {
      await repositories.sync.markMediaState(upload.id, 'uploading');
      try {
        final file = File(upload.localPath);
        final fileBytes = await file.readAsBytes();

        final response = await _dio.post<Map<String, dynamic>>(
          '$homeserverUrl/_matrix/media/v3/upload',
          data: Stream.fromIterable([fileBytes]),
          options: Options(
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/octet-stream',
            },
          ),
        );

        final contentUri = response.data?['content_uri'] as String?;
        if (contentUri != null) {
          await repositories.sync.markMediaState(
            upload.id,
            'uploaded',
            matrixUri: contentUri,
          );
        } else {
          await repositories.sync.markMediaFailedWithRetry(
            upload.id,
            const Duration(minutes: 1),
          );
        }
      } catch (e) {
        await repositories.sync.markMediaFailedWithRetry(
          upload.id,
          const Duration(minutes: 1),
        );
      }
    }
  }
}
