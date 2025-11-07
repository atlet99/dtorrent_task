import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/piece/web_seed_downloader.dart';

void main() {
  group('WebSeedDownloader Tests', () {
    test('should initialize with web seeds and acceptable sources', () {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];
      final acceptableSources = [Uri.parse('http://source.example.com/file')];
      final downloader = WebSeedDownloader(
        webSeeds: webSeeds,
        acceptableSources: acceptableSources,
        totalLength: 1048576,
        pieceLength: 16384,
      );

      expect(downloader, isNotNull);
      expect(downloader.webSeeds.length, equals(1));
      expect(downloader.acceptableSources.length, equals(1));
      expect(downloader.hasUrls, isTrue);
    });

    test('should return false for hasUrls when no URLs provided', () {
      final downloader = WebSeedDownloader(
        webSeeds: [],
        acceptableSources: [],
        totalLength: 1048576,
        pieceLength: 16384,
      );

      expect(downloader.hasUrls, isFalse);
    });

    test('should combine web seeds and acceptable sources in allUrls', () {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];
      final acceptableSources = [Uri.parse('http://source.example.com/file')];
      final downloader = WebSeedDownloader(
        webSeeds: webSeeds,
        acceptableSources: acceptableSources,
        totalLength: 1048576,
        pieceLength: 16384,
      );

      expect(downloader.allUrls.length, equals(2));
      expect(downloader.allUrls, contains(webSeeds[0]));
      expect(downloader.allUrls, contains(acceptableSources[0]));
    });

    test('should return null when downloading from invalid URL', () async {
      final webSeeds = [
        Uri.parse('http://invalid-url-that-does-not-exist-12345.com/file')
      ];
      final downloader = WebSeedDownloader(
        webSeeds: webSeeds,
        acceptableSources: [],
        totalLength: 1048576,
        pieceLength: 16384,
      );

      final result = await downloader.downloadPiece(0, 0, 16384);
      expect(result, isNull);
    });

    test('should return null when no URLs available', () async {
      final downloader = WebSeedDownloader(
        webSeeds: [],
        acceptableSources: [],
        totalLength: 1048576,
        pieceLength: 16384,
      );

      final result = await downloader.downloadPiece(0, 0, 16384);
      expect(result, isNull);
    });

    test('should track failed URLs', () async {
      final webSeeds = [
        Uri.parse('http://invalid-url-that-does-not-exist-12345.com/file')
      ];
      final downloader = WebSeedDownloader(
        webSeeds: webSeeds,
        acceptableSources: [],
        totalLength: 1048576,
        pieceLength: 16384,
      );

      // Try to download (will fail)
      await downloader.downloadPiece(0, 0, 16384);

      // URL should be marked as failed
      expect(downloader.isUrlAvailable(webSeeds[0]),
          isTrue); // Still available (hasn't reached max retries)

      // Try multiple times to reach max retries
      for (var i = 0; i < 3; i++) {
        await downloader.downloadPiece(0, 0, 16384);
      }

      // After max retries, URL should not be available
      expect(downloader.isUrlAvailable(webSeeds[0]), isFalse);
    });

    test('should reset failure counts', () {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];
      final downloader = WebSeedDownloader(
        webSeeds: webSeeds,
        acceptableSources: [],
        totalLength: 1048576,
        pieceLength: 16384,
      );

      // Simulate failure tracking
      // (We can't easily test this without actual HTTP failures, but we can test the reset method)
      downloader.resetFailureCounts();
      expect(downloader.isUrlAvailable(webSeeds[0]), isTrue);
    });

    test('should dispose resources', () {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];
      final downloader = WebSeedDownloader(
        webSeeds: webSeeds,
        acceptableSources: [],
        totalLength: 1048576,
        pieceLength: 16384,
      );

      downloader.dispose();
      // After dispose, should still be able to check URLs
      expect(downloader.hasUrls, isTrue);
    });

    test('should handle multiple web seed URLs with retry', () async {
      final webSeeds = [
        Uri.parse('http://invalid-url-1.com/file'),
        Uri.parse('http://invalid-url-2.com/file'),
      ];
      final downloader = WebSeedDownloader(
        webSeeds: webSeeds,
        acceptableSources: [],
        totalLength: 1048576,
        pieceLength: 16384,
      );

      // Should try all URLs before giving up
      final result = await downloader.downloadPiece(0, 0, 16384);
      expect(result, isNull);
    });

    test('should prefer web seeds over acceptable sources', () {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];
      final acceptableSources = [Uri.parse('http://source.example.com/file')];
      final downloader = WebSeedDownloader(
        webSeeds: webSeeds,
        acceptableSources: acceptableSources,
        totalLength: 1048576,
        pieceLength: 16384,
      );

      // allUrls should list web seeds first
      expect(downloader.allUrls[0], equals(webSeeds[0]));
      expect(downloader.allUrls[1], equals(acceptableSources[0]));
    });

    test('should handle empty piece size', () async {
      final webSeeds = [Uri.parse('http://invalid-url.com/file')];
      final downloader = WebSeedDownloader(
        webSeeds: webSeeds,
        acceptableSources: [],
        totalLength: 1048576,
        pieceLength: 16384,
      );

      // Empty piece size should return empty list or null
      final result = await downloader.downloadPiece(0, 0, 0);
      // Result can be null or empty list depending on implementation
      expect(result == null || result.isEmpty, isTrue);
    });
  });
}
