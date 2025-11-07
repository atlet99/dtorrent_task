import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/metadata/metadata_downloader.dart';
import 'package:dtorrent_task_v2/src/metadata/magnet_parser.dart';

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

    test('should create with trackers from magnet URI', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr=http://tracker1.com&tr=http://tracker2.com';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });

    test('should create with tracker tiers from magnet URI', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr.1=http://tracker1.com&tr.2=http://tracker2.com';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });

    test('should create with trackers parameter', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final trackers = [
        Uri.parse('http://tracker1.com'),
        Uri.parse('http://tracker2.com'),
      ];

      final downloader = MetadataDownloader(infoHash, trackers: trackers);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });

    test('should create with tracker tiers parameter', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final trackerTiers = [
        TrackerTier([Uri.parse('http://tracker1.com')]),
        TrackerTier([Uri.parse('http://tracker2.com')]),
      ];

      final downloader =
          MetadataDownloader(infoHash, trackerTiers: trackerTiers);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });

    test('should have DHT instance', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader.dht, isNotNull);
    });

    test('should track metadata size when set', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader.metaDataSize, isNull);
      // metadata size is set during handshake, which we can't easily test without peers
    });

    test('should calculate bytes downloaded correctly', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader.bytesDownloaded, equals(0));
      // bytesDownloaded is calculated based on completed pieces
    });

    test('should handle magnet URI with web seeds', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&ws=http://webseed.example.com/file';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      // Web seeds are parsed but not used in MetadataDownloader
      // They should be passed to TorrentTask instead
    });

    test('should handle magnet URI with acceptable sources', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&as=http://source.example.com/file';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
    });

    test('should handle magnet URI with selected file indices', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=0&so=2';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      // Selected file indices are parsed but not used in MetadataDownloader
      // They should be passed to TorrentTask instead
    });
  });
}
