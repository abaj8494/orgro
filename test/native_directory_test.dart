import 'package:flutter_test/flutter_test.dart';
import 'package:orgro/src/data_source.dart';
import 'package:orgro/src/native_directory.dart';

void main() {
  group('DirectoryEntry', () {
    test('creates entry from map with all fields', () {
      final map = {
        'name': 'test.org',
        'identifier': 'content://test/1',
        'uri': 'content://test/uri/1',
        'isDirectory': false,
      };

      final entry = DirectoryEntry.fromMap(map);

      expect(entry.name, 'test.org');
      expect(entry.identifier, 'content://test/1');
      expect(entry.uri, 'content://test/uri/1');
      expect(entry.isDirectory, false);
    });

    test('isOrgFile returns true for .org files', () {
      final entry = DirectoryEntry.fromMap({
        'name': 'notes.org',
        'identifier': 'id',
        'uri': 'uri',
        'isDirectory': false,
      });

      expect(entry.isOrgFile, true);
    });

    test('isOrgFile returns true for .ORG files (case insensitive)', () {
      final entry = DirectoryEntry.fromMap({
        'name': 'NOTES.ORG',
        'identifier': 'id',
        'uri': 'uri',
        'isDirectory': false,
      });

      expect(entry.isOrgFile, true);
    });

    test('isOrgFile returns false for non-.org files', () {
      final entry = DirectoryEntry.fromMap({
        'name': 'notes.txt',
        'identifier': 'id',
        'uri': 'uri',
        'isDirectory': false,
      });

      expect(entry.isOrgFile, false);
    });

    test('isOrgFile returns false for directories', () {
      final entry = DirectoryEntry.fromMap({
        'name': 'folder.org',
        'identifier': 'id',
        'uri': 'uri',
        'isDirectory': true,
      });

      expect(entry.isOrgFile, false);
    });

    test('isOrgFile handles files with multiple dots', () {
      final entry = DirectoryEntry.fromMap({
        'name': 'my.notes.org',
        'identifier': 'id',
        'uri': 'uri',
        'isDirectory': false,
      });

      expect(entry.isOrgFile, true);
    });

    test('directory entry properties', () {
      final entry = DirectoryEntry.fromMap({
        'name': 'Documents',
        'identifier': 'content://docs',
        'uri': 'content://docs/uri',
        'isDirectory': true,
      });

      expect(entry.name, 'Documents');
      expect(entry.isDirectory, true);
      expect(entry.isOrgFile, false);
    });
  });

  group('NativeDirectoryInfo', () {
    test('creates info with constructor', () {
      final info = NativeDirectoryInfo(
        'My Folder',
        'content://folder/123',
        'content://folder/uri/123',
      );

      expect(info.identifier, 'content://folder/123');
      expect(info.uri, 'content://folder/uri/123');
      expect(info.name, 'My Folder');
    });
  });
}
