import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orgro/l10n/app_localizations.dart';
import 'package:orgro/src/pages/start/folder_explorer.dart';

void main() {
  const channel = MethodChannel('com.madlonkay.orgro/native_directory');

  TestWidgetsFlutterBinding.ensureInitialized();

  group('FolderExplorerBody', () {
    setUp(() {
      // Set up the method channel mock
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'listDirectory') {
          // Return mock directory entries
          return [
            {
              'name': 'notes.org',
              'identifier': 'content://test/notes',
              'uri': 'content://test/uri/notes',
              'isDirectory': false,
            },
            {
              'name': 'Subfolder',
              'identifier': 'content://test/subfolder',
              'uri': 'content://test/uri/subfolder',
              'isDirectory': true,
            },
            {
              'name': 'another.org',
              'identifier': 'content://test/another',
              'uri': 'content://test/uri/another',
              'isDirectory': false,
            },
          ];
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Widget buildTestWidget() {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: FolderExplorerBody(
            rootIdentifier: 'content://test/root',
            rootName: 'Test Folder',
          ),
        ),
      );
    }

    testWidgets('displays loading indicator initially', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Initially should show loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays directory entries after loading', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Should show the file entries
      expect(find.text('notes.org'), findsOneWidget);
      expect(find.text('Subfolder'), findsOneWidget);
      expect(find.text('another.org'), findsOneWidget);
    });

    testWidgets('displays breadcrumb with root folder name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Should show the root folder name in breadcrumbs
      expect(find.text('Test Folder'), findsOneWidget);
    });

    testWidgets('shows folder icon for directories', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Should have folder icons for directories
      expect(find.byIcon(Icons.folder), findsAtLeast(1));
    });

    testWidgets('shows file icon for .org files', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Should have description icons for files
      expect(find.byIcon(Icons.description), findsAtLeast(1));
    });

    testWidgets('shows chevron for directories', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Should have chevron_right for navigable directories
      expect(find.byIcon(Icons.chevron_right), findsAtLeast(1));
    });
  });

  group('FolderExplorerBody error handling', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(
          code: 'ERROR',
          message: 'Failed to list directory',
        );
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('displays error state when listing fails', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: FolderExplorerBody(
              rootIdentifier: 'content://test/root',
              rootName: 'Test Folder',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show error icon
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // Should show retry button
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });

  group('FolderExplorerBody empty directory', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return <Map<String, dynamic>>[];
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('displays empty state for empty directory', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: FolderExplorerBody(
              rootIdentifier: 'content://test/root',
              rootName: 'Test Folder',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show folder_open icon for empty state
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });
  });
}
