import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orgro/l10n/app_localizations.dart';
import 'package:orgro/src/components/remembered_files.dart';
import 'package:orgro/src/pages/start/start_drawer.dart';
import 'package:orgro/src/preferences.dart';

void main() {
  // Mock the file picker channel to avoid platform errors
  const filePickerChannel = MethodChannel('codeux.design/file_picker_writable');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, (MethodCall methodCall) async {
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, null);
  });

  group('StartDrawer', () {
    Widget buildTestDrawer({
      List<RememberedFile> files = const [],
      RecentFilesSortKey sortKey = RecentFilesSortKey.lastOpened,
      SortOrder sortOrder = SortOrder.descending,
    }) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: InheritedRememberedFiles(
            files,
            sortKey,
            sortOrder,
            add: (_) async {},
            remove: (_) async {},
            star: (_) {},
            unstar: (_) {},
            child: Builder(
              builder: (context) => const StartDrawer(),
            ),
          ),
        ),
      );
    }

    testWidgets('displays app title in header', (tester) async {
      await tester.pumpWidget(buildTestDrawer());
      await tester.pumpAndSettle();

      // AppLocalizations.of(context)!.appTitle is "Orgro"
      expect(find.text('Orgro'), findsOneWidget);
    });

    testWidgets('displays empty state when no files', (tester) async {
      await tester.pumpWidget(buildTestDrawer(files: []));
      await tester.pumpAndSettle();

      expect(find.text('No recent files'), findsOneWidget);
    });

    testWidgets('displays starred files section when starred files exist',
        (tester) async {
      final starredFile = RememberedFile(
        identifier: 'content://starred/1',
        name: 'starred.org',
        uri: 'content://starred/uri/1',
        lastOpened: DateTime.now(),
        starredIdx: 0,
      );

      await tester.pumpWidget(buildTestDrawer(files: [starredFile]));
      await tester.pumpAndSettle();

      expect(find.text('starred.org'), findsOneWidget);
      // Should have starred section header
      expect(find.byIcon(Icons.star), findsAtLeast(1));
    });

    testWidgets('displays recent files section when recent files exist',
        (tester) async {
      final recentFile = RememberedFile(
        identifier: 'content://recent/1',
        name: 'recent.org',
        uri: 'content://recent/uri/1',
        lastOpened: DateTime.now(),
        starredIdx: -1, // Not starred
      );

      await tester.pumpWidget(buildTestDrawer(files: [recentFile]));
      await tester.pumpAndSettle();

      expect(find.text('recent.org'), findsOneWidget);
      // Should have history icon for recent files section
      expect(find.byIcon(Icons.history), findsAtLeast(1));
    });

    testWidgets('displays both starred and recent sections', (tester) async {
      final starredFile = RememberedFile(
        identifier: 'content://starred/1',
        name: 'starred.org',
        uri: 'content://starred/uri/1',
        lastOpened: DateTime.now(),
        starredIdx: 0,
      );
      final recentFile = RememberedFile(
        identifier: 'content://recent/1',
        name: 'recent.org',
        uri: 'content://recent/uri/1',
        lastOpened: DateTime.now(),
        starredIdx: -1,
      );

      await tester.pumpWidget(buildTestDrawer(files: [starredFile, recentFile]));
      await tester.pumpAndSettle();

      expect(find.text('starred.org'), findsOneWidget);
      expect(find.text('recent.org'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsAtLeast(1));
      expect(find.byIcon(Icons.history), findsAtLeast(1));
    });

    testWidgets('displays settings link', (tester) async {
      await tester.pumpWidget(buildTestDrawer());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('displays about link', (tester) async {
      await tester.pumpWidget(buildTestDrawer());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('displays sort button for recent files', (tester) async {
      final recentFile = RememberedFile(
        identifier: 'content://recent/1',
        name: 'recent.org',
        uri: 'content://recent/uri/1',
        lastOpened: DateTime.now(),
        starredIdx: -1,
      );

      await tester.pumpWidget(buildTestDrawer(files: [recentFile]));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.sort), findsOneWidget);
    });

    testWidgets('shows file description icons for files', (tester) async {
      final file = RememberedFile(
        identifier: 'content://file/1',
        name: 'test.org',
        uri: 'content://file/uri/1',
        lastOpened: DateTime.now(),
        starredIdx: -1,
      );

      await tester.pumpWidget(buildTestDrawer(files: [file]));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.description), findsOneWidget);
    });
  });

  group('RememberedFile model', () {
    test('isStarred returns true when starredIdx >= 0', () {
      final file = RememberedFile(
        identifier: 'id',
        name: 'test.org',
        uri: 'uri',
        lastOpened: DateTime.now(),
        starredIdx: 0,
      );

      expect(file.isStarred, true);
      expect(file.isNotStarred, false);
    });

    test('isStarred returns false when starredIdx is -1', () {
      final file = RememberedFile(
        identifier: 'id',
        name: 'test.org',
        uri: 'uri',
        lastOpened: DateTime.now(),
        starredIdx: -1,
      );

      expect(file.isStarred, false);
      expect(file.isNotStarred, true);
    });

    test('copyWith preserves unchanged fields', () {
      final original = RememberedFile(
        identifier: 'id',
        name: 'test.org',
        uri: 'uri',
        lastOpened: DateTime(2024, 1, 1),
        starredIdx: 5,
      );

      final copied = original.copyWith(name: 'new.org');

      expect(copied.identifier, 'id');
      expect(copied.name, 'new.org');
      expect(copied.uri, 'uri');
      expect(copied.lastOpened, DateTime(2024, 1, 1));
      expect(copied.starredIdx, 5);
    });

    test('fromJson parses correctly', () {
      final json = {
        'identifier': 'id',
        'name': 'test.org',
        'uri': 'uri',
        'lastOpened': 1704067200000, // 2024-01-01 00:00:00 UTC
        'pinnedIdx': 3,
      };

      final file = RememberedFile.fromJson(json);

      expect(file.identifier, 'id');
      expect(file.name, 'test.org');
      expect(file.uri, 'uri');
      expect(file.starredIdx, 3);
    });

    test('fromJson uses identifier as uri fallback', () {
      final json = {
        'identifier': 'content://id',
        'name': 'test.org',
        'lastOpened': 1704067200000,
      };

      final file = RememberedFile.fromJson(json);

      expect(file.uri, 'content://id');
    });

    test('toJson writes pinnedIdx for backward compatibility', () {
      final file = RememberedFile(
        identifier: 'id',
        name: 'test.org',
        uri: 'uri',
        lastOpened: DateTime(2024, 1, 1),
        starredIdx: 2,
      );

      final json = file.toJson();

      expect(json['pinnedIdx'], 2);
      expect(json.containsKey('starredIdx'), false);
    });
  });
}
