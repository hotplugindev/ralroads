// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:ralroads/main.dart';
import 'package:ralroads/services/route_storage_service.dart';
import 'package:ralroads/services/settings_service.dart';

void main() {
  testWidgets('RoadNotes home shows primary actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      RoadNotesApp(storage: RouteStorageService(), settings: SettingsService()),
    );

    expect(find.text('RoadNotes'), findsWidgets);
    expect(find.text('Plan Route'), findsOneWidget);
    expect(find.text('Saved Routes'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
