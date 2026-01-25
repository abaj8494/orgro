import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:orgro/l10n/app_localizations.dart';
import 'package:orgro/src/components/about.dart';
import 'package:orgro/src/components/remembered_files.dart';
import 'package:orgro/src/file_picker.dart';
import 'package:orgro/src/pages/start/remembered_files.dart';
import 'package:orgro/src/pages/start/util.dart';
import 'package:orgro/src/preferences.dart';
import 'package:orgro/src/routes/routes.dart';

class StartDrawer extends StatelessWidget {
  const StartDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final remembered = RememberedFiles.of(context);
    final starred = remembered.starred;
    final recents = remembered.recents
      ..sort((a, b) {
        final result = switch (remembered.sortKey) {
          RecentFilesSortKey.lastOpened => a.lastOpened.compareTo(b.lastOpened),
          RecentFilesSortKey.name => a.name.compareTo(b.name),
          RecentFilesSortKey.location =>
            (appName(context, a.uri) ?? a.uri).compareTo(
              appName(context, b.uri) ?? b.uri,
            ),
        };
        return remembered.sortOrder == SortOrder.ascending ? result : -result;
      });

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              margin: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.appTitle,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Starred files section
                  if (starred.isNotEmpty) ...[
                    _SectionHeader(
                      title: AppLocalizations.of(context)!.sectionHeaderStarredFiles,
                      icon: Icons.star,
                    ),
                    for (final file in starred)
                      _DrawerFileListTile(file: file, isStarred: true),
                  ],
                  // Recent files section
                  if (recents.isNotEmpty) ...[
                    _SectionHeader(
                      title: AppLocalizations.of(context)!.sectionHeaderRecentFiles,
                      icon: Icons.history,
                      trailing: const _RecentFilesSortButton(),
                    ),
                    for (final file in recents)
                      _DrawerFileListTile(file: file, isStarred: false),
                  ],
                  if (starred.isEmpty && recents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No recent files',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).disabledColor,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(AppLocalizations.of(context)!.menuItemSettings),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, Routes.settings);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(AppLocalizations.of(context)!.menuItemAbout),
              onTap: () {
                Navigator.pop(context);
                openAboutDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _RecentFilesSortButton extends StatelessWidget {
  const _RecentFilesSortButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.sort, size: 20),
      onPressed: () => showRecentFilesSortDialog(context),
      tooltip: AppLocalizations.of(context)!.recentFilesSortDialogTitle,
    );
  }
}

class _DrawerFileListTile extends StatelessWidget {
  const _DrawerFileListTile({
    required this.file,
    required this.isStarred,
  });

  final RememberedFile file;
  final bool isStarred;

  @override
  Widget build(BuildContext context) {
    final remembered = RememberedFiles.of(context);

    return Slidable(
      key: ValueKey(file.uri),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.4,
        children: [
          SlidableAction(
            backgroundColor: isStarred ? Colors.grey : Colors.amber,
            foregroundColor: Colors.white,
            icon: isStarred ? Icons.star_border : Icons.star,
            onPressed: (_) {
              if (isStarred) {
                remembered.unstar(file);
              } else {
                remembered.star(file);
              }
            },
          ),
          SlidableAction(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            onPressed: (_) => remembered.remove(file),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(
          Icons.description,
          color: Theme.of(context).disabledColor,
        ),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _formatLastOpened(context, file.lastOpened),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        dense: true,
        onTap: () async {
          Navigator.pop(context);
          await loadAndRememberFile(
            context,
            readFileWithIdentifier(file.identifier),
          );
        },
      ),
    );
  }

  String _formatLastOpened(BuildContext context, DateTime lastOpened) {
    final now = DateTime.now();
    final diff = now.difference(lastOpened);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${lastOpened.day}/${lastOpened.month}/${lastOpened.year}';
    }
  }
}
