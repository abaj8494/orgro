import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:org_flutter/org_flutter.dart';
import 'package:orgro/l10n/app_localizations.dart';
import 'package:orgro/src/actions/actions.dart';
import 'package:orgro/src/actions/geometry.dart';
import 'package:orgro/src/actions/wakelock.dart';
import 'package:orgro/src/assets.dart';
import 'package:orgro/src/components/banners.dart';
import 'package:orgro/src/components/dialogs.dart';
import 'package:orgro/src/components/document_provider.dart';
import 'package:orgro/src/components/fab.dart';
import 'package:orgro/src/components/scroll.dart';
import 'package:orgro/src/components/slidable_action.dart';
import 'package:orgro/src/components/view_settings.dart';
import 'package:orgro/src/data_source.dart';
import 'package:orgro/src/debug.dart';
import 'package:orgro/src/encryption.dart';
import 'package:orgro/src/file_picker.dart';
import 'package:orgro/src/navigation.dart';
import 'package:orgro/src/pages/document/agenda.dart';
import 'package:orgro/src/pages/document/citations.dart';
import 'package:orgro/src/pages/document/encryption.dart';
import 'package:orgro/src/pages/document/images.dart';
import 'package:orgro/src/pages/document/keyboard.dart';
import 'package:orgro/src/pages/document/links.dart';
import 'package:orgro/src/pages/document/narrow.dart';
import 'package:orgro/src/pages/document/reader_drawer.dart';
import 'package:orgro/src/pages/document/restoration.dart';
import 'package:orgro/src/pages/document/sibling_swipe.dart';
import 'package:orgro/src/pages/document/timestamps.dart';
import 'package:orgro/src/transclusion/transclusion.dart';
import 'package:orgro/src/native_directory.dart';
import 'package:orgro/src/preferences.dart';
import 'package:orgro/src/components/remembered_files.dart';
import 'package:orgro/src/error.dart';
import 'package:orgro/src/pages/pages.dart';
import 'package:orgro/src/routes/document.dart';
import 'package:orgro/src/routes/routes.dart';
import 'package:orgro/src/serialization.dart';
import 'package:orgro/src/statistics.dart';
import 'package:orgro/src/util.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

var _activeDocuments = 0;

const _kBigScreenDocumentPadding = EdgeInsets.all(16);

enum InitialMode { view, edit }

extension InitialModePersistence on InitialMode? {
  String? get persistableString => switch (this) {
    InitialMode.view => 'view',
    InitialMode.edit => 'edit',
    null => null,
  };

  static InitialMode? fromString(String? value) => switch (value) {
    'view' => InitialMode.view,
    'edit' => InitialMode.edit,
    _ => null,
  };
}

const _kDefaultInitialMode = InitialMode.view;

const kRestoreNarrowTargetKey = 'restore_narrow_target';
const kRestoreModeKey = 'restore_mode';
const kRestoreSearchQueryKey = 'restore_search_query_2';
const kRestoreSearchFilterKey = 'restore_search_filter';
const kRestoreDirtyDocumentKey = 'restore_dirty_document';

class DocumentPage extends StatefulWidget {
  const DocumentPage({
    required this.layer,
    required this.title,
    this.initialMode,
    this.initialTarget,
    this.initialQuery,
    this.initialFilter,
    this.afterOpen,
    required this.root,
    super.key,
  });

  final int layer;
  final String title;
  final String? initialTarget;
  final SearchQuery? initialQuery;
  final InitialMode? initialMode;
  final FilterData? initialFilter;
  final AfterOpenCallback? afterOpen;
  final bool root;

  @override
  State createState() => DocumentPageState();
}

class DocumentPageState extends State<DocumentPage> with RestorationMixin {
  @override
  String get restorationId => 'document_page_${widget.layer}';

  late MySearchDelegate searchDelegate;

  OrgTree get _doc => DocumentProvider.of(context).doc;
  DataSource get _dataSource => DocumentProvider.of(context).dataSource;

  InheritedViewSettings get _viewSettings => ViewSettings.of(context);

  double get _screenWidth => MediaQuery.sizeOf(context).width;

  // Not sure why this size
  bool get _biggishScreen => _screenWidth > 500;

  // E.g. iPad mini in portrait (768px), iPhone XS in landscape (812px), Pixel 2
  // in landscape (731px)
  bool get _bigScreen => _screenWidth > 600;

  // Sibling file navigation
  List<DirectoryEntry>? _siblingFiles;
  int _currentFileIndex = -1;
  bool _isDrawerOpen = false;

  bool get _canNavigatePrevious => _currentFileIndex > 0;
  bool get _canNavigateNext =>
      _siblingFiles != null && _currentFileIndex < _siblingFiles!.length - 1;

