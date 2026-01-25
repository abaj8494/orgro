import 'package:flutter/services.dart';

const _channel = MethodChannel('com.madlonkay.orgro/native_directory');

/// Represents a file or directory entry from native directory listing
class DirectoryEntry {
  const DirectoryEntry({
    required this.name,
    required this.identifier,
    required this.uri,
    required this.isDirectory,
  });

  factory DirectoryEntry.fromMap(Map<String, dynamic> map) {
    return DirectoryEntry(
      name: map['name'] as String,
      identifier: map['identifier'] as String,
      uri: map['uri'] as String,
      isDirectory: map['isDirectory'] as bool,
    );
  }

  final String name;
  final String identifier;
  final String uri;
  final bool isDirectory;

  bool get isOrgFile =>
      !isDirectory && name.toLowerCase().endsWith('.org');

  @override
  String toString() =>
      'DirectoryEntry[$name, isDirectory=$isDirectory]';
}

/// Lists the contents of a directory given its identifier.
/// Returns only directories and .org files.
Future<List<DirectoryEntry>> listDirectory(String dirIdentifier) async {
  final result = await _channel.invokeMethod<List<dynamic>>(
    'listDirectory',
    {'dirIdentifier': dirIdentifier},
  );

  if (result == null) {
    return [];
  }

  final entries = result
      .cast<Map<dynamic, dynamic>>()
      .map((e) => DirectoryEntry.fromMap(e.cast<String, dynamic>()))
      .where((entry) => entry.isDirectory || entry.isOrgFile)
      .toList();

  // Sort: directories first, then alphabetically by name
  entries.sort((a, b) {
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return entries;
}

/// Recursively lists all .org files in a directory and its subdirectories.
/// Returns only .org files (no directories).
Future<List<DirectoryEntry>> listDirectoryRecursive(String dirIdentifier) async {
  final result = await _channel.invokeMethod<List<dynamic>>(
    'listDirectoryRecursive',
    {'dirIdentifier': dirIdentifier},
  );

  if (result == null) {
    return [];
  }

  final entries = result
      .cast<Map<dynamic, dynamic>>()
      .map((e) => DirectoryEntry.fromMap(e.cast<String, dynamic>()))
      .toList();

  // Sort alphabetically by name
  entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return entries;
}
