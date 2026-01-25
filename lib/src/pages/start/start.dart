import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orgro/l10n/app_localizations.dart';
import 'package:orgro/src/assets.dart';
import 'package:orgro/src/components/about.dart';
import 'package:orgro/src/components/dialogs.dart';
import 'package:orgro/src/debug.dart';
import 'package:orgro/src/entitlements.dart';
import 'package:orgro/src/file_picker.dart';
import 'package:orgro/src/fonts.dart';
import 'package:orgro/src/native_directory.dart';
import 'package:orgro/src/pages/pages.dart';
import 'package:orgro/src/pages/start/file_search.dart';
import 'package:orgro/src/pages/start/folder_explorer.dart';
import 'package:orgro/src/pages/start/start_drawer.dart';
import 'package:orgro/src/pages/start/util.dart';
import 'package:orgro/src/preferences.dart';
import 'package:orgro/src/routes/routes.dart';
import 'package:orgro/src/util.dart';

class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State createState() => StartPageState();
}

class StartPageState extends State<StartPage> with PlatformOpenHandler {
  @override
  Widget build(BuildContext context) {
    final prefs = Preferences.of(context, PrefsAspect.configuredFolder);
    final hasConfiguredFolder = prefs.hasConfiguredFolder;
    final folderName = prefs.configuredFolderName;

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menu',
          ),
        ),
        actions: _buildActions(
          hasConfiguredFolder: hasConfiguredFolder,
        ).toList(growable: false),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasConfiguredFolder
                  ? folderName ?? AppLocalizations.of(context)!.appTitle
                  : AppLocalizations.of(context)!.appTitle,
            ),
            const FontPreloader(),
          ],
        ),
      ),
      drawer: const StartDrawer(),
      body: _KeyboardShortcuts(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: hasConfiguredFolder
              ? FolderExplorerBody(
                  rootIdentifier: prefs.configuredFolderIdentifier!,
                  rootName: folderName ?? 'Folder',
                )
              : const _SetupBody(),
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(context, hasConfiguredFolder),
    );
  }

  Iterable<Widget> _buildActions({required bool hasConfiguredFolder}) sync* {
    yield PopupMenuButton<VoidCallback>(
      onSelected: (callback) => callback(),
      itemBuilder: (context) => [
        PopupMenuItem<VoidCallback>(
          value: () => _configureFolder(context),
          child: Text(AppLocalizations.of(context)!.menuItemConfigureFolder),
        ),
        if (hasConfiguredFolder) ...[
          PopupMenuItem<VoidCallback>(
            value: () => _openOrgroManual(context),
            child: Text(AppLocalizations.of(context)!.menuItemOrgroManual),
          ),
        ],
        if (!kReleaseMode && !kScreenshotMode) ...[
          const PopupMenuDivider(),
          if (hasConfiguredFolder)
            PopupMenuItem<VoidCallback>(
              value: () => _openOrgManual(context),
              child: Text(AppLocalizations.of(context)!.menuItemOrgManual),
            ),
          PopupMenuItem<VoidCallback>(
            value: () => _openTestFile(context),
            child: Text(AppLocalizations.of(context)!.menuItemTestFile),
          ),
        ],
      ],
    );
  }

  Widget _buildFloatingActionButton(BuildContext context, bool hasConfiguredFolder) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: 16,
      children: [
        if (hasConfiguredFolder)
          FloatingActionButton(
            tooltip: AppLocalizations.of(context)!.tooltipCreateFile,
            onPressed: () => _createAndOpenFile(context),
            heroTag: 'NewFileFAB',
            mini: true,
            child: const Icon(Icons.create),
          ),
        FloatingActionButton(
          tooltip: hasConfiguredFolder
              ? AppLocalizations.of(context)!.tooltipSearchFiles
              : AppLocalizations.of(context)!.tooltipConfigureFolder,
          onPressed: hasConfiguredFolder
              ? () => _searchFiles(context)
              : () => _configureFolder(context),
          heroTag: 'SearchFAB',
          foregroundColor: Theme.of(context).colorScheme.onSecondary,
          child: Icon(
            hasConfiguredFolder ? Icons.search : Icons.create_new_folder,
          ),
        ),
      ],
    );
  }

  Future<void> _configureFolder(BuildContext context) async {
    final dirInfo = await pickDirectory();
    if (dirInfo == null || !context.mounted) return;
    await Preferences.of(
      context,
      PrefsAspect.configuredFolder,
    ).setConfiguredFolder(dirInfo);
  }

  Future<void> _searchFiles(BuildContext context) async {
    final prefs = Preferences.of(context, PrefsAspect.configuredFolder);
    final rootIdentifier = prefs.configuredFolderIdentifier;
    if (rootIdentifier == null) return;

    final result = await showSearch<DirectoryEntry?>(
      context: context,
      delegate: FileSearchDelegate(rootIdentifier: rootIdentifier),
    );

    if (result != null && context.mounted) {
      // For search results, we know the root but not the exact parent folder
      // The parent will be resolved later if needed
      await loadAndRememberFile(
        context,
        readFileWithIdentifier(
          result.identifier,
          rootDirIdentifier: rootIdentifier,
          // parentDirIdentifier is unknown for search results
        ),
      );
    }
  }

  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var restored = false;
    if (!_inited) {
      _inited = true;
      // RestorationMixin.restoreRoute is ultimately called during
      // didChangeDependencies, so we do the same here.
      //
      // We don't use RestorationMixin here because we don't want StartPage to
      // have its own bucket; we want it and QuickActions to use the root bucket
      // so that routes remembered by either can be restored here.
      restored = _restoreRoute();
    }
    if (!restored && kFreemium) {
      final entitlements = UserEntitlements.of(context)!.entitlements;
      if (entitlements.locked) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openSettingsScreen(context),
        );
      }
    }
  }

  bool _restoreRoute() {
    final bucket = RestorationScope.of(context);
    final restoreRoute = bucket.read<String>(kRestoreRouteKey);
    debugPrint('restoreState; restoreRoute=$restoreRoute');
    if (restoreRoute == null) return false;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restoreData = json.decode(restoreRoute);
      final context = this.context;
      switch (restoreData) {
        case {'route': Routes.document, 'fileId': String fileId}:
          await loadAndRememberFile(context, readFileWithIdentifier(fileId));
          return;
        case {'route': Routes.document, 'url': String url}:
          await loadAndRememberUrl(context, Uri.parse(url));
          return;
        case {'route': Routes.document, 'assetKey': String key}:
          await loadAndRememberAsset(context, key);
          return;
        default:
          debugPrint('Unknown route: ${restoreData['route']}');
          return;
      }
    });
    return true;
  }
}

