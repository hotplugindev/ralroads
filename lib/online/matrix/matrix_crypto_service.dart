import 'package:matrix/matrix.dart';
import 'matrix_client_service.dart';

class MatrixCryptoService {
  MatrixCryptoService({
    required MatrixClientService clientService,
  }) : _clientService = clientService;

  final MatrixClientService _clientService;

  Client get _client => _clientService.client;

  Future<void> setRoomEncryption(String roomId, bool enabled) async {
    if (enabled) {
      await _client.setRoomStateWithKey(
        roomId,
        'm.room.encryption',
        '',
        {'algorithm': 'm.megolm.v1.aes-sha2'},
      );
    }
  }

  bool isRoomEncrypted(String roomId) {
    final room = _client.getRoomById(roomId);
    return room?.encrypted ?? false;
  }
}
