import 'dart:typed_data';
import 'package:matrix/matrix.dart';
import 'matrix_client_service.dart';

class MatrixMediaService {
  MatrixMediaService({required MatrixClientService clientService})
    : _clientService = clientService;

  final MatrixClientService _clientService;

  Client get _client => _clientService.client;

  Future<Uri> uploadMedia(
    Uint8List bytes, {
    String? filename,
    String? contentType,
  }) async {
    final mxcUri = await _client.uploadContent(
      bytes,
      filename: filename,
      contentType: contentType,
    );
    return mxcUri;
  }

  Uri getDownloadUrl(Uri mxcUri) {
    return mxcUri.getDownloadLink(_client);
  }
}
