import 'package:flutter/foundation.dart';
import 'package:org_parser/org_parser.dart';
import 'package:orgro/src/data_source.dart';
import 'package:orgro/src/native_search.dart';
import 'package:orgro/src/transclusion/transclusion_cache.dart';
import 'package:orgro/src/transclusion/transclusion_directive.dart';

/// Result of resolving a transclusion directive.
sealed class TransclusionResult {}

/// Successfully resolved transclusion content.
class TransclusionSuccess extends TransclusionResult {
  TransclusionSuccess({
    required this.content,
    required this.sourceId,
    required this.sourceName,
    required this.sourceDataSource,
    this.targetSection,
  });

  /// The resolved and transformed content.
  final OrgTree content;

  /// Identifier of the source file (for circular detection and cache invalidation).
  final String sourceId;

  /// Name of the source file (for display).
  final String sourceName;

  /// DataSource for the source file (for navigation).
  final DataSource sourceDataSource;

  /// The target section name if specified (e.g., "* Week 5").
  final String? targetSection;
}

/// Error resolving transclusion.
class TransclusionError extends TransclusionResult {
  TransclusionError({
    required this.message,
    required this.type,
  });

  factory TransclusionError.notFound(String target) => TransclusionError(
        message: 'File not found: $target',
        type: TransclusionErrorType.fileNotFound,
      );

  factory TransclusionError.circular(String sourceId) => TransclusionError(
        message: 'Circular transclusion detected',
        type: TransclusionErrorType.circularReference,
      );

  factory TransclusionError.invalidTarget(String target) => TransclusionError(
        message: 'Target not found: $target',
        type: TransclusionErrorType.invalidTarget,
      );

  factory TransclusionError.permission() => TransclusionError(
        message: 'Directory access required',
        type: TransclusionErrorType.permissionDenied,
      );

  factory TransclusionError.parse(String message) => TransclusionError(
        message: 'Parse error: $message',
        type: TransclusionErrorType.parseError,
      );

  final String message;
  final TransclusionErrorType type;
}

enum TransclusionErrorType {
  fileNotFound,
  circularReference,
  invalidTarget,
  permissionDenied,
  parseError,
}

/// Resolves transclusion directives by loading content from referenced files.
class TransclusionResolver {
  TransclusionResolver({
    required this.dataSource,
    required this.cache,
    this.maxDepth = 5,
  });

  /// The data source of the current document.
  final DataSource dataSource;

  /// Cache for resolved transclusions.
  final TransclusionCache cache;

  /// Maximum nesting depth for transclusions.
  final int maxDepth;

  /// Resolve a transclusion directive.
  ///
  /// [ancestorIds] contains IDs of all ancestor transclusions for circular detection.
  Future<TransclusionResult> resolve(
    TransclusionDirective directive, {
    Set<String> ancestorIds = const {},
  }) async {
    // Check nesting depth
    if (ancestorIds.length >= maxDepth) {
      return TransclusionError(
        message: 'Maximum transclusion depth ($maxDepth) exceeded',
        type: TransclusionErrorType.circularReference,
      );
    }

    // Generate source ID from link
    final sourceId = _getSourceId(directive);

    // Check for circular reference
    if (ancestorIds.contains(sourceId)) {
      return TransclusionError.circular(sourceId);
    }

    // Check cache
    final cached = cache.get(directive);
    if (cached != null) {
      return TransclusionSuccess(
        content: cached.content,
        sourceId: cached.sourceId,
        sourceName: _getSourceName(directive),
        sourceDataSource: cached.sourceDataSource,
        targetSection: cached.targetSection,
      );
    }

    try {
      // Resolve link to data source
      final targetSource = await _resolveLink(directive);
      if (targetSource == null) {
        return TransclusionError.notFound(directive.link.toString());
      }

      // Load and parse content
      final content = await targetSource.content;
      final parsed = await compute(_parseContent, content);

      // Extract target section if search option specified
      OrgTree targetContent = parsed;
      String? navigationTarget;
      final searchOption = directive.link.extra;
      debugPrint('Transclusion search option: "$searchOption"');
      debugPrint('Link: scheme=${directive.link.scheme}, body=${directive.link.body}, extra=${directive.link.extra}');
      if (searchOption != null && searchOption.isNotEmpty) {
        final extracted = _extractTarget(parsed, searchOption);
        if (extracted == null) {
          debugPrint('Failed to extract target for search option: "$searchOption"');
          return TransclusionError.invalidTarget(searchOption);
        }
        targetContent = extracted;
        // Get the actual navigation target from the matched section
        navigationTarget = _getNavigationTarget(extracted);
      }

      // Apply property transformations
      targetContent = _applyProperties(targetContent, directive);

      // Cache the result - use navigation target for proper section lookup
      cache.put(directive, targetContent, sourceId, targetSource, navigationTarget);

      return TransclusionSuccess(
        content: targetContent,
        sourceId: sourceId,
        sourceName: targetSource.name,
        sourceDataSource: targetSource,
        targetSection: navigationTarget,
      );
    } catch (e) {
      debugPrint('Transclusion resolution error: $e');
      return TransclusionError.parse(e.toString());
    }
  }

