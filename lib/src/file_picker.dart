import 'dart:async';
import 'dart:io';

import 'package:file_picker_writable/file_picker_writable.dart';
import 'package:flutter/material.dart';
import 'package:orgro/l10n/app_localizations.dart';
import 'package:orgro/src/capture.dart';
import 'package:orgro/src/data_source.dart';
import 'package:orgro/src/debug.dart';
import 'package:orgro/src/pages/start/util.dart';

Future<NativeDataSource?> pickFile() async =>
    FilePickerWritable().openFile(LoadedNativeDataSource.fromExternal);

Future<NativeDataSource?> createAndLoadFile(String fileName) async {
  final fileInfo = await FilePickerWritable().openFileForCreate(
    fileName: fileName,
    writer: (file) => file.writeAsString(''),
  );
  return fileInfo == null ? null : readFileWithIdentifier(fileInfo.identifier);
}

Future<FileInfo?> createAndSaveFile(String fileName, String content) async =>
    await FilePickerWritable().openFileForCreate(
      fileName: fileName,
      writer: (file) => file.writeAsString(content),
    );

Future<NativeDirectoryInfo?> pickDirectory({String? initialDirUri}) async {
  final dirInfo = await FilePickerWritable().openDirectory(
    initialDirUri: initialDirUri,
  );
  return dirInfo == null
      ? null
      : NativeDirectoryInfo(
          dirInfo.fileName ?? 'unknown',
          dirInfo.identifier,
          dirInfo.uri,
        );
}

Future<NativeDataSource> readFileWithIdentifier(
  String identifier, {
  String? parentDirIdentifier,
  String? rootDirIdentifier,
}) async {
  final source = await FilePickerWritable().readFile(
    identifier: identifier,
    reader: LoadedNativeDataSource.fromExternal,
  );
  debugPrint('readFileWithIdentifier: name=${source.name}, persistable=${source.persistable}, parentDir=$parentDirIdentifier, rootDir=$rootDirIdentifier');
  // If any directory info provided, create a new source with that info
  if (parentDirIdentifier != null || rootDirIdentifier != null) {
    // If only root is provided, use it as parent too (for search results)
    final effectiveParent = parentDirIdentifier ?? rootDirIdentifier;
    final effectiveRoot = rootDirIdentifier ?? parentDirIdentifier;
    // Files from configured folder tree have persistent access via the tree URI,
    // so force persistable=true when rootDirIdentifier is provided
    final isPersistable = rootDirIdentifier != null ? true : source.persistable;
    debugPrint('readFileWithIdentifier: setting persistable=$isPersistable (original=${source.persistable})');
    return NativeDataSource(
      source.name,
      source.identifier,
      source.uri,
      persistable: isPersistable,
      parentDirIdentifier: effectiveParent,
      rootDirIdentifier: effectiveRoot,
    );
  }
  return source;
}

Future<bool> canObtainNativeDirectoryPermissions() async =>
    FilePickerWritable().isDirectoryAccessSupported();

Future<void> disposeNativeSourceIdentifier(String identifier) =>
    FilePickerWritable().disposeIdentifier(identifier);

mixin PlatformOpenHandler<T extends StatefulWidget> on State<T> {
  late final FilePickerState _filePickerState;

  @override
  void initState() {
    super.initState();
    _filePickerState = FilePickerWritable().init()
      ..registerFileOpenHandler(_loadFile)
      ..registerErrorEventHandler(_handleError)
      ..registerUriHandler(_handleUri);
  }

  Future<bool> _loadFile(FileInfo fileInfo, File file) async {
    NativeDataSource openFileInfo;
    try {
      openFileInfo = await LoadedNativeDataSource.fromExternal(fileInfo, file);
    } catch (e) {
      await _displayError(e.toString());
      return false;
    }
    if (!mounted) return false;
    await loadAndRememberFile(context, openFileInfo);
    return true;
  }

  Future<bool> _handleError(ErrorEvent event) async {
    await _displayError(event.message);
    return true;
  }

  Future<void> _displayError(String message) async => showDialog<void>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(AppLocalizations.of(context)!.dialogTitleError),
      children: [ListTile(title: Text(message))],
    ),
  );

  @override
  void dispose() {
    _filePickerState
      ..removeFileOpenHandler(_loadFile)
      ..removeErrorEventHandler(_handleError);
    super.dispose();
  }

  // It doesn't make a lot of sense to handle org-capture URIs here, but
  // file_picker_writable implements the callback that handles URI opening, so
  // for now we have no choice.
  //
  // TODO(aaron): See if file_picker_writable can refuse handling of non-file URIs
  bool _handleUri(Uri uri) {
    debugPrint('Received URI: $uri; scheme=${uri.scheme}, host=${uri.host}');
    if (isCaptureUri(uri)) {
      captureUri(context, uri).onError(logError);
      return true;
    }
    return false;
  }
}
