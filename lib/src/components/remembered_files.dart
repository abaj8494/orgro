import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:orgro/src/agenda.dart';
import 'package:orgro/src/debug.dart';
import 'package:orgro/src/file_picker.dart';
import 'package:orgro/src/preferences.dart';

enum RecentFilesSortKey { lastOpened, name, location }

extension RecentFilesSortKeyPersistence on RecentFilesSortKey? {
  static RecentFilesSortKey? fromString(String? key) => switch (key) {
    _kRecentFilesSortKeyLastOpened => RecentFilesSortKey.lastOpened,
    _kRecentFilesSortKeyName => RecentFilesSortKey.name,
    _kRecentFilesSortKeyLocation => RecentFilesSortKey.location,
    _ => null,
  };

  String? get persistableString => switch (this) {
    RecentFilesSortKey.lastOpened => _kRecentFilesSortKeyLastOpened,
    RecentFilesSortKey.name => _kRecentFilesSortKeyName,
    RecentFilesSortKey.location => _kRecentFilesSortKeyLocation,
    null => null,
  };
}

const _kRecentFilesSortKeyLastOpened = 'last_opened';
const _kRecentFilesSortKeyName = 'name';
const _kRecentFilesSortKeyLocation = 'location';

class RememberedFile {
  RememberedFile.fromJson(Map<String, dynamic> json)
    : this(
        identifier: json['identifier'] as String,
        name: json['name'] as String,
        // Older versions of Orgro did not store the URI, so fall back to the
        // identifier
        uri: (json['uri'] ?? json['identifier']) as String,
        lastOpened: DateTime.fromMillisecondsSinceEpoch(
          json['lastOpened'] as int,
        ),
        // Keep reading from 'pinnedIdx' for backward compatibility
        starredIdx: json['pinnedIdx'] as int? ?? -1,
        parentDirIdentifier: json['parentDirIdentifier'] as String?,
        rootDirIdentifier: json['rootDirIdentifier'] as String?,
      );

  const RememberedFile({
    required this.identifier,
    required this.name,
    required this.uri,
    required this.lastOpened,
    this.starredIdx = -1,
    this.parentDirIdentifier,
    this.rootDirIdentifier,
  }) : assert(starredIdx >= -1, 'Starred index must be -1 or >= 0');

  final String identifier;
  final String name;
  final String uri;
  final DateTime lastOpened;
  final int starredIdx;
  final String? parentDirIdentifier;
  final String? rootDirIdentifier;

  bool get isStarred => starredIdx != -1;
  bool get isNotStarred => !isStarred;

  @override
  bool operator ==(Object other) =>
      other is RememberedFile &&
      identifier == other.identifier &&
      name == other.name &&
      uri == other.uri &&
      lastOpened == other.lastOpened &&
      starredIdx == other.starredIdx &&
      parentDirIdentifier == other.parentDirIdentifier &&
      rootDirIdentifier == other.rootDirIdentifier;

  @override
  int get hashCode => Object.hash(identifier, name, uri, lastOpened, starredIdx, parentDirIdentifier, rootDirIdentifier);

  Map<String, Object?> toJson() => {
    'identifier': identifier,
    'name': name,
    'uri': uri,
    'lastOpened': lastOpened.millisecondsSinceEpoch,
    // Keep writing to 'pinnedIdx' for backward compatibility
    'pinnedIdx': starredIdx,
    if (parentDirIdentifier != null) 'parentDirIdentifier': parentDirIdentifier,
    if (rootDirIdentifier != null) 'rootDirIdentifier': rootDirIdentifier,
  };

  RememberedFile copyWith({
    String? identifier,
    String? name,
    String? uri,
    DateTime? lastOpened,
    int? starredIdx,
    String? parentDirIdentifier,
    String? rootDirIdentifier,
  }) => RememberedFile(
    identifier: identifier ?? this.identifier,
    name: name ?? this.name,
    uri: uri ?? this.uri,
    lastOpened: lastOpened ?? this.lastOpened,
    starredIdx: starredIdx ?? this.starredIdx,
    parentDirIdentifier: parentDirIdentifier ?? this.parentDirIdentifier,
    rootDirIdentifier: rootDirIdentifier ?? this.rootDirIdentifier,
  );

  @override
  String toString() => 'RecentFile[$name:$_debugShortIdentifier]($starredIdx)';

  String get _debugShortIdentifier {
    final length = identifier.length;
    if (length > 20) {
      final front = identifier.substring(0, 10);
      final back = identifier.substring(length - 10);
      return '$front...$back';
    } else {
      return identifier;
    }
  }
}