  @override
  void initState() {
    super.initState();
    _activeDocuments++;
    searchDelegate = MySearchDelegate(
      onQueryChanged: (query) {
        if (query.isEmpty || query.queryString.length > 3) {
          _doQuery(query);
        }
      },
      onQuerySubmitted: _doQuery,
      initialQuery: widget.initialQuery,
      initialFilter: widget.initialFilter,
      onFilterChanged: _doSearchFilter,
    );
    canObtainNativeDirectoryPermissions().then(
      (value) => setState(() => canResolveRelativeLinks = value),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSiblingFiles();
      // Restore saved visibility state before handling initial target
      _restoreVisibilityState();
      handleInitialTarget(widget.initialTarget);
      ensureOpenOnNarrow();
      if (widget.initialTarget == null) {
        switch (widget.initialMode ?? _kDefaultInitialMode) {
          case InitialMode.view:
            widget.afterOpen?.call(this);
            break;
          case InitialMode.edit:
            doEdit(requestFocus: true);
            break;
        }
      }
    });
  }

  @override
  void deactivate() {
    debugPrint('>>> DocumentPageState.deactivate() CALLED');
    // Save visibility state before the widget is removed from the tree
    // Using deactivate() instead of dispose() because context is still valid here
    _saveVisibilityState();
    super.deactivate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final analysis = DocumentProvider.of(context).analysis;
    searchDelegate.keywords = analysis.keywords ?? [];
    searchDelegate.tags = analysis.tags ?? [];
    searchDelegate.priorities = analysis.priorities ?? [];
    searchDelegate.todoSettings = OrgSettings.of(context).settings.todoSettings;
    if (analysis.loaded && isAgendaFile) {
      // The same file's persistent identifier may change; re-add to overwrite
      // stale entry.
      setAgendaFile();
      setNotifications();
    }
    WakelockPlus.toggle(enable: _viewSettings.wakelock).onError((e, s) {
      logError(e, s);
      if (mounted) showErrorSnackBar(context, e);
    });
  }

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restoreDoc = restoreDocument();
      restoreSearchState();

      if (!initialRestore) return;

      // Wait for doc to finish restoring before opening narrow target
      await restoreDoc;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = bucket!.read<String>(kRestoreNarrowTargetKey);
        if (widget.initialTarget == null) {
          handleInitialTarget(target);
        }
        if (widget.initialMode == null && target == null) {
          restoreMode();
        }
      });
    });
  }

  void _onSectionLongPress(OrgSection section) async => doNarrow(section);

  List<Widget> _onSectionSlide(OrgSection section) {
    return [
      PrimaryScrollController(
        controller: PrimaryScrollController.of(context),
        child: ResponsiveSlidableAction(
          label: '', // Icon only for cleaner look
          icon: Icons.repeat,
          onPressed: () {
            final todoSettings = OrgSettings.of(context).settings.todoSettings;
            try {
              final replacement = section.cycleTodo(todoStates: todoSettings);
              var newDoc =
                  _doc.editNode(section)!.replace(replacement).commit()
                      as OrgTree;
              newDoc = recalculateHeadlineStats(newDoc, replacement.headline);
              updateDocument(newDoc);
            } catch (e, s) {
              logError(e, s);
              // TODO(aaron): Make this more friendly?
              showErrorSnackBar(context, e);
            }
          },
        ),
      ),
    ];
  }

  void _doQuery(SearchQuery query) {
    if (query.isEmpty) {
      bucket!.remove<void>(kRestoreSearchQueryKey);
    } else {
      bucket!.write(kRestoreSearchQueryKey, query.toJson());
    }
    _viewSettings.searchQuery = query;
  }

  void _doSearchFilter(FilterData filterData) {
    if (filterData.isEmpty) {
      bucket!.remove<void>(kRestoreSearchFilterKey);
    } else {
      bucket!.write(kRestoreSearchFilterKey, filterData.toJson());
    }
    _viewSettings.filterData = filterData;
  }

  @override
  void dispose() {
    searchDelegate.dispose();
    _dirty.dispose();
    if (--_activeDocuments == 0) {
      debugPrint('Disabling wakelock as no active documents remain');
      WakelockPlus.disable().onError(logError);
    }
    super.dispose();
  }

  /// Convert OrgVisibilityState to string for storage
  String _visibilityToString(OrgVisibilityState state) => state.name;

  /// Convert string back to OrgVisibilityState
  OrgVisibilityState? _visibilityFromString(String? value) {
    if (value == null) return null;
    return OrgVisibilityState.values
        .cast<OrgVisibilityState?>()
        .firstWhere((s) => s?.name == value, orElse: () => null);
  }

  /// Save the current visibility state of all sections to preferences
  void _saveVisibilityState() {
    debugPrint('>>> _saveVisibilityState() CALLED');
    try {
      final controller = OrgController.of(context);
      final doc = _doc;
      final visibility = <String, String>{};

      doc.visitSections((section) {
        final title = section.headline.rawTitle;
        if (title != null && title.isNotEmpty) {
          final state = controller.nodeFor(section).visibility.value;
          visibility[title] = _visibilityToString(state);
          debugPrint('  Section "$title" -> ${state.name}');
        }
        return true;
      });

      if (visibility.isNotEmpty) {
        final scopeKey = _dataSource.id;
        debugPrint('>>> Saving ${visibility.length} sections to key: $scopeKey');
        debugPrint('>>> Visibility map: $visibility');
        _viewSettings.setVisibilityState(scopeKey, visibility);
        debugPrint('>>> Save completed');
      } else {
        debugPrint('>>> No sections to save');
      }
    } catch (e, s) {
      debugPrint('>>> _saveVisibilityState ERROR: $e');
      logError(e, s);
    }
  }

  /// Restore saved visibility state for all sections
  void _restoreVisibilityState() {
    debugPrint('>>> _restoreVisibilityState() CALLED');
    try {
      final scopeKey = _dataSource.id;
      debugPrint('>>> Looking for saved state with key: $scopeKey');
      final savedVisibility = _viewSettings.getVisibilityState(scopeKey);
      if (savedVisibility == null || savedVisibility.isEmpty) {
        debugPrint('>>> No saved visibility state found (null or empty)');
        return;
      }

      debugPrint('>>> Found saved visibility: $savedVisibility');

      // Delay the actual restoration to avoid conflicts with OrgController's
      // own restoration mechanism. OrgController uses Flutter's RestorationMixin
      // which can be updating during route transitions. We need to wait until
      // the restoration phase is completely finished.
      _scheduleVisibilityRestore(savedVisibility);
    } catch (e, s) {
      debugPrint('>>> _restoreVisibilityState ERROR: $e');
      logError(e, s);
    }
  }

  /// Schedule visibility restore using idle task to avoid restoration conflicts
  void _scheduleVisibilityRestore(Map<String, String> savedVisibility, [int attempt = 0]) {
    if (!mounted || attempt > 5) {
      if (attempt > 5) {
        debugPrint('>>> Gave up restoring visibility after $attempt attempts');
      }
      return;
    }

    // Use scheduleTask with idle priority to run after restoration is complete
    // This ensures we don't interfere with OrgController's own restoration
    SchedulerBinding.instance.scheduleTask(() {
      if (!mounted) return;

      // Additional delay to ensure we're past any restoration phase
      Future.delayed(Duration(milliseconds: 50 + (attempt * 100)), () {
        if (!mounted) return;
        debugPrint('>>> Attempting visibility restore (attempt ${attempt + 1})');
        final success = _applyVisibilityState(savedVisibility);
        if (!success && attempt < 5) {
          debugPrint('>>> Visibility restore failed, scheduling retry ${attempt + 1}');
          _scheduleVisibilityRestore(savedVisibility, attempt + 1);
        }
      });
    }, Priority.idle);
  }

  /// Apply saved visibility state to sections, returns true if successful
  bool _applyVisibilityState(Map<String, String> savedVisibility) {
    try {
      final controller = OrgController.of(context);
      final doc = _doc;
      var restored = 0;

      doc.visitSections((section) {
        final title = section.headline.rawTitle;
        if (title != null && savedVisibility.containsKey(title)) {
          final stateString = savedVisibility[title];
          final state = _visibilityFromString(stateString);
          if (state != null) {
            debugPrint('>>> Restoring "$title" to ${state.name}');
            controller.setVisibilityOf(section, (_) => state);
            restored++;
          }
        }
        return true;
      });

      debugPrint('>>> Restored visibility state for $restored sections');
      return true;
    } catch (e, s) {
      debugPrint('>>> _applyVisibilityState ERROR: $e');
      // Don't log as fatal error - this is expected during restoration conflicts
      return false;
    }
  }

  Widget _title(bool searchMode) {
    if (searchMode) {
      return searchDelegate.buildSearchField();
    } else {
      return Text(widget.title, overflow: TextOverflow.fade);
    }
  }

  Iterable<Widget> _actions(bool searchMode) sync* {
    final viewSettings = _viewSettings;
    final scopeKey = _dataSource.id;
    final scopedViewSettings = viewSettings.forScope(scopeKey);
    if (!searchMode || _biggishScreen) {
      // Star toggle button
      final rememberedFiles = RememberedFiles.of(context);
      final currentFile = rememberedFiles.list
          .where((f) => f.name == widget.title)
          .firstOrNull;
      final isStarred = currentFile?.isStarred ?? false;
      yield IconButton(
        tooltip: isStarred ? 'Unstar file' : 'Star file',
        icon: Icon(isStarred ? Icons.star : Icons.star_border),
        onPressed: currentFile != null
            ? () {
                if (isStarred) {
                  rememberedFiles.unstar(currentFile);
                } else {
                  rememberedFiles.star(currentFile);
                }
              }
            : null,
      );
      yield IconButton(
        tooltip: AppLocalizations.of(context)!.tooltipCycleVisibility,
        icon: const Icon(Icons.repeat),
        onPressed: () => OrgController.of(
          context,
        ).cycleVisibility(skip: OrgVisibilityState.subtree),
        onLongPress: () => OrgController.of(
          context,
        ).cycleVisibility(to: OrgVisibilityState.subtree),
      );
      if (_bigScreen) {
        yield TextStyleButton(
          textScale: scopedViewSettings.textScale,
          onTextScaleChanged: (value) =>
              viewSettings.setTextScale(scopeKey, value),
          fontFamily: scopedViewSettings.fontFamily,
          onFontFamilyChanged: (value) =>
              viewSettings.setFontFamily(scopeKey, value),
        );
        yield ReaderModeButton(
          enabled: scopedViewSettings.readerMode,
          onChanged: (value) => viewSettings.readerMode = value,
        );
        if (_allowFullScreen(context)) {
          yield FullWidthButton(
            enabled: scopedViewSettings.fullWidth,
            onChanged: (value) => viewSettings.fullWidth = value,
          );
        }
        yield const ScrollTopButton();
        yield const ScrollBottomButton();
      } else {
        yield PopupMenuButton<VoidCallback>(
          onSelected: (callback) => callback(),
          itemBuilder: (context) => [
            undoMenuItem(context, onChanged: _undo),
            redoMenuItem(context, onChanged: _redo),
            const PopupMenuDivider(),
            textScaleMenuItem(
              context,
              textScale: scopedViewSettings.textScale,
              onChanged: (value) => viewSettings.setTextScale(scopeKey, value),
            ),
            fontFamilyMenuItem(
              context,
              fontFamily: scopedViewSettings.fontFamily,
              onChanged: (value) => viewSettings.setFontFamily(scopeKey, value),
            ),
            const PopupMenuDivider(),
            readerModeMenuItem(
              context,
              enabled: scopedViewSettings.readerMode,
              onChanged: (value) => viewSettings.readerMode = value,
            ),
            wakelockMenuItem(
              context,
              enabled: scopedViewSettings.wakelock,
              onChanged: (value) => viewSettings.wakelock = value,
            ),
            if (_allowFullScreen(context))
              fullWidthMenuItem(
                context,
                enabled: scopedViewSettings.fullWidth,
                onChanged: (value) => viewSettings.fullWidth = value,
              ),
            const PopupMenuDivider(),
            // Disused because icon button is always visible now
            // PopupMenuItem<VoidCallback>(
            //   child: const Text('Cycle visibility'),
            //   value: OrgController.of(context).cycleVisibility,
            // ),
            scrollTopMenuItem(context),
            scrollBottomMenuItem(context),
          ],
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: searchDelegate.searchMode,
      builder: (context, searchMode, _) => ValueListenableBuilder<bool>(
        valueListenable: _dirty,
        builder: (context, dirty, _) {
          return PopScope(
            canPop:
                searchMode || !dirty || _doc is! OrgDocument || !widget.root,
            onPopInvokedWithResult: _onPopInvoked,
            child: KeyboardShortcuts(
              onEdit: doEdit,
              onUndo: _undo,
              onRedo: _redo,
              searchDelegate: searchDelegate,
              child: Scaffold(
                // Disable drawer edge drag - use custom left edge swipe
                drawerEdgeDragWidth: 0,
                onDrawerChanged: (isOpened) {
                  setState(() => _isDrawerOpen = isOpened);
                },
                drawer: ReaderDrawer(
                  dataSource: _dataSource,
                  currentFileName: widget.title,
                ),
                body: Builder(
                  builder: (scaffoldContext) => SiblingSwipeDetector(
                    enabled: !_isDrawerOpen,
                    canSwipeLeft: _canNavigateNext,
                    canSwipeRight: _canNavigatePrevious,
                    onSwipeLeft: () => _navigateToSibling(1),
                    onSwipeRight: () => _navigateToSibling(-1),
                    onOpenDrawer: () =>
                        Scaffold.of(scaffoldContext).openDrawer(),
                    onAtStart: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Already at first file'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    onAtEnd: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Already at last file'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: CustomScrollView(
                      restorationId: 'document_scroll_view_${widget.layer}',
                      slivers: [
                        _buildAppBar(context, searchMode: searchMode),
                        _buildDocument(context),
                      ],
                    ),
                  ),
                ),
                // Builder is here to ensure that the Scaffold makes it into the
                // body's context
                floatingActionButton: Builder(
                  builder: (context) => _buildFloatingActionButton(
                    context,
                    searchMode: searchMode,
                  ),
                ),
                bottomSheet: searchMode
                    ? searchDelegate.buildBottomSheet(context)
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, {required bool searchMode}) {
    return PrimaryScrollController(
      // Context of app bar(?) lacks access to the primary scroll controller, so
      // we supply it explicitly from parent context
      controller: PrimaryScrollController.of(context),
      child: SliverAppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menu',
            // Ensure large touch target
            iconSize: 24,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          ),
        ),
        title: _title(searchMode),
        actions: _actions(searchMode).toList(growable: false),
        pinned: searchMode,
        floating: true,
        forceElevated: true,
        snap: true,
      ),
    );
  }

  Widget _buildDocument(BuildContext context) {
    final viewSettings = _viewSettings;
    final docProvider = DocumentProvider.of(context);
    final doc = docProvider.doc;
    final analysis = docProvider.analysis;
    final result = SliverList(
      delegate: SliverChildListDelegate([
        DirectoryPermissionsBanner(
          visible: _askForDirectoryPermissions,
          onDismiss: () => viewSettings.setLocalLinksPolicy(
            LocalLinksPolicy.deny,
            persist: false,
          ),
          onForbid: () => viewSettings.setLocalLinksPolicy(
            LocalLinksPolicy.deny,
            persist: true,
          ),
          onAllow: doPickDirectory,
        ),
        RemoteImagePermissionsBanner(
          visible: _askPermissionToLoadRemoteImages,
          onResult: viewSettings.setRemoteImagesPolicy,
        ),
        SavePermissionsBanner(
          visible: _askPermissionToSaveChanges,
          onResult: (value, {required bool persist}) {
            viewSettings.setSaveChangesPolicy(value, persist: persist);
            if (_dirty.value) _onDocChanged(doc, analysis);
          },
        ),
        DecryptContentBanner(
          visible: _askToDecrypt,
          onAccept: decryptContent,
          onDeny: viewSettings.setDecryptPolicy,
        ),
        AgendaNotificationsBanner(
          visible: _askAboutAgendaNotifications,
          onAccept: enableNotifications,
          onDeny: viewSettings.setAgendaNotificationsPolicy,
        ),
        _maybeConstrainWidth(
          context,
          child: SelectionArea(
            child: OrgRootWidget(
              style: viewSettings.forScope(_dataSource.id).textStyle,
              onLinkTap: openLink,
              onSectionLongPress: _onSectionLongPress,
              onSectionSlide: _onSectionSlide,
              onLocalSectionLinkTap: doNarrow,
              onListItemTap: _onListItemTap,
              onCitationTap: openCitation,
              onTimestampTap: onTimestampTap,
              loadImage: loadImage,
              child: switch (doc) {
                OrgDocument() => TransclusionAwareDocumentWidget(doc, shrinkWrap: true),
                OrgSection() => OrgSectionWidget(
                  doc,
                  root: true,
                  shrinkWrap: true,
                ),
                _ => throw Exception('Unexpected document type: $doc'),
              },
            ),
          ),
        ),
        // Bottom padding to compensate for Floating Action Button:
        // FAB height (56px) + padding (16px) = 72px
        //
        // TODO(aaron): Include edit FAB?
        const SizedBox(height: 72),
      ]),
    );

    return _maybePadForBigScreen(result);
  }

  // Add some extra padding on big screens to make things not feel so
  // tight. We can do this instead of adjusting the [OrgTheme.rootPadding]
  // because we are shrinkwapping the document
  Widget _maybePadForBigScreen(Widget child) => _bigScreen
      ? SliverPadding(padding: _kBigScreenDocumentPadding, sliver: child)
      : child;

  Widget _maybeConstrainWidth(BuildContext context, {required Widget child}) {
    if (_viewSettings.fullWidth || !_bigScreen || !_allowFullScreen(context)) {
      return child;
    }
    final inset =
        (_screenWidth -
            _maxRecommendedWidth(context) -
            _kBigScreenDocumentPadding.left) /
        2;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: child,
    );
  }

  bool _allowFullScreen(BuildContext context) =>
      _maxRecommendedWidth(context) +
          _kBigScreenDocumentPadding.left +
          _kBigScreenDocumentPadding.right +
          // org_flutter default theme has 8px padding on left + right
          // TODO(aaron): make this publically accessible
          16 <
      _screenWidth;

  // Calculate the maximum document width as 72 of the character 'M' with the
  // user's preferred font size and family
  double _maxRecommendedWidth(BuildContext context) {
    final mBox = renderedBounds(
      context,
      const BoxConstraints(),
      Text.rich(const TextSpan(text: 'M'), style: _viewSettings.textStyle),
    );
    return 72 * mBox.toRect().width;
  }

  Widget _buildFloatingActionButton(
    BuildContext context, {
    required bool searchMode,
  }) => searchMode
      ? searchDelegate.buildSearchResultsNavigation()
      : ScrollingBuilder(
          builder: (context, scrolling) => Column(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 16,
            children: [
              FloatingActionButton(
                tooltip: AppLocalizations.of(context)!.tooltipEditDocument,
                onPressed: () {
                  if (scrolling) return;
                  doEdit();
                },
                heroTag: '${widget.title}EditFAB',
                mini: true,
                child: const Icon(Icons.edit),
              ),
              BadgableFloatingActionButton(
                tooltip: AppLocalizations.of(context)!.tooltipSearchDocument,
                badgeVisible: searchDelegate.hasQuery,
                onPressed: () {
                  if (scrolling) return;
                  searchDelegate.start(context);
                },
                heroTag: '${widget.title}FAB',
                child: const Icon(Icons.search),
              ),
            ],
          ),
        );

  Future<void> doEdit({bool requestFocus = false}) async {
    final controller = OrgController.of(context);
    bucket!.write(kRestoreModeKey, InitialMode.edit.persistableString);
    final newDoc = await showTextEditor(
      context,
      _dataSource,
      _doc,
      requestFocus: requestFocus,
      layer: widget.layer,
    );
    bucket!.remove<String>(kRestoreModeKey);
    if (newDoc != null) {
      controller.adaptVisibility(
        newDoc,
        defaultState: OrgVisibilityState.children,
      );
      await updateDocument(newDoc);
    }
  }

  bool? get _hasRelativeLinks =>
      DocumentProvider.of(context).analysis.hasRelativeLinks;

  // Android 4.4 and earlier doesn't have APIs to get directory info
  bool? canResolveRelativeLinks;

  bool get _askForDirectoryPermissions =>
      _viewSettings.localLinksPolicy == LocalLinksPolicy.ask &&
      _hasRelativeLinks == true &&
      canResolveRelativeLinks == true &&
      _dataSource.needsToResolveParent;

  void _showMissingEncryptionKeySnackBar(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.snackbarMessageNeedsEncryptionKey,
          ),
          action: SnackBarAction(
            label: AppLocalizations.of(
              context,
            )!.snackbarActionEnterEncryptionKey.toUpperCase(),
            onPressed: () async {
              final password = await showDialog<String>(
                context: context,
                builder: (context) => InputPasswordDialog(
                  title: AppLocalizations.of(
                    context,
                  )!.inputEncryptionPasswordDialogTitle,
                ),
              );
              if (password == null || !context.mounted) return;
              final docProvider = DocumentProvider.of(context);
              final passwords = docProvider.addPasswords([
                (password: password, predicate: (_) => true),
              ]);
              if (_dirty.value) {
                _onDocChanged(docProvider.doc, docProvider.analysis, passwords);
              }
            },
          ),
        ),
      );

  void _onListItemTap(OrgListItem item) {
    final replacement = item.toggleCheckbox();
    var newTree = _doc.editNode(item)!.replace(replacement).commit<OrgTree>();
    newTree = recalculateListStats(newTree, replacement);
    updateDocument(newTree);
  }

  bool? get _hasRemoteImages =>
      DocumentProvider.of(context).analysis.hasRemoteImages;

  bool get _askPermissionToLoadRemoteImages =>
      _viewSettings.remoteImagesPolicy == RemoteImagesPolicy.ask &&
      _hasRemoteImages == true &&
      !_askForDirectoryPermissions;

  bool get _askPermissionToSaveChanges =>
      _viewSettings.saveChangesPolicy == SaveChangesPolicy.ask &&
      _canSaveChanges &&
      !_askForDirectoryPermissions &&
      !_askPermissionToLoadRemoteImages;

  bool get _canSaveChanges =>
      _dataSource is NativeDataSource && _doc is OrgDocument && widget.root;

  Timer? _writeTimer;
  Future<void>? _writeFuture;

  final ValueNotifier<bool> _dirty = ValueNotifier(false);

  Future<bool> updateDocument(OrgTree newDoc, {bool dirty = true}) async {
    final (pushed, analysis) = await DocumentProvider.of(
      context,
    ).pushDoc(newDoc);
    if (pushed && dirty) {
      await _onDocChanged(newDoc, analysis);
    }
    return pushed;
  }

  Future<void> _undo() async {
    final (doc, analysis) = DocumentProvider.of(context).undo();
    await _onDocChanged(doc, analysis);
  }

  Future<void> _redo() async {
    final (doc, analysis) = DocumentProvider.of(context).redo();
    await _onDocChanged(doc, analysis);
  }

  Future<void> _onDocChanged(
    OrgTree doc,
    DocumentAnalysis analysis, [
    List<OrgroPassword>? passwords,
  ]) async {
    _dirty.value = true;
    final docProvider = DocumentProvider.of(context);
    final source = docProvider.dataSource;
    passwords ??= docProvider.passwords;
    if (analysis.needsEncryption == true &&
        doc.missingEncryptionKey(passwords)) {
      _showMissingEncryptionKeySnackBar(context);
      return;
    }
    final doWrite =
        _viewSettings.saveChangesPolicy == SaveChangesPolicy.allow &&
        _canSaveChanges &&
        source is NativeDataSource &&
        doc is OrgDocument;
    _writeTimer?.cancel();
    _writeTimer = Timer(const Duration(seconds: 3), () {
      _writeFuture = time('save', () async {
        try {
          debugPrint('starting auto save');
          final serializer = OrgroSerializer.get(analysis, passwords!);
          final markup = await serialize(doc, serializer);
          try {
            // Because of the timer delay this can be called when the bucket is
            // not available, so we conditionally access the bucket.
            //
            // "Some platforms restrict the size of the restoration data", and
            // the markup is potentially large, thus the try-catch. See:
            // https://api.flutter.dev/flutter/services/RestorationManager-class.html
            bucket?.write(kRestoreDirtyDocumentKey, markup);
          } catch (e, s) {
            logError(e, s);
          }
          if (doWrite) {
            await time('write', () => source.write(markup));
            if (mounted) {
              showErrorSnackBar(
                context,
                AppLocalizations.of(context)!.savedMessage,
              );
            }
            bucket?.remove<String>(kRestoreDirtyDocumentKey);
            _dirty.value = false;
          }
        } on Exception catch (e, s) {
          logError(e, s);
          if (mounted) showErrorSnackBar(context, e);
        }
      }).whenComplete(() => _writeFuture = null);
    });
  }

  Future<void> _onPopInvoked(bool didPop, dynamic result) async {
    if (didPop) return;

    assert(_dirty.value);

    final doc = _doc;
    // Don't try to save anything other than a root document
    if (doc is! OrgDocument || !widget.root) return;

    // Grab the route now when we're sure it's on top, so we don't accidentally
    // pop the wrong one later.
    final navigator = Navigator.of(context);
    final docRoute = ModalRoute.of(context)!;
    void pop() {
      if (!mounted) return;
      navigator.removeRoute(docRoute);
    }

    // If we are already in the middle of saving, wait for that to finish
    final writeFuture = _writeFuture;
    if (writeFuture != null) {
      debugPrint('waiting for autosave to finish');
      await progressTask(
        context,
        dialogTitle: AppLocalizations.of(context)!.savingProgressDialogTitle,
        task: writeFuture,
      );
      if (!_dirty.value) return;
    }

    if (!mounted) return;

    // Save now, if possible
    final viewSettings = _viewSettings;
    var saveChangesPolicy = viewSettings.saveChangesPolicy;
    final source = _dataSource;
    if (viewSettings.saveChangesPolicy == SaveChangesPolicy.ask &&
        _canSaveChanges) {
      final result = await showDialog<(SaveChangesPolicy, bool)>(
        context: context,
        builder: (context) => const SavePermissionDialog(),
      );
      if (result == null) {
        return;
      } else {
        final (newPolicy, persist) = result;
        saveChangesPolicy = newPolicy;
        viewSettings.setSaveChangesPolicy(newPolicy, persist: persist);
      }
    }

    if (!mounted) return;

    final docProvider = DocumentProvider.of(context);
    var passwords = docProvider.passwords;
    if (docProvider.analysis.needsEncryption == true &&
        doc.missingEncryptionKey(passwords)) {
      final password = await showDialog<String>(
        context: context,
        builder: (context) => InputPasswordDialog(
          title: AppLocalizations.of(
            context,
          )!.inputEncryptionPasswordDialogTitle,
          bodyText: AppLocalizations.of(
            context,
          )!.inputEncryptionPasswordDialogBody,
        ),
      );
      if (!mounted) return;
      if (password == null) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => const DiscardChangesDialog(),
        );
        if (discard == true) {
          pop();
        }
        return;
      } else {
        passwords = docProvider.addPasswords([
          (password: password, predicate: (_) => true),
        ]);
      }
    }

    if (!mounted) return;

    final serializer = OrgroSerializer.get(docProvider.analysis, passwords);

    if (saveChangesPolicy == SaveChangesPolicy.allow &&
        _canSaveChanges &&
        source is NativeDataSource) {
      debugPrint('synchronously saving now');
      _writeTimer?.cancel();
      final markup = await serializeWithProgressUI(context, doc, serializer);
      if (markup == null) return;
      await time('write', () => source.write(markup));
      pop();
      return;
    }

    final isScratchDocument =
        source is AssetDataSource && source.key == LocalAssets.scratch;

    // Prompt to save or share
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => SaveChangesDialog(
        doc: doc,
        serializer: serializer,
        message: isScratchDocument
            ? null
            : AppLocalizations.of(context)!.saveChangesDialogMessage,
      ),
    );

    if (result == true) pop();
  }

  bool? get _hasEncryptedContent =>
      DocumentProvider.of(context).analysis.hasEncryptedContent;

  bool get _askToDecrypt =>
      _viewSettings.decryptPolicy == DecryptPolicy.ask &&
      _hasEncryptedContent == true &&
      !_askForDirectoryPermissions &&
      !_askPermissionToLoadRemoteImages &&
      !_askPermissionToSaveChanges;

  bool? get _hasAgendaEntries =>
      DocumentProvider.of(context).analysis.hasAgendaEntries;

  bool get _askAboutAgendaNotifications =>
      _viewSettings.agendaNotificationsPolicy ==
          AgendaNotificationsPolicy.ask &&
      canBeAgendaFile &&
      !isAgendaFile &&
      _hasAgendaEntries == true &&
      !_askForDirectoryPermissions &&
      !_askPermissionToLoadRemoteImages &&
      !_askPermissionToSaveChanges &&
      !_askToDecrypt;

  Future<void> _loadSiblingFiles() async {
    final source = _dataSource;
    debugPrint('_loadSiblingFiles: source type=${source.runtimeType}');
    if (source is! NativeDataSource) {
      debugPrint('_loadSiblingFiles: cannot load - not NativeDataSource');
      return;
    }

    debugPrint('_loadSiblingFiles: parentDirIdentifier=${source.parentDirIdentifier}');
    debugPrint('_loadSiblingFiles: rootDirIdentifier=${source.rootDirIdentifier}');

    // Try to get parent directory - use stored value or try to derive it
    String? parentDir = source.parentDirIdentifier;
    String? rootDir = source.rootDirIdentifier;

    // If no parent dir, try to get it from configured folder
    if (parentDir == null) {
      final prefs = Preferences.of(context, PrefsAspect.configuredFolder);
      final configuredRoot = prefs.configuredFolderIdentifier;
      debugPrint('_loadSiblingFiles: trying configured folder: $configuredRoot');

      if (configuredRoot != null) {
        // Try to find the file in the configured folder and determine its parent
        parentDir = await _findParentDirectory(source.identifier, configuredRoot);
        rootDir = configuredRoot;
        debugPrint('_loadSiblingFiles: derived parentDir=$parentDir');
      }
    }

    if (parentDir == null) {
      debugPrint('_loadSiblingFiles: cannot load - no parent dir available');
      return;
    }

    try {
      final entries = await listDirectory(parentDir);
      final orgFiles = entries.where((e) => e.isOrgFile).toList();
      final currentIndex = orgFiles.indexWhere(
        (e) => e.name == widget.title,
      );
      debugPrint('_loadSiblingFiles: found ${orgFiles.length} siblings, current index=$currentIndex');
      if (mounted) {
        setState(() {
          _siblingFiles = orgFiles;
          _currentFileIndex = currentIndex;
          // Store the derived parent/root for sibling navigation
          _derivedParentDir = parentDir;
          _derivedRootDir = rootDir;
        });
      }
    } catch (e) {
      debugPrint('Failed to load sibling files: $e');
    }
  }

  String? _derivedParentDir;
  String? _derivedRootDir;

  /// Try to find the parent directory of a file by searching the configured folder tree
  Future<String?> _findParentDirectory(String fileIdentifier, String rootDir) async {
    try {
      // Search recursively to find the file and its parent
      return await _searchForFileParent(fileIdentifier, rootDir, widget.title);
    } catch (e) {
      debugPrint('_findParentDirectory failed: $e');
      return null;
    }
  }

  Future<String?> _searchForFileParent(String fileIdentifier, String dirIdentifier, String fileName) async {
    try {
      final entries = await listDirectory(dirIdentifier);

      // Check if the file is in this directory
      for (final entry in entries) {
        if (!entry.isDirectory && entry.name == fileName) {
          // Found the file - this directory is the parent
          return dirIdentifier;
        }
      }

      // Search subdirectories
      for (final entry in entries) {
        if (entry.isDirectory) {
          final result = await _searchForFileParent(fileIdentifier, entry.identifier, fileName);
          if (result != null) {
            return result;
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('_searchForFileParent error in $dirIdentifier: $e');
      return null;
    }
  }

  Future<void> _navigateToSibling(int direction) async {
    if (_siblingFiles == null) return;
    final newIndex = _currentFileIndex + direction;
    if (newIndex < 0 || newIndex >= _siblingFiles!.length) return;

    // Save visibility state BEFORE navigating so the next document can restore
    debugPrint('>>> Saving visibility before sibling navigation');
    _saveVisibilityState();

    final entry = _siblingFiles![newIndex];
    final source = _dataSource;
    // Use stored or derived parent/root directories
    final parentId = (source is NativeDataSource ? source.parentDirIdentifier : null) ?? _derivedParentDir;
    final rootId = (source is NativeDataSource ? source.rootDirIdentifier : null) ?? _derivedRootDir;

    // Load the sibling file data
    final dataSource = await readFileWithIdentifier(
      entry.identifier,
      parentDirIdentifier: parentId,
      rootDirIdentifier: rootId,
    );

    if (!mounted) return;

    // Remember the file
    final rememberedFiles = RememberedFiles.of(context);
    if (dataSource.persistable) {
      final loadedFile = RememberedFile(
        identifier: dataSource.identifier,
        name: dataSource.name,
        uri: dataSource.uri,
        lastOpened: DateTime.now(),
        parentDirIdentifier: dataSource.parentDirIdentifier,
        rootDirIdentifier: dataSource.rootDirIdentifier,
      );
      rememberedFiles.add([loadedFile]);
    }

    // Use push (not pushReplacement) so back button returns to previous document
    // direction > 0 means next (slide from right), direction < 0 means previous (slide from left)
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        settings: RouteSettings(
          name: Routes.document,
          arguments: DocumentRouteArgs(dataSource: dataSource),
        ),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const _DocumentRouteTop();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Slide from right for next (direction > 0), from left for previous (direction < 0)
          final begin = Offset(direction > 0 ? 1.0 : -1.0, 0.0);
          const end = Offset.zero;
          final tween = Tween(begin: begin, end: end);
          final offsetAnimation = animation.drive(tween);
          return SlideTransition(position: offsetAnimation, child: child);
        },
      ),
    );
  }
}

