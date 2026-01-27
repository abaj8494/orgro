import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:org_flutter/org_flutter.dart';
import 'package:orgro/src/pages/document/sibling_swipe.dart';
import 'package:orgro/src/transclusion/transclusion_directive.dart';
import 'package:orgro/src/transclusion/transclusion_widget.dart';

/// Custom OrgDocumentWidget that handles transclusion directives.
///
/// This widget wraps the standard OrgDocumentWidget rendering but intercepts
/// OrgMeta nodes that are transclusion directives and renders them with
/// our custom transclusion widget instead.
class TransclusionAwareDocumentWidget extends StatelessWidget {
  const TransclusionAwareDocumentWidget(
    this.document, {
    this.shrinkWrap = false,
    this.safeArea = true,
    super.key,
  });

  final OrgDocument document;
  final bool shrinkWrap;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final rootPadding = OrgTheme.dataOf(context).rootPadding;

    return ListView(
      restorationId: shrinkWrap
          ? null
          : OrgController.of(context).restorationIdFor('org_document_list_view'),
      padding: rootPadding,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: <Widget>[
        if (document.content != null) ..._contentWidgets(context),
        for (final (i, section) in document.sections.indexed)
          TransclusionAwareSectionWidget(
            section,
            siblingIndex: i,
          ),
        if (safeArea) _listBottomSafeArea(),
      ],
    );
  }

  Iterable<Widget> _contentWidgets(BuildContext context) sync* {
    final textDirection = OrgSettings.of(context).settings.textDirection;

    for (final child in document.content!.children) {
      // Check if this is a transclusion directive
      if (child is OrgMeta) {
        final directive = TransclusionDirective.tryParse(child);
        if (directive != null) {
          // Render as transclusion
          yield OrgTransclusionWidget(
            meta: child,
            directive: directive,
          );
          continue;
        }
      }

      // Default: render with OrgContentWidget
      Widget widget = OrgContentWidget(child);
      if (textDirection != null) {
        widget = Directionality(textDirection: textDirection, child: widget);
      }
      yield widget;
    }
  }

  Widget _listBottomSafeArea() {
    return SizedBox(
      height: MediaQueryData.fromView(
              WidgetsBinding.instance.platformDispatcher.views.first)
          .padding
          .bottom,
    );
  }
}

/// Custom OrgSectionWidget that handles transclusion directives within sections.
///
/// This mirrors the standard OrgSectionWidget but intercepts OrgMeta nodes
/// that are transclusion directives.
class TransclusionAwareSectionWidget extends StatelessWidget {
  const TransclusionAwareSectionWidget(
    this.section, {
    this.siblingIndex = 0,
    this.root = false,
    this.shrinkWrap = false,
    super.key,
  });

  final OrgSection section;
  final bool root;
  final bool shrinkWrap;
  final int siblingIndex;

  // Whether the section is open "enough" to not show the trailing ellipsis
  bool _openEnough(OrgVisibilityState visibility) {
    switch (visibility) {
      case OrgVisibilityState.folded:
        return section.isEmpty;
      case OrgVisibilityState.contents:
        return section.content == null;
      case OrgVisibilityState.children:
      case OrgVisibilityState.subtree:
        return true;
      case OrgVisibilityState.hidden:
        // Not meaningful
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibilityListenable =
        OrgController.of(context).nodeFor(section).visibility;
    Widget widget = ValueListenableBuilder<OrgVisibilityState>(
      valueListenable: visibilityListenable,
      builder: (context, visibility, child) => visibility ==
              OrgVisibilityState.hidden
          ? const SizedBox.shrink()
          : ListView(
              shrinkWrap: shrinkWrap || !root,
              physics: shrinkWrap || !root
                  ? const NeverScrollableScrollPhysics()
                  : null,
              padding:
                  root ? OrgTheme.dataOf(context).rootPadding : EdgeInsets.zero,
              children: <Widget>[
                InkWell(
                  onTap: () =>
                      OrgController.of(context).cycleVisibilityOf(section),
                  onLongPress: () =>
                      OrgEvents.of(context).onSectionLongPress?.call(section),
                  child: OrgHeadlineWidget(
                    section.headline,
                    open: _openEnough(visibility),
                    highlighted:
                        OrgController.of(context).sparseQuery?.matches(section),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 100),
                  transitionBuilder: (child, animation) =>
                      SizeTransition(sizeFactor: animation, child: child),
                  child: Column(
                    key: ValueKey(visibility),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (section.content != null &&
                          (visibility == OrgVisibilityState.children ||
                              visibility == OrgVisibilityState.subtree))
                        ..._contentWidgets(context),
                      if (visibility != OrgVisibilityState.folded)
                        for (final (i, subsection) in section.sections.indexed)
                          TransclusionAwareSectionWidget(
                            subsection,
                            siblingIndex: i,
                          ),
                    ],
                  ),
                ),
                if (root) _listBottomSafeArea(),
              ],
            ),
    );
    widget = _withSlideActions(context, widget);
    return widget;
  }

  Widget _listBottomSafeArea() {
    return SizedBox(
      height: MediaQueryData.fromView(
              WidgetsBinding.instance.platformDispatcher.views.first)
          .padding
          .bottom,
    );
  }

  Iterable<Widget> _contentWidgets(BuildContext context) sync* {
    final textDirection = OrgSettings.of(context).settings.textDirection;

    for (final child in section.content!.children) {
      // Check if this is a transclusion directive
      if (child is OrgMeta) {
        final directive = TransclusionDirective.tryParse(child);
        if (directive != null) {
          // Render as transclusion
          yield OrgTransclusionWidget(
            meta: child,
            directive: directive,
          );
          continue;
        }
      }

      // Default: render with OrgContentWidget
      Widget widget = OrgContentWidget(child);
      if (textDirection != null) {
        widget = Directionality(textDirection: textDirection, child: widget);
      }
      yield widget;
    }
  }

  Widget _withSlideActions(BuildContext context, Widget child) {
    final actions = OrgEvents.of(context).onSectionSlide?.call(section);
    if (actions == null) return child;
    return _SwipeTrackingSlidable(
      actions: actions,
      child: child,
    );
  }
}

/// A Slidable wrapper that resets swipe tracking when it opens.
///
/// This prevents accidental sibling navigation when the user repeatedly
/// opens/closes the TODO cycle slidable.
class _SwipeTrackingSlidable extends StatefulWidget {
  const _SwipeTrackingSlidable({
    required this.actions,
    required this.child,
  });

  final List<Widget> actions;
  final Widget child;

  @override
  State<_SwipeTrackingSlidable> createState() => _SwipeTrackingSlidableState();
}

class _SwipeTrackingSlidableState extends State<_SwipeTrackingSlidable>
    with SingleTickerProviderStateMixin {
  late final SlidableController _controller;
  bool _wasOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = SlidableController(this);
    _controller.animation.addListener(_onAnimationChanged);
  }

  @override
  void dispose() {
    _controller.animation.removeListener(_onAnimationChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onAnimationChanged() {
    final isOpen = _controller.ratio.abs() > 0.1;
    if (isOpen && !_wasOpen) {
      // Slidable is opening - reset swipe tracking to prevent
      // the next swipe from being treated as a "second swipe"
      SiblingSwipeDetector.resetTracking();
    }
    _wasOpen = isOpen;
  }

  @override
  Widget build(BuildContext context) {
    return Slidable(
      controller: _controller,
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: widget.actions,
      ),
      child: widget.child,
    );
  }
}
