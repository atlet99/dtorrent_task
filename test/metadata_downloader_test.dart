import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/metadata/metadata_downloader.dart';

void main() {
  group('MetadataDownloader Tests', () {
    test('should create from info hash string', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
      expect(downloader.metaDataSize, isNull);
    });

    test('should create from magnet URI', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=test+file&tr=http://tracker.example.com';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });

    test('should throw error for invalid magnet URI', () {
      expect(
        () => MetadataDownloader.fromMagnet('invalid-uri'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should track download progress', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader.progress, equals(0));
      expect(downloader.bytesDownloaded, equals(0));
    });

    test('should have active peers getter', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader.activePeers, isNotNull);
      expect(downloader.activePeers.length, equals(0));
    });
  });
}
