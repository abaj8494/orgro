import 'package:flutter/material.dart';
import 'package:orgro/l10n/app_localizations.dart';
import 'package:orgro/src/components/remembered_files.dart';
import 'package:orgro/src/data_source.dart';
import 'package:orgro/src/file_picker.dart';
import 'package:orgro/src/native_directory.dart';
import 'package:orgro/src/pages/start/util.dart';
import 'package:orgro/src/preferences.dart';

// Static sort state that persists across directory navigation
bool _sortAscending = true;

/// A minimal drawer for the document reader view.
/// Contains: navigation header, scoped file tree, and recent files.
class ReaderDrawer extends StatefulWidget {
  const ReaderDrawer({
    required this.dataSource,
    required this.currentFileName,
    super.key,
  });

  final DataSource dataSource;
  final String currentFileName;

  @override
  State<ReaderDrawer> createState() => _ReaderDrawerState();
}

class _ReaderDrawerState extends State<ReaderDrawer> {
  // Stack of directory identifiers for navigation
  List<String> _pathStack = [];
  List<String> _nameStack = [];
  List<DirectoryEntry>? _entries;
  bool _isLoading = false;
  String? _error;
  String? _rootIdentifier;
  String _rootName = 'Folder';

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initializeFromDataSource();
    }
  }

  void _initializeFromDataSource() {
    // Get root from app preferences - this is the configured folder
    final prefs = Preferences.of(context, PrefsAspect.configuredFolder);
    final configuredRoot = prefs.configuredFolderIdentifier;
    final configuredRootName = prefs.configuredFolderName ?? 'Folder';

    final source = widget.dataSource;
    debugPrint('ReaderDrawer: dataSource type=${source.runtimeType}');
    debugPrint('ReaderDrawer: configuredRoot=$configuredRoot');
    if (source is NativeDataSource) {
      debugPrint('ReaderDrawer: parentDirIdentifier=${source.parentDirIdentifier}');
      debugPrint('ReaderDrawer: rootDirIdentifier=${source.rootDirIdentifier}');
    }

    // Always use configured folder as root (HOME)
    _rootIdentifier = configuredRoot;
    _rootName = configuredRootName;

    if (source is NativeDataSource && source.parentDirIdentifier != null) {
      _pathStack = [source.parentDirIdentifier!];
      final folderName = _extractFolderName(source.parentDirIdentifier!);
      _nameStack = [folderName];
      _loadDirectory();
    } else if (configuredRoot != null) {
      // If no parent dir but we have configured root, start from root
      _pathStack = [configuredRoot];
      _nameStack = [configuredRootName];
      _loadDirectory();
    } else {
      debugPrint('ReaderDrawer: Cannot show file tree - no configured folder');
    }
  }

  String _extractFolderName(String identifier) {
    try {
      final uri = Uri.parse(Uri.decodeFull(identifier));
      final path = uri.path;
      if (path.isNotEmpty) {
        final segments = path.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.isNotEmpty) {
          return segments.last;
        }
      }
    } catch (_) {}
    return 'Folder';
  }

  String? get _currentIdentifier =>
      _pathStack.isNotEmpty ? _pathStack.last : null;

  bool get _canShowFileTree {
    // Can show file tree if we have a path stack (meaning we have somewhere to show)
    return _pathStack.isNotEmpty;
  }

  // Can go up if not at root
  bool get _canGoUp =>
      _pathStack.length > 1 ||
      (_pathStack.isNotEmpty && _pathStack.first != _rootIdentifier);

  bool get _isAtRoot =>
      _pathStack.length == 1 && _pathStack.first == _rootIdentifier;

  Future<void> _loadDirectory() async {
    final identifier = _currentIdentifier;
    if (identifier == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final entries = await listDirectory(identifier);
      if (mounted) {
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToRoot() {
    // If already at root, exit to File Manager HOME
    if (_isAtRoot) {
      _closeDocument();
      return;
    }
    if (_rootIdentifier != null) {
      setState(() {
        _pathStack = [_rootIdentifier!];
        _nameStack = [_rootName];
      });
      _loadDirectory();
    }
  }

  void _navigateUp() {
    if (_pathStack.length > 1) {
      // Normal case: go up in the stack
      setState(() {
        _pathStack.removeLast();
        _nameStack.removeLast();
      });
      _loadDirectory();
    } else if (_pathStack.isNotEmpty && _pathStack.first != _rootIdentifier && _rootIdentifier != null) {
      // We're at the file's parent but not at root - go to root
      _navigateToRoot();
    }
  }

  void _navigateInto(DirectoryEntry entry) {
    setState(() {
      _pathStack.add(entry.identifier);
      _nameStack.add(entry.name);
    });
    _loadDirectory();
  }

  Future<void> _openFile(DirectoryEntry entry) async {
    Navigator.pop(context); // Close drawer
    try {
      final dataSource = await readFileWithIdentifier(
        entry.identifier,
        parentDirIdentifier: _currentIdentifier,
        rootDirIdentifier: _rootIdentifier,
      );
      if (!mounted) return;
      await loadAndRememberFile(context, dataSource);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _closeDocument() {
    Navigator.pop(context); // Close drawer
    // Pop all document pages to return to the home/folder explorer
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Navigation header with HOME, folder name, UP
            _buildNavigationHeader(context),
            const Divider(height: 1),

            // File tree section
            if (_canShowFileTree) ...[
              Expanded(child: _buildFileTree(context)),
            ] else ...[
              Expanded(
                child: Center(
                  child: Text(
                    'File tree not available',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).disabledColor,
                        ),
                  ),
                ),
              ),
            ],

            // Recent files section
            const Divider(height: 1),
            _buildRecentFilesSection(context),

            // Close document button at bottom
            const Divider(height: 1),
            _buildCloseButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationHeader(BuildContext context) {
    final currentFolderName =
        _nameStack.isNotEmpty ? _nameStack.last : 'Folder';

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // HOME button - press twice to exit to File Manager HOME
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: _navigateToRoot,
            tooltip: _isAtRoot ? 'Exit to File Manager' : 'Go to root folder',
          ),
          // Folder name (green color)
          Expanded(
            child: Text(
              currentFolderName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          // Sort button
          PopupMenuButton<bool>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: (ascending) {
              setState(() => _sortAscending = ascending);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: true,
                child: Row(
                  children: [
                    Icon(
                      Icons.check,
                      color: _sortAscending
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                    ),
                    const SizedBox(width: 8),
                    const Text('Name (A-Z)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: false,
                child: Row(
                  children: [
                    Icon(
                      Icons.check,
                      color: !_sortAscending
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                    ),
                    const SizedBox(width: 8),
                    const Text('Name (Z-A)'),
                  ],
                ),
              ),
            ],
          ),
          // UP button
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            onPressed: _canGoUp ? _navigateUp : null,
            tooltip: 'Go up one folder',
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.exit_to_app),
      title: Text(AppLocalizations.of(context)!.readerDrawerClose),
      onTap: _closeDocument,
    );
  }

  Widget _buildFileTree(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(
                'Error loading files',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton(
                onPressed: _loadDirectory,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final entries = _entries ?? [];
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No .org files',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).disabledColor,
                ),
          ),
        ),
      );
    }

    // Sort entries: directories first, then by name
    final sortedEntries = List<DirectoryEntry>.from(entries);
    sortedEntries.sort((a, b) {
      // Directories always come first
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      // Then sort by name
      final comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return _sortAscending ? comparison : -comparison;
    });

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: sortedEntries.length,
      itemBuilder: (context, index) {
        final entry = sortedEntries[index];
        final isCurrentFile =
            !entry.isDirectory && entry.name == widget.currentFileName;

        return ListTile(
          dense: true,
          leading: Icon(
            entry.isDirectory ? Icons.folder : Icons.description,
            size: 20,
            color: entry.isDirectory
                ? Theme.of(context).colorScheme.primary
                : isCurrentFile
                    ? Theme.of(context).colorScheme.secondary
                    : null,
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isCurrentFile
                ? TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.secondary,
                  )
                : null,
          ),
          trailing:
              entry.isDirectory ? const Icon(Icons.chevron_right, size: 18) : null,
          onTap: () =>
              entry.isDirectory ? _navigateInto(entry) : _openFile(entry),
        );
      },
    );
  }

  Widget _buildRecentFilesSection(BuildContext context) {
    final remembered = RememberedFiles.of(context);
    final starred = remembered.starred.take(3).toList();
    final recents = remembered.recents.take(5).toList();

    debugPrint('ReaderDrawer: starred=${starred.length}, recents=${recents.length}, total=${remembered.list.length}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Starred files section
        if (starred.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.star,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.sectionHeaderStarredFiles,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ),
          ...starred.map((file) => _buildFileListTile(context, file, isStarred: true)),
        ],
        // Recent files section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.readerDrawerRecentFiles,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
        ),
        if (recents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No recent files',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
            ),
          )
        else
          ...recents.map((file) => _buildFileListTile(context, file, isStarred: false)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildFileListTile(BuildContext context, RememberedFile file, {required bool isStarred}) {
    return ListTile(
      dense: true,
      leading: Icon(
        isStarred ? Icons.star : Icons.description,
        size: 20,
        color: isStarred
            ? Theme.of(context).colorScheme.secondary
            : Theme.of(context).disabledColor,
      ),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        Navigator.pop(context); // Close drawer
        await loadAndRememberFile(
          context,
          readFileWithIdentifier(
            file.identifier,
            parentDirIdentifier: file.parentDirIdentifier,
            rootDirIdentifier: file.rootDirIdentifier,
          ),
        );
      },
    );
  }
}