  /// Resolve the link in a directive to a DataSource.
  Future<DataSource?> _resolveLink(TransclusionDirective directive) async {
    final link = directive.link;

    if (link.scheme == 'id:') {
      // ID link - search for file containing this ID
      return await _resolveIdLink(link.body);
    } else if (link.isRelative) {
      // Relative file link
      return await _resolveRelativeLink(link.body);
    }

    // Unsupported link type
    return null;
  }

  /// Resolve an ID link by searching for the file containing the ID.
  Future<DataSource?> _resolveIdLink(String orgId) async {
    if (dataSource is! NativeDataSource) {
      debugPrint('ID links not supported for non-native data sources');
      return null;
    }

    final nativeSource = dataSource as NativeDataSource;
    if (nativeSource.rootDirIdentifier == null) {
      debugPrint('No root directory for ID search');
      return null;
    }

    final requestId = Object().hashCode.toString();
    try {
      final result = await findFileForId(
        requestId: requestId,
        orgId: orgId,
        dirIdentifier: nativeSource.rootDirIdentifier!,
      );
      return result;
    } catch (e) {
      debugPrint('Error finding file for ID: $e');
      return null;
    }
  }

  /// Resolve a relative file link.
  Future<DataSource?> _resolveRelativeLink(String relativePath) async {
    if (dataSource.needsToResolveParent) {
      return null;
    }

    try {
      return await dataSource.resolveRelative(relativePath);
    } catch (e) {
      debugPrint('Error resolving relative link: $e');
      return null;
    }
  }

  /// Generate a unique ID for the source (for circular detection).
  String _getSourceId(TransclusionDirective directive) {
    final link = directive.link;
    return '${link.scheme ?? ''}${link.body}';
  }

  /// Get a display name for the source.
  String _getSourceName(TransclusionDirective directive) {
    // Use description if available
    if (directive.description != null && directive.description!.isNotEmpty) {
      return directive.description!;
    }
    // Otherwise use the link body
    final body = directive.link.body;
    // Extract filename from path
    final lastSlash = body.lastIndexOf('/');
    return lastSlash >= 0 ? body.substring(lastSlash + 1) : body;
  }

  /// Extract target section from parsed document based on search option.
  OrgTree? _extractTarget(OrgDocument doc, String searchOption) {
    // Handle different search option formats
    // https://orgmode.org/manual/Search-Options.html

    if (searchOption.startsWith('*')) {
      // Headline search: *some headline
      final title = searchOption.substring(1).trim();
      return _findSectionByTitle(doc, title);
    } else if (searchOption.startsWith('#')) {
      // Custom ID search: #custom-id
      final customId = searchOption.substring(1).trim();
      return _findSectionByCustomId(doc, customId);
    } else if (searchOption.startsWith('/') && searchOption.endsWith('/')) {
      // Regex search - not implemented yet
      debugPrint('Regex search not implemented: $searchOption');
      return null;
    } else {
      // Named target or dedicated target
      return _findByTarget(doc, searchOption);
    }
  }

