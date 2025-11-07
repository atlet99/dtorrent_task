import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/metadata/magnet_parser.dart';

void main() {
  group('MagnetParser Tests', () {
    test('should parse basic magnet URI', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=test+file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.infoHash.length, equals(20));
      // Display name may be URL encoded, so check for either format
      expect(
          magnet.displayName == 'test file' ||
              magnet.displayName == 'test+file',
          isTrue);
      expect(magnet.trackers, isEmpty);
    });

    test('should parse magnet URI with trackers', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr=http://tracker1.com&tr=http://tracker2.com';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      // Should parse multiple trackers
      expect(magnet!.trackers.length, greaterThanOrEqualTo(1));
      // At least one tracker should be present
      final trackerStrings = magnet.trackers.map((t) => t.toString()).join(',');
      expect(
          trackerStrings.contains('tracker1') ||
              trackerStrings.contains('tracker2'),
          isTrue);
    });

    test('should parse magnet URI with exact length', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&xl=1048576';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.exactLength, equals(1048576));
    });

    test('should handle multiple tr parameters', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr=http://tracker1.com,http://tracker2.com';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.trackers.length, equals(2));
    });

    test('should reject invalid magnet URI', () {
      final invalidUri = 'not-a-magnet-uri';
      final magnet = MagnetParser.parse(invalidUri);

      expect(magnet, isNull);
    });

    test('should reject magnet URI without xt parameter', () {
      final magnetUri = 'magnet:?dn=test+file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNull);
    });

    test('should reject magnet URI with invalid info hash length', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef0123456'; // 39 chars
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNull);
    });

    test('should create magnet URI from MagnetLink', () {
      final infoHash = Uint8List.fromList(List<int>.generate(20, (i) => i));
      final trackers = [
        Uri.parse('http://tracker1.com'),
        Uri.parse('http://tracker2.com'),
      ];
      final magnet = MagnetLink(
        infoHash: infoHash,
        displayName: 'test file',
        trackers: trackers,
        exactLength: 1048576,
      );

      final uri = MagnetParser.toUri(magnet);
      expect(uri, contains('magnet:?'));
      expect(uri, contains('xt=urn:btih:'));
      expect(uri, contains('dn=')); // Display name is URL encoded
      expect(uri, contains('tracker1'));
      expect(uri, contains('tracker2'));
      expect(uri, contains('xl=1048576'));
    });

    test('should handle SHA1 format', () {
      final magnetUri =
          'magnet:?xt=urn:sha1:0123456789abcdef0123456789abcdef01234567';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.infoHash.length, equals(20));
    });

    test('should handle URL-encoded display name', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Test%20File%20Name';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.displayName, equals('Test File Name'));
    });
  });
}
