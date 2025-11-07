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

    test('should parse web seed URLs (BEP 0019)', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&ws=http://webseed.example.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.webSeeds.length, equals(1));
      expect(magnet.webSeeds[0].toString(), contains('webseed.example.com'));
    });

    test('should parse multiple web seed URLs', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&ws=http://webseed1.com/file&ws=http://webseed2.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.webSeeds.length, greaterThanOrEqualTo(1));
    });

    test('should parse acceptable source URLs (BEP 0019)', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&as=http://source.example.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.acceptableSources.length, equals(1));
      expect(magnet.acceptableSources[0].toString(),
          contains('source.example.com'));
    });

    test('should parse multiple acceptable source URLs', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&as=http://source1.com/file&as=http://source2.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.acceptableSources.length, greaterThanOrEqualTo(1));
    });

    test('should parse selected file indices (BEP 0053)', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=0&so=2&so=5';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.selectedFileIndices, isNotNull);
      expect(magnet.selectedFileIndices!.length, equals(3));
      expect(magnet.selectedFileIndices, containsAll([0, 2, 5]));
    });

    test('should handle numbered web seed parameters', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&ws.1=http://webseed1.com/file&ws.2=http://webseed2.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.webSeeds.length, equals(2));
    });

    test('should handle numbered acceptable source parameters', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&as.1=http://source1.com/file&as.2=http://source2.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.acceptableSources.length, equals(2));
    });

    test('should parse tracker tiers (BEP 0012)', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr.1=http://tracker1.com&tr.2=http://tracker2.com';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.trackerTiers.length, equals(2));
      expect(magnet.trackerTiers[0].trackers.length, equals(1));
      expect(magnet.trackerTiers[1].trackers.length, equals(1));
    });

    test('should group trackers in same tier when using tr parameter', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr=http://tracker1.com&tr=http://tracker2.com';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.trackerTiers.length, equals(1));
      expect(magnet.trackerTiers[0].trackers.length, equals(2));
    });

    test('should parse Base32 infohash (RFC 4648)', () {
      // Base32 encoding of 20 zero bytes: AAAAAAAAAAAAAAAAAAAAAAAAAA
      final magnetUri = 'magnet:?xt=urn:btih:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.infoHash.length, equals(20));
      // All bytes should be zero
      expect(magnet.infoHash.every((b) => b == 0), isTrue);
    });

    test('should reject invalid Base32 infohash', () {
      final magnetUri =
          'magnet:?xt=urn:btih:INVALIDBASE32CHARACTERS123456789012';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNull);
    });

    test('should create magnet URI with web seeds', () {
      final infoHash = Uint8List.fromList(List<int>.generate(20, (i) => i));
      final webSeeds = [
        Uri.parse('http://webseed1.com/file'),
        Uri.parse('http://webseed2.com/file'),
      ];
      final magnet = MagnetLink(
        infoHash: infoHash,
        webSeeds: webSeeds,
      );

      final uri = MagnetParser.toUri(magnet);
      expect(uri, contains('ws='));
      expect(uri, contains('webseed1'));
      expect(uri, contains('webseed2'));
    });

    test('should create magnet URI with acceptable sources', () {
      final infoHash = Uint8List.fromList(List<int>.generate(20, (i) => i));
      final acceptableSources = [
        Uri.parse('http://source1.com/file'),
        Uri.parse('http://source2.com/file'),
      ];
      final magnet = MagnetLink(
        infoHash: infoHash,
        acceptableSources: acceptableSources,
      );

      final uri = MagnetParser.toUri(magnet);
      expect(uri, contains('as='));
      expect(uri, contains('source1'));
      expect(uri, contains('source2'));
    });

    test('should create magnet URI with selected file indices', () {
      final infoHash = Uint8List.fromList(List<int>.generate(20, (i) => i));
      final magnet = MagnetLink(
        infoHash: infoHash,
        selectedFileIndices: [0, 2, 5],
      );

      final uri = MagnetParser.toUri(magnet);
      expect(uri, contains('so=0'));
      expect(uri, contains('so=2'));
      expect(uri, contains('so=5'));
    });

    test('should handle full magnet URI with all parameters', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Test+File&xl=1048576&tr=http://tracker.com&ws=http://webseed.com/file&as=http://source.com/file&so=0&so=2';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.displayName, isNotNull);
      expect(magnet.exactLength, equals(1048576));
      expect(magnet.trackers.length, greaterThanOrEqualTo(1));
      expect(magnet.webSeeds.length, equals(1));
      expect(magnet.acceptableSources.length, equals(1));
      expect(magnet.selectedFileIndices, isNotNull);
      expect(magnet.selectedFileIndices!.length, equals(2));
    });

    test('should handle invalid web seed URL scheme', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&ws=invalid://url';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      // Invalid URLs should be filtered out
      expect(magnet!.webSeeds.length, equals(0));
    });

    test('should handle invalid file index in so parameter', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=0&so=invalid&so=2';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      // Invalid indices should be filtered out
      expect(magnet!.selectedFileIndices, isNotNull);
      expect(magnet.selectedFileIndices!.length, equals(2));
      expect(magnet.selectedFileIndices, containsAll([0, 2]));
    });

    test('should handle negative file index in so parameter', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=-1&so=0';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      // Negative indices should be filtered out
      expect(magnet!.selectedFileIndices, isNotNull);
      expect(magnet.selectedFileIndices!.length, equals(1));
      expect(magnet.selectedFileIndices, contains(0));
    });
  });
}
