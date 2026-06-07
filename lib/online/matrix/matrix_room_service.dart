import 'package:matrix/matrix.dart';
import 'matrix_client_service.dart';

class MatrixRoomService {
  MatrixRoomService({
    required MatrixClientService clientService,
  }) : _clientService = clientService;

  final MatrixClientService _clientService;

  Client get _client => _clientService.client;

  Future<String> createRoom({
    required String name,
    String? topic,
    bool isDirect = false,
    bool isPrivate = true,
  }) async {
    final roomId = await _client.createRoom(
      name: name,
      topic: topic,
      isDirect: isDirect,
      visibility: isPrivate ? Visibility.private : Visibility.public,
    );
    return roomId;
  }

  Future<void> joinRoom(String roomId) async {
    await _client.joinRoom(roomId);
  }

  Future<void> inviteUser({
    required String roomId,
    required String userId,
  }) async {
    await _client.inviteUser(roomId, userId);
  }

  List<Room> getJoinedRooms() {
    return _client.rooms;
  }
}