// Re-export _DocumentRouteTop for sibling navigation
class _DocumentRouteTop extends StatefulWidget {
  const _DocumentRouteTop();

  @override
  State<_DocumentRouteTop> createState() => _DocumentRouteTopState();
}

class _DocumentRouteTopState extends State<_DocumentRouteTop> {
  bool _inited = false;
  late DocumentRouteArgs _args;
  late Future<ParsedOrgFileInfo?> _parsed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_inited) {
      setState(() {
        _inited = true;
        _args = ModalRoute.of(context)!.settings.arguments as DocumentRouteArgs;
        _parsed = ParsedOrgFileInfo.from(_args.dataSource);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ParsedOrgFileInfo?>(
      future: _parsed,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return DocumentProvider(
            dataSource: snapshot.data!.dataSource,
            doc: snapshot.data!.doc,
            child: _DocumentPageWrapper(
              layer: 0,
              target: _args.target,
              initialMode: _args.mode,
              afterOpen: _args.afterOpen,
            ),
          );
        } else if (snapshot.hasError) {
          return ErrorPage(error: snapshot.error.toString());
        } else {
          return const ProgressPage();
        }
      },
    );
  }
}

class _DocumentPageWrapper extends StatelessWidget {
  const _DocumentPageWrapper({
    required this.layer,
    required this.target,
    required this.afterOpen,
    this.initialMode,
  });

  final int layer;
  final String? target;
  final InitialMode? initialMode;
  final AfterOpenCallback? afterOpen;

  @override
  Widget build(BuildContext context) {
    final docProvider = DocumentProvider.of(context);
    final dataSource = docProvider.dataSource;
    return RootRestorationScope(
      restorationId: 'org_page_root:${dataSource.id}',
      child: ViewSettings.defaults(
        context,
        child: Builder(
          builder: (context) {
            final viewSettings = ViewSettings.of(context);
            return OrgController(
              root: docProvider.doc,
              settings: viewSettings.readerMode
                  ? OrgSettings.hideMarkup
                  : const OrgSettings(),
              interpretEmbeddedSettings: true,
              searchQuery: viewSettings.searchQuery.asPattern(),
              sparseQuery: viewSettings.filterData.asSparseQuery(),
              errorHandler: (e) => WidgetsBinding.instance.addPostFrameCallback(
                (_) => showErrorSnackBar(context, OrgroError.from(e)),
              ),
              restorationId: 'org_page:${dataSource.id}',
              child: OrgLocator(
                child: DocumentPage(
                  layer: layer,
                  title: dataSource.name,
                  initialTarget: target,
                  initialMode: initialMode,
                  afterOpen: afterOpen,
                  root: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
