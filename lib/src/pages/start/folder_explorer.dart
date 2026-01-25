import 'package:flutter/material.dart';
import 'package:orgro/l10n/app_localizations.dart';
import 'package:orgro/src/debug.dart';
import 'package:orgro/src/file_picker.dart';
import 'package:orgro/src/native_directory.dart';
import 'package:orgro/src/pages/start/util.dart';

class FolderExplorerBody extends StatefulWidget {
  const FolderExplorerBody({
    required this.rootIdentifier,
    required this.rootName,
    super.key,
  });

  final String rootIdentifier;
  final String rootName;

  @override
  State<FolderExplorerBody> createState() => _FolderExplorerBodyState();
}

// Static sort state that persists across directory navigation
bool _sortAscending = true;

class _FolderExplorerBodyState extends State<FolderExplorerBody> {
  // Stack of directory identifiers for navigation (first is root)
  late List<String> _pathStack;
  // Stack of directory names for breadcrumbs
  late List<String> _nameStack;

  List<DirectoryEntry>? _entries;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pathStack = [widget.rootIdentifier];
    _nameStack = [widget.rootName];
    _loadCurrentDirectory();
  }

  @override
  void didUpdateWidget(FolderExplorerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootIdentifier != widget.rootIdentifier) {
      _pathStack = [widget.rootIdentifier];
      _nameStack = [widget.rootName];
      _loadCurrentDirectory();
    }
  }

  String get _currentIdentifier => _pathStack.last;

  Future<void> _loadCurrentDirectory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final entries = await listDirectory(_currentIdentifier);
      if (mounted) {
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      logError(e, s);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _navigateInto(DirectoryEntry entry) {
    setState(() {
      _pathStack.add(entry.identifier);
      _nameStack.add(entry.name);
    });
    _loadCurrentDirectory();
  }

  void _navigateUp() {
    if (_pathStack.length > 1) {
      setState(() {
        _pathStack.removeLast();
        _nameStack.removeLast();
      });
      _loadCurrentDirectory();
    }
  }

  void _navigateToLevel(int index) {
    if (index < _pathStack.length - 1) {
      setState(() {
        _pathStack.removeRange(index + 1, _pathStack.length);
        _nameStack.removeRange(index + 1, _nameStack.length);
      });
      _loadCurrentDirectory();
    }
  }

  Future<void> _openFile(DirectoryEntry entry) async {
    try {
      final dataSource = await readFileWithIdentifier(
        entry.identifier,
        parentDirIdentifier: _currentIdentifier,
        rootDirIdentifier: widget.rootIdentifier,
      );
      if (!mounted) return;
      await loadAndRememberFile(context, dataSource);
    } catch (e, s) {
      logError(e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _navigateToRoot() {
    if (_pathStack.length > 1) {
      setState(() {
        _pathStack.removeRange(1, _pathStack.length);
        _nameStack.removeRange(1, _nameStack.length);
      });
      _loadCurrentDirectory();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Handle back button: navigate up folder hierarchy before exiting
    return PopScope(
      canPop: _pathStack.length <= 1, // Can pop (exit) only when at root
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _pathStack.length > 1) {
          // Back was pressed but we didn't pop - navigate up instead
          _navigateUp();
        }
      },
      child: Column(
        children: [
          _BreadcrumbBar(
            names: _nameStack,
            onTap: _navigateToLevel,
            canGoUp: _pathStack.length > 1,
            onUpPressed: _navigateUp,
            onHomePressed: _navigateToRoot,
            sortAscending: _sortAscending,
            onSortChanged: (ascending) {
              setState(() => _sortAscending = ascending);
            },
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.folderExplorerLoading),
          ],
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
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.folderExplorerError,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadCurrentDirectory,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open,
                size: 48,
                color: Theme.of(context).disabledColor,
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.folderExplorerNoOrgFiles,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).disabledColor,
                    ),
              ),
            ],
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

    return RefreshIndicator(
      onRefresh: _loadCurrentDirectory,
      child: ListView.builder(
        itemCount: sortedEntries.length,
        itemBuilder: (context, index) {
          final entry = sortedEntries[index];
          return _DirectoryEntryTile(
            entry: entry,
            onTap: () =>
                entry.isDirectory ? _navigateInto(entry) : _openFile(entry),
          );
        },
      ),
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({
    required this.names,
    required this.onTap,
    required this.canGoUp,
    required this.onUpPressed,
    required this.onHomePressed,
    required this.sortAscending,
    required this.onSortChanged,
  });

  final List<String> names;
  final void Function(int index) onTap;
  final bool canGoUp;
  final VoidCallback onUpPressed;
  final VoidCallback onHomePressed;
  final bool sortAscending;
  final void Function(bool ascending) onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (canGoUp) ...[
            IconButton(
              icon: const Icon(Icons.home),
              onPressed: onHomePressed,
              tooltip: 'Go to root folder',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward),
              onPressed: onUpPressed,
              tooltip: 'Go up',
            ),
          ],
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < names.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Theme.of(context).disabledColor,
                      ),
                    InkWell(
                      onTap: i < names.length - 1 ? () => onTap(i) : null,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          names[i],
                          style: TextStyle(
                            fontWeight: i == names.length - 1
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: i == names.length - 1
                                ? null
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          PopupMenuButton<bool>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: onSortChanged,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: true,
                child: Row(
                  children: [
                    Icon(
                      Icons.check,
                      color: sortAscending
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
                      color: !sortAscending
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
        ],
      ),
    );
  }
}

class _DirectoryEntryTile extends StatelessWidget {
  const _DirectoryEntryTile({
    required this.entry,
    required this.onTap,
  });

  final DirectoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        entry.isDirectory ? Icons.folder : Icons.description,
        color: entry.isDirectory
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      title: Text(entry.name),
      trailing: entry.isDirectory ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }
}