class _KeyboardShortcuts extends StatelessWidget {
  const _KeyboardShortcuts({required this.child});

  final Widget child;
  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        LogicalKeySet(platformShortcutKey, LogicalKeyboardKey.keyO): () =>
            loadAndRememberFile(context, pickFile()),
        LogicalKeySet(platformShortcutKey, LogicalKeyboardKey.keyN): () =>
            _createAndOpenFile(context),
        LogicalKeySet(platformShortcutKey, LogicalKeyboardKey.period): () =>
            _openSettingsScreen(context),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

class _SetupBody extends StatelessWidget {
  const _SetupBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.folder_open,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context)!.setupPromptTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.setupPromptBody,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  onPressed: () async {
                    final dirInfo = await pickDirectory();
                    if (dirInfo == null || !context.mounted) return;
                    await Preferences.of(
                      context,
                      PrefsAspect.configuredFolder,
                    ).setConfiguredFolder(dirInfo);
                  },
                  icon: const Icon(Icons.folder),
                  label: Text(AppLocalizations.of(context)!.buttonChooseFolder),
                ),
                const SizedBox(height: 48),
                const _SupportLink(),
                const _VersionInfoButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _createAndOpenFile(BuildContext context) async {
  final fileName = await showDialog<String>(
    context: context,
    builder: (context) => InputFileNameDialog(
      title: AppLocalizations.of(context)!.createFileDialogTitle,
    ),
  );
  if (fileName == null || !context.mounted) return;
  final orgFileName = fileName.toLowerCase().endsWith('.org')
      ? fileName
      : '$fileName.org';
  return await loadAndRememberFile(
    context,
    createAndLoadFile(orgFileName),
    mode: InitialMode.edit,
  );
}

Future<void> _openOrgroManual(BuildContext context) =>
    loadAndRememberAsset(context, LocalAssets.manual);

Future<void> _openOrgManual(BuildContext context) =>
    loadAndRememberUrl(context, Uri.parse(RemoteAssets.orgManual));

Future<void> _openTestFile(BuildContext context) =>
    loadAndRememberAsset(context, LocalAssets.testFile);

void _openSettingsScreen(BuildContext context) =>
    Navigator.pushNamed(context, Routes.settings);

class _SupportLink extends StatelessWidget {
  const _SupportLink();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: const Icon(Icons.help),
      label: Text(AppLocalizations.of(context)!.buttonSupport),
      onPressed: visitSupportLink,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).disabledColor,
      ),
    );
  }
}

class _VersionInfoButton extends StatelessWidget {
  const _VersionInfoButton();
  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: visitChangelogLink,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).disabledColor,
      ),
      child: Text(AppLocalizations.of(context)!.buttonVersion(orgroVersion)),
    );
  }
}