  /// Find a section by its headline title.
  ///
  /// The matching is flexible:
  /// 1. Exact match (case-insensitive)
  /// 2. Match after stripping statistics cookies like [/], [0/2], etc.
  /// 3. Match if headline starts with the search title
  OrgSection? _findSectionByTitle(OrgTree tree, String title) {
    OrgSection? result;
    final searchTitle = title.trim().toLowerCase();
    debugPrint('Searching for headline: "$searchTitle"');

    // First pass: try exact match
    tree.visitSections((section) {
      final rawTitle = section.headline.title?.toMarkup();
      final headlineTitle = rawTitle?.trim().toLowerCase();
      if (headlineTitle != null && headlineTitle == searchTitle) {
        debugPrint('  Found exact match: "$headlineTitle"');
        result = section;
        return false;
      }
      return true;
    });

    if (result != null) return result;

    // Second pass: try matching after stripping statistics cookies
    // Statistics cookies look like [/], [0/2], [7/7], [50%], etc.
    final cookiePattern = RegExp(r'\s*\[[\d/%]+\]\s*$');
    tree.visitSections((section) {
      final rawTitle = section.headline.title?.toMarkup();
      if (rawTitle == null) return true;

      // Strip the cookie and compare
      final strippedTitle = rawTitle.replaceAll(cookiePattern, '').trim().toLowerCase();
      debugPrint('  Checking stripped headline: "$strippedTitle" (original: "${rawTitle.trim().toLowerCase()}")');
      if (strippedTitle == searchTitle) {
        debugPrint('  Found match after stripping cookie!');
        result = section;
        return false;
      }
      return true;
    });

    if (result != null) return result;

    // Third pass: try prefix match (headline starts with search title)
    tree.visitSections((section) {
      final rawTitle = section.headline.title?.toMarkup();
      final headlineTitle = rawTitle?.trim().toLowerCase();
      if (headlineTitle != null && headlineTitle.startsWith(searchTitle)) {
        debugPrint('  Found prefix match: "$headlineTitle"');
        result = section;
        return false;
      }
      return true;
    });

    if (result == null) {
      debugPrint('No matching headline found for: "$searchTitle"');
    }
    return result;
  }

  /// Find a section by its CUSTOM_ID property.
  OrgSection? _findSectionByCustomId(OrgTree tree, String customId) {
    OrgSection? result;
    tree.visitSections((section) {
      // customIds returns a list; get the first one if any
      final sectionIds = section.customIds;
      if (sectionIds.isNotEmpty &&
          sectionIds.first.toLowerCase() == customId.toLowerCase()) {
        result = section;
        return false;
      }
      return true;
    });
    return result;
  }

  /// Find content by a named target or dedicated target.
  OrgTree? _findByTarget(OrgDocument doc, String target) {
    // Try to find by ID first
    OrgSection? result;
    doc.visitSections((section) {
      if (section.id == target) {
        result = section;
        return false;
      }
      return true;
    });
    return result;
  }

  /// Get a navigation target string for the given tree.
  ///
  /// This returns a target that can be used with `handleInitialTarget` to
  /// navigate to this section. Prefers ID, then custom ID, then headline title.
  String? _getNavigationTarget(OrgTree tree) {
    if (tree is! OrgSection) return null;

    // Prefer ID for most reliable navigation
    final id = tree.ids.firstOrNull;
    if (id != null) {
      return 'id:$id';
    }

    // Fall back to custom ID
    final customId = tree.customIds.firstOrNull;
    if (customId != null) {
      return '#$customId';
    }

    // Fall back to headline title
    final title = tree.headline.rawTitle;
    if (title != null && title.isNotEmpty) {
      return '*$title';
    }

    return null;
  }

  /// Apply transclusion properties to transform the content.
  OrgTree _applyProperties(OrgTree content, TransclusionDirective directive) {
    var result = content;

    // :no-first-heading - Remove the top-level headline
    if (directive.noFirstHeading && result is OrgSection) {
      // Create a document from the section's content and subsections
      result = _removeFirstHeading(result);
    }

    // :only-contents - Remove subsections, keep only the body
    if (directive.onlyContents && result is OrgSection) {
      result = _keepOnlyContents(result);
    }

    // :level N - Adjust headline levels (future enhancement)
    // This would require modifying the OrgSection nodes

    return result;
  }

  /// Remove the first heading, keeping content and subsections.
  OrgTree _removeFirstHeading(OrgSection section) {
    // The section has:
    // - headline (which we want to remove)
    // - content (body text, which we keep)
    // - sections (subsections, which we keep)
    //
    // We return an OrgDocument containing the content and subsections
    return OrgDocument(section.content, section.sections);
  }

  /// Keep only the body content, removing subsections.
  OrgSection _keepOnlyContents(OrgSection section) {
    return OrgSection(section.headline, section.content, const []);
  }
}

/// Parse content in an isolate to avoid blocking the UI.
OrgDocument _parseContent(String content) {
  return OrgDocument.parse(content, interpretEmbeddedSettings: true);
}
