import 'package:drift/drift.dart';
import '../database/app_database.dart';

class NotificationRepository {
  NotificationRepository(this.database);

  final AppDatabase database;

  Future<void> createNotification({
    required String id,
    required String type,
    required String title,
    String? body,
  }) {
    return database
        .into(database.localNotifications)
        .insertOnConflictUpdate(
          LocalNotificationsCompanion(
            id: Value(id),
            type: Value(type),
            title: Value(title),
            body: Value(body),
            createdAt: Value(DateTime.now()),
          ),
        );
  }

  Future<List<LocalNotification>> getUnreadNotifications() {
    return (database.select(database.localNotifications)
          ..where((row) => row.readAt.isNull())
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
        .get();
  }

  Future<void> markAsRead(String id) {
    return (database.update(database.localNotifications)
          ..where((row) => row.id.equals(id)))
        .write(LocalNotificationsCompanion(readAt: Value(DateTime.now())));
  }

  Stream<List<LocalNotification>> watchUnreadNotifications() {
    return (database.select(database.localNotifications)
          ..where((row) => row.readAt.isNull())
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
        .watch();
  }
}
