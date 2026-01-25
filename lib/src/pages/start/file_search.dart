import 'package:flutter/material.dart';
import 'package:orgro/src/native_directory.dart';

/// Search delegate for fuzzy searching .org files in a directory tree.
class FileSearchDelegate extends SearchDelegate<DirectoryEntry?> {
  FileSearchDelegate({required this.rootIdentifier});

  final String rootIdentifier;
  List<DirectoryEntry>? _allFiles;
  bool _isLoading = false;
  String? _error;

  @override
  String get searchFieldLabel => 'Search .org files...';

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
          tooltip: 'Clear',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
      tooltip: 'Back',
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSuggestions(context);

  Widget _buildSuggestions(BuildContext context) {
    // Load files if not yet loaded
    if (_allFiles == null && !_isLoading) {
      _loadAllFiles();
    }

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading files...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _error = null;
                _loadAllFiles();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final files = _allFiles ?? [];
    if (files.isEmpty) {
      return Center(
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
              'No .org files found',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
            ),
          ],
        ),
      );
    }

    final results = _fuzzySearch(query, files);

    if (results.isEmpty && query.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              'No matches for "$query"',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final entry = results[index];
        return ListTile(
          leading: const Icon(Icons.description),
          title: _buildHighlightedTitle(context, entry.name, query),
          onTap: () => close(context, entry),
        );
      },
    );
  }

  Widget _buildHighlightedTitle(
      BuildContext context, String name, String query) {
    if (query.isEmpty) {
      return Text(name);
    }

    final lowerName = name.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // Find matching character positions
    final matches = <int>[];
    int queryIndex = 0;
    for (int i = 0; i < name.length && queryIndex < lowerQuery.length; i++) {
      if (lowerName[i] == lowerQuery[queryIndex]) {
        matches.add(i);
        queryIndex++;
      }
    }

    if (matches.isEmpty) {
      return Text(name);
    }

    // Build text spans with highlighting
    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final matchIndex in matches) {
      if (matchIndex > lastEnd) {
        spans.add(TextSpan(text: name.substring(lastEnd, matchIndex)));
      }
      spans.add(TextSpan(
        text: name[matchIndex],
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ));
      lastEnd = matchIndex + 1;
    }
    if (lastEnd < name.length) {
      spans.add(TextSpan(text: name.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyLarge,
        children: spans,
      ),
    );
  }

  Future<void> _loadAllFiles() async {
    _isLoading = true;
    _error = null;
    // Trigger rebuild to show loading state
    // Note: SearchDelegate doesn't have setState, so we need to use query change
    final currentQuery = query;
    query = '$currentQuery ';
    query = currentQuery;

    try {
      _allFiles = await listDirectoryRecursive(rootIdentifier);
      _isLoading = false;
      // Trigger rebuild
      query = '$currentQuery ';
      query = currentQuery;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      query = '$currentQuery ';
      query = currentQuery;
    }
  }

  /// Fuzzy search: all query characters must appear in order in the filename.
  List<DirectoryEntry> _fuzzySearch(String query, List<DirectoryEntry> files) {
    if (query.isEmpty) {
      // Show first 50 files when no query
      return files.take(50).toList();
    }

    final lowerQuery = query.toLowerCase();

    final matches = files.where((f) {
      final name = f.name.toLowerCase();
      int queryIndex = 0;
      for (int i = 0; i < name.length && queryIndex < lowerQuery.length; i++) {
        if (name[i] == lowerQuery[queryIndex]) {
          queryIndex++;
        }
      }
      return queryIndex == lowerQuery.length;
    }).toList();

    // Sort: prefer matches at start, then by name length, then alphabetically
    matches.sort((a, b) {
      final aName = a.name.toLowerCase();
      final bName = b.name.toLowerCase();
      final aStartsWith = aName.startsWith(lowerQuery);
      final bStartsWith = bName.startsWith(lowerQuery);

      if (aStartsWith && !bStartsWith) return -1;
      if (!aStartsWith && bStartsWith) return 1;

      final aContains = aName.contains(lowerQuery);
      final bContains = bName.contains(lowerQuery);

      if (aContains && !bContains) return -1;
      if (!aContains && bContains) return 1;

      // Prefer shorter names (more relevant matches)
      if (a.name.length != b.name.length) {
        return a.name.length.compareTo(b.name.length);
      }

      return aName.compareTo(bName);
    });

    return matches;
  }
}