class InheritedRememberedFiles extends InheritedWidget {
  const InheritedRememberedFiles(
    this.list,
    this.sortKey,
    this.sortOrder, {
    required this.add,
    required this.remove,
    required this.star,
    required this.unstar,
    required super.child,
    super.key,
  });

  final List<RememberedFile> list;
  final RecentFilesSortKey sortKey;
  final SortOrder sortOrder;
  final AsyncValueSetter<List<RememberedFile>> add;
  final AsyncValueSetter<RememberedFile> remove;
  final ValueChanged<RememberedFile> star;
  final ValueChanged<RememberedFile> unstar;

  List<RememberedFile> get starred =>
      list.where((f) => f.isStarred).toList()
        ..sort((a, b) => a.starredIdx.compareTo(b.starredIdx));

  List<RememberedFile> get recents => list.where((f) => f.isNotStarred).toList();

  bool get hasRememberedFiles => list.isNotEmpty;

  @override
  bool updateShouldNotify(InheritedRememberedFiles oldWidget) =>
      !listEquals(list, oldWidget.list) ||
      sortKey != oldWidget.sortKey ||
      sortOrder != oldWidget.sortOrder;
}

class RememberedFiles extends StatefulWidget {
  static InheritedRememberedFiles of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InheritedRememberedFiles>()!;

  const RememberedFiles({required this.child, super.key});

  final Widget child;

  @override
  State<RememberedFiles> createState() => _RememberedFilesState();
}

class _RememberedFilesState extends State<RememberedFiles> {
  InheritedPreferences get _prefs =>
      Preferences.of(context, PrefsAspect.recentFiles);
  List<RememberedFile> get _rememberedFiles => _prefs.rememberedFiles;
  _LifecycleEventHandler? _lifecycleEventHandler;

  Future<void> _reloadFuture = Future.value();

  Future<void> addRecentFiles(List<RememberedFile> newFiles) async {
    await _reloadFuture;
    newFiles = newFiles
        .map((newFile) {
          // If the new file is starred, we don't need to absorb an existing star
          if (newFile.isStarred) return newFile;
          final existingFile = _rememberedFiles
              .where((f) => f.uri == newFile.uri)
              .firstOrNull;
          if (existingFile == null) return newFile;
          return newFile.copyWith(starredIdx: existingFile.starredIdx);
        })
        .toList(growable: false);
    debugPrint('Adding recent files: $newFiles');
    await _prefs.addRecentFiles(newFiles);
  }

  Future<void> removeRecentFile(RememberedFile recentFile) async {
    debugPrint('Removing recent file: $recentFile');
    try {
      await disposeNativeSourceIdentifier(recentFile.identifier);
    } on Exception catch (e, s) {
      logError(e, s);
    }
    _prefs.removeAgendaFileJsons((json) => json['uri'] == recentFile.uri);
    await clearNotificationsForFiles((json) => json['uri'] == recentFile.uri);
    _prefs.removeRecentFile(recentFile);
  }

  void starFile(RememberedFile recentFile) {
    _prefs.starFile(recentFile);
  }

  void unstarFile(RememberedFile recentFile) {
    _prefs.unstarFile(recentFile);
  }

  @override
  void initState() {
    super.initState();
    _lifecycleEventHandler ??= _LifecycleEventHandler(onResume: _onResume);
    WidgetsBinding.instance.addObserver(_lifecycleEventHandler!);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleEventHandler!);
    super.dispose();
  }

  Future<void> _onResume() async {
    if (Platform.isAndroid) {
      // Only reload on resume on Android:
      //
      // - On Android there could be new Recent File entries due to other
      //   activities, but on iOS there is only a single "activity" so no
      //   pressing need to reload
      //
      // - On iOS a resume event occurs when returning from file/directory
      //   pickers, when we are likely to want to store something in shared
      //   prefs. Shared prefs are committed asynchronously on iOS (`commit` is
      //   a noop) so reloading at this point will clear what we just stored.
      debugPrint('Reloading recent files');
      await (_reloadFuture = _prefs.reload());
    }
  }

  @override
  Widget build(BuildContext context) {
    return InheritedRememberedFiles(
      _rememberedFiles,
      _prefs.recentFilesSortKey,
      _prefs.recentFilesSortOrder,
      add: addRecentFiles,
      remove: removeRecentFile,
      star: starFile,
      unstar: unstarFile,
      child: widget.child,
    );
  }
}

class _LifecycleEventHandler extends WidgetsBindingObserver {
  _LifecycleEventHandler({this.onResume});

  final VoidCallback? onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('App resumed');
        onResume?.call();
        break;
      default:
      // Nothing
    }
  }
}
