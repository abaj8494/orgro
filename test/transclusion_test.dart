import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:org_parser/org_parser.dart';
import 'package:orgro/src/data_source.dart';
import 'package:orgro/src/transclusion/transclusion_directive.dart';
import 'package:orgro/src/transclusion/transclusion_cache.dart';

/// Mock DataSource for testing
class MockDataSource extends DataSource {
  MockDataSource(super.name);

  @override
  String get id => 'mock:$name';

  @override
  String get content => '';

  @override
  Uint8List get bytes => Uint8List(0);

  @override
  bool get needsToResolveParent => false;

  @override
  DataSource resolveRelative(String relativePath) => MockDataSource(relativePath);

  @override
  Map<String, Object?> toJson() => {'type': 'mock', 'name': name};
}

void main() {
  group('TransclusionDirective', () {
    group('tryParse', () {
      test('parses basic id link', () {
        final doc = OrgDocument.parse(
          '#+transclude: [[id:51fe6c3d-45e2-4655-bc1c-9358f989d02a]]\n',
        );
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
        expect(directive!.link.scheme, equals('id:'));
        expect(directive.link.body, equals('51fe6c3d-45e2-4655-bc1c-9358f989d02a'));
        expect(directive.link.extra, isNull);
        expect(directive.description, isNull);
        expect(directive.noFirstHeading, isFalse);
        expect(directive.onlyContents, isFalse);
      });

      test('parses id link with search option', () {
        final doc = OrgDocument.parse(
          '#+transclude: [[id:51fe6c3d-45e2-4655-bc1c-9358f989d02a::* Week 5]]\n',
        );
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
        expect(directive!.link.scheme, equals('id:'));
        expect(directive.link.body, equals('51fe6c3d-45e2-4655-bc1c-9358f989d02a'));
        expect(directive.link.extra, equals('* Week 5'));
      });

      test('parses id link with description', () {
        final doc = OrgDocument.parse(
          '#+transclude: [[id:51fe6c3d-45e2-4655-bc1c-9358f989d02a::* Week 5][My Description]]\n',
        );
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
        expect(directive!.description, equals('My Description'));
        expect(directive.link.extra, equals('* Week 5'));
      });

      test('parses :no-first-heading property', () {
        final doc = OrgDocument.parse(
          '#+transclude: [[id:uuid]] :no-first-heading\n',
        );
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
        expect(directive!.noFirstHeading, isTrue);
        expect(directive.onlyContents, isFalse);
      });

      test('parses :only-contents property', () {
        final doc = OrgDocument.parse(
          '#+transclude: [[id:uuid]] :only-contents\n',
        );
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
        expect(directive!.onlyContents, isTrue);
        expect(directive.noFirstHeading, isFalse);
      });

      test('parses :level property', () {
        final doc = OrgDocument.parse(
          '#+transclude: [[id:uuid]] :level 2\n',
        );
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
        expect(directive!.level, equals(2));
      });

      test('parses multiple properties', () {
        final doc = OrgDocument.parse(
          '#+transclude: [[id:uuid::*heading][desc]] :no-first-heading :only-contents :level 3\n',
        );
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
        expect(directive!.noFirstHeading, isTrue);
        expect(directive.onlyContents, isTrue);
        expect(directive.level, equals(3));
        expect(directive.description, equals('desc'));
        expect(directive.link.extra, equals('*heading'));
      });

      test('parses file link', () {
        final doc = OrgDocument.parse(
          '#+transclude: [[file:./notes.org::*Section]]\n',
        );
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
        expect(directive!.link.scheme, equals('file:'));
        expect(directive.link.body, equals('./notes.org'));
        expect(directive.link.extra, equals('*Section'));
      });

      test('parses relative file link without scheme', () {
        final doc = OrgDocument.parse(
          '#+transclude: [[./notes.org::*Section]]\n',
        );
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
        expect(directive!.link.isRelative, isTrue);
        expect(directive.link.body, equals('./notes.org'));
        expect(directive.link.extra, equals('*Section'));
      });

      test('returns null for non-transclude meta', () {
        final doc = OrgDocument.parse('#+TITLE: My Document\n');
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNull);
      });

      test('returns null for transclude without link', () {
        final doc = OrgDocument.parse('#+transclude: some text\n');
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNull);
      });

      test('case insensitive directive key', () {
        final doc = OrgDocument.parse('#+TRANSCLUDE: [[id:uuid]]\n');
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
      });

      test('case insensitive properties', () {
        final doc = OrgDocument.parse(
          '#+transclude: [[id:uuid]] :NO-FIRST-HEADING :ONLY-CONTENTS :LEVEL 2\n',
        );
        final meta = doc.content!.children.first as OrgMeta;
        final directive = TransclusionDirective.tryParse(meta);

        expect(directive, isNotNull);
        expect(directive!.noFirstHeading, isTrue);
        expect(directive.onlyContents, isTrue);
        expect(directive.level, equals(2));
      });
    });

    group('extractTransclusions', () {
      test('extracts transclusions from document', () {
        final doc = OrgDocument.parse('''
#+TITLE: Test
#+transclude: [[id:uuid1]]
Some content
#+transclude: [[id:uuid2::*Heading]]
* Section
#+transclude: [[id:uuid3]] :no-first-heading
''');
        final directives = extractTransclusions(doc);

        expect(directives.length, equals(3));
        expect(directives[0].link.body, equals('uuid1'));
        expect(directives[1].link.extra, equals('*Heading'));
        expect(directives[2].noFirstHeading, isTrue);
      });

      test('returns empty list when no transclusions', () {
        final doc = OrgDocument.parse('''
#+TITLE: Test
Some content
* Section
More content
''');
        final directives = extractTransclusions(doc);

        expect(directives, isEmpty);
      });
    });

    group('hasTransclusions', () {
      test('returns true when transclusions present', () {
        final doc = OrgDocument.parse('''
#+TITLE: Test
#+transclude: [[id:uuid]]
''');
        expect(hasTransclusions(doc), isTrue);
      });

      test('returns false when no transclusions', () {
        final doc = OrgDocument.parse('''
#+TITLE: Test
Some content
''');
        expect(hasTransclusions(doc), isFalse);
      });

      test('detects transclusion in section', () {
        final doc = OrgDocument.parse('''
* Section
#+transclude: [[id:uuid]]
''');
        expect(hasTransclusions(doc), isTrue);
      });
    });
  });

  group('TransclusionCache', () {
    TransclusionDirective makeDirective(String linkBody, {
      String? extra,
      bool noFirstHeading = false,
      bool onlyContents = false,
    }) {
      final extraPart = extra != null ? '::$extra' : '';
      final props = [
        if (noFirstHeading) ':no-first-heading',
        if (onlyContents) ':only-contents',
      ].join(' ');
      final doc = OrgDocument.parse(
        '#+transclude: [[id:$linkBody$extraPart]] $props\n',
      );
      final meta = doc.content!.children.first as OrgMeta;
      return TransclusionDirective.tryParse(meta)!;
    }

    test('stores and retrieves entries', () {
      final cache = TransclusionCache();
      final directive = makeDirective('uuid', extra: '*Heading');
      final doc = OrgDocument.parse('* Test\nContent');
      final mockSource = MockDataSource('test.org');

      cache.put(directive, doc, 'source-id', mockSource, '*Heading');
      final result = cache.get(directive);

      expect(result, isNotNull);
      expect(result!.content, equals(doc));
      expect(result.sourceId, equals('source-id'));
      expect(result.sourceDataSource, equals(mockSource));
      expect(result.targetSection, equals('*Heading'));
    });

    test('returns null for missing entry', () {
      final cache = TransclusionCache();
      final directive = makeDirective('uuid');

      expect(cache.get(directive), isNull);
    });

    test('different links return different results', () {
      final cache = TransclusionCache();
      final directive1 = makeDirective('uuid1');
      final directive2 = makeDirective('uuid2');
      final doc1 = OrgDocument.parse('* Doc1');
      final doc2 = OrgDocument.parse('* Doc2');
      final mockSource = MockDataSource('test.org');

      cache.put(directive1, doc1, 'source1', mockSource, null);
      cache.put(directive2, doc2, 'source2', mockSource, null);

      expect(cache.get(directive1)!.content, equals(doc1));
      expect(cache.get(directive2)!.content, equals(doc2));
    });

    test('same location but different search options are different keys', () {
      final cache = TransclusionCache();
      final directive1 = makeDirective('uuid', extra: '*Heading1');
      final directive2 = makeDirective('uuid', extra: '*Heading2');
      final doc1 = OrgDocument.parse('* Doc1');
      final doc2 = OrgDocument.parse('* Doc2');
      final mockSource = MockDataSource('test.org');

      cache.put(directive1, doc1, 'source', mockSource, '*Heading1');
      cache.put(directive2, doc2, 'source', mockSource, '*Heading2');

      expect(cache.get(directive1)!.content, equals(doc1));
      expect(cache.get(directive2)!.content, equals(doc2));
    });

    test('noFirstHeading affects cache key', () {
      final cache = TransclusionCache();
      final directive1 = makeDirective('uuid', noFirstHeading: false);
      final directive2 = makeDirective('uuid', noFirstHeading: true);
      final doc1 = OrgDocument.parse('* Doc1');
      final doc2 = OrgDocument.parse('* Doc2');
      final mockSource = MockDataSource('test.org');

      cache.put(directive1, doc1, 'source', mockSource, null);
      cache.put(directive2, doc2, 'source', mockSource, null);

      expect(cache.get(directive1)!.content, equals(doc1));
      expect(cache.get(directive2)!.content, equals(doc2));
    });

    test('clear removes all entries', () {
      final cache = TransclusionCache();
      final directive = makeDirective('uuid');
      final doc = OrgDocument.parse('* Test');
      final mockSource = MockDataSource('test.org');

      cache.put(directive, doc, 'source', mockSource, null);
      expect(cache.get(directive), isNotNull);

      cache.clear();
      expect(cache.get(directive), isNull);
    });

    test('invalidate removes entries by source id', () {
      final cache = TransclusionCache();
      final directive1 = makeDirective('uuid1');
      final directive2 = makeDirective('uuid2');
      final doc1 = OrgDocument.parse('* Doc1');
      final doc2 = OrgDocument.parse('* Doc2');
      final mockSource = MockDataSource('test.org');

      cache.put(directive1, doc1, 'source1', mockSource, null);
      cache.put(directive2, doc2, 'source2', mockSource, null);

      cache.invalidate('source1');

      expect(cache.get(directive1), isNull);
      expect(cache.get(directive2), isNotNull);
    });

    test('respects max size limit', () {
      final cache = TransclusionCache(maxSize: 3);
      final mockSource = MockDataSource('test.org');

      final directives = <TransclusionDirective>[];
      for (var i = 0; i < 5; i++) {
        final directive = makeDirective('uuid$i');
        directives.add(directive);
        cache.put(directive, OrgDocument.parse('* Doc$i'), 'source$i', mockSource, null);
      }

      // First two should be evicted
      expect(cache.get(directives[0]), isNull);
      expect(cache.get(directives[1]), isNull);

      // Last three should still be present
      expect(cache.get(directives[2]), isNotNull);
      expect(cache.get(directives[3]), isNotNull);
      expect(cache.get(directives[4]), isNotNull);
    });

    test('length returns correct count', () {
      final cache = TransclusionCache();
      final mockSource = MockDataSource('test.org');

      expect(cache.length, equals(0));

      cache.put(makeDirective('uuid1'), OrgDocument.parse('* Doc1'), 'src', mockSource, null);
      expect(cache.length, equals(1));

      cache.put(makeDirective('uuid2'), OrgDocument.parse('* Doc2'), 'src', mockSource, null);
      expect(cache.length, equals(2));

      cache.clear();
      expect(cache.length, equals(0));
    });
  });
}
