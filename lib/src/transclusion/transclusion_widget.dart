import 'package:flutter/material.dart';
import 'package:org_flutter/org_flutter.dart';
import 'package:orgro/src/components/document_provider.dart';
import 'package:orgro/src/navigation.dart';
import 'package:orgro/src/transclusion/transclusion_directive.dart';
import 'package:orgro/src/transclusion/transclusion_resolver.dart';

/// Colors for transclusion styling, matching the user's Emacs configuration.
class TransclusionColors {
  // Dark theme colors (gruber-darker)
  static const darkBackground = Color(0xFF1c1a22); // Purple-tinted dark
  static const darkBorder = Color(0xFF9e95c7); // Purple fringe

  // Light theme colors (gruber-lighter)
  static const lightBackground = Color(0xFFF5f2f8); // Purple-tinted light
  static const lightBorder = Color(0xFF6a5a8e); // Purple fringe
}

/// Widget for rendering transcluded content.
///
/// Shows the transcluded content inline with:
/// - Purple-tinted background
/// - 2px purple left border
/// - Tap to toggle visibility
class OrgTransclusionWidget extends StatefulWidget {
  const OrgTransclusionWidget({
    required this.meta,
    required this.directive,
    super.key,
  });

  final OrgMeta meta;
  final TransclusionDirective directive;

  @override
  State<OrgTransclusionWidget> createState() => _OrgTransclusionWidgetState();
}

class _OrgTransclusionWidgetState extends State<OrgTransclusionWidget> {
  bool _isExpanded = true; // Default: expanded
  Future<TransclusionResult>? _resolveFuture;
  TransclusionSuccess? _resolvedResult;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? TransclusionColors.darkBackground
            : TransclusionColors.lightBackground,
        border: Border(
          left: BorderSide(
            color: isDark
                ? TransclusionColors.darkBorder
                : TransclusionColors.lightBorder,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with toggle
          _buildHeader(context),
          // Content (when expanded)
          if (_isExpanded) _buildContent(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? TransclusionColors.darkBorder
        : TransclusionColors.lightBorder;

    return InkWell(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      onLongPress: _navigateToSource,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: borderColor,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.link,
              size: 14,
              color: borderColor,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _getHeaderText(),
                style: TextStyle(
                  fontSize: 12,
                  color: borderColor,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Navigate to the source file/section when long-pressing the header.
  void _navigateToSource() {
    final result = _resolvedResult;
    if (result == null) return;

    // Navigate to the source file, optionally to the target section
    loadDocument(
      context,
      result.sourceDataSource,
      target: result.targetSection,
    );
  }

  String _getHeaderText() {
    final directive = widget.directive;

    // Use description if available
    if (directive.description != null && directive.description!.isNotEmpty) {
      return directive.description!;
    }

    // Build from link
    final link = directive.link;
    final buffer = StringBuffer();

    if (link.scheme == 'id:') {
      buffer.write('ID: ${link.body.substring(0, 8)}...');
    } else {
      buffer.write(link.body);
    }

    if (link.extra != null) {
      buffer.write(' → ${link.extra}');
    }

    return buffer.toString();
  }

  Widget _buildContent(BuildContext context) {
    return FutureBuilder<TransclusionResult>(
      future: _resolveFuture ??= _resolve(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoading();
        }

        if (snapshot.hasError) {
          return _buildError(snapshot.error.toString());
        }

        final result = snapshot.data;
        if (result == null) {
          return _buildError('No result');
        }

        return switch (result) {
          TransclusionSuccess() => _buildSuccessAndStore(context, result),
          TransclusionError() => _buildError(result.message),
        };
      },
    );
  }

  Widget _buildSuccessAndStore(BuildContext context, TransclusionSuccess result) {
    // Store the result for navigation
    _resolvedResult = result;
    return _buildSuccess(context, result);
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: Colors.orange[700],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[700],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: () {
              setState(() {
                _resolveFuture = _resolve();
              });
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, TransclusionSuccess result) {
    final content = result.content;

    // Track this transclusion in the ancestor stack
    return TransclusionAncestorWidget(
      sourceId: result.sourceId,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: switch (content) {
          OrgDocument() => OrgDocumentWidget(content, shrinkWrap: true),
          OrgSection() => OrgSectionWidget(content, root: true, shrinkWrap: true),
          _ => _buildGenericContent(content),
        },
      ),
    );
  }

  Widget _buildGenericContent(OrgTree content) {
    // For other content types, render as markup text
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(content.toMarkup()),
    );
  }

  Future<TransclusionResult> _resolve() async {
    final docProvider = DocumentProvider.of(context);
    final dataSource = docProvider.dataSource;
    final cache = docProvider.transclusionCache;

    // Get ancestor IDs from context
    final ancestors = TransclusionAncestorWidget.ancestorsOf(context);

    final resolver = TransclusionResolver(
      dataSource: dataSource,
      cache: cache,
    );

    return resolver.resolve(widget.directive, ancestorIds: ancestors);
  }
}

/// InheritedWidget to track transclusion ancestors for circular detection.
class TransclusionAncestorWidget extends InheritedWidget {
  const TransclusionAncestorWidget({
    required this.sourceId,
    required super.child,
    super.key,
  });

  final String sourceId;

  /// Get the set of ancestor source IDs from the context.
  static Set<String> ancestorsOf(BuildContext context) {
    final ancestors = <String>{};
    context.visitAncestorElements((element) {
      if (element.widget is TransclusionAncestorWidget) {
        final widget = element.widget as TransclusionAncestorWidget;
        ancestors.add(widget.sourceId);
      }
      return true; // Continue visiting
    });
    return ancestors;
  }

  @override
  bool updateShouldNotify(TransclusionAncestorWidget oldWidget) =>
      sourceId != oldWidget.sourceId;
}
