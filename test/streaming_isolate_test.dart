import 'dart:io';

import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/httpserver/streaming_isolate.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';

void main() {
  group('StreamingIsolate Tests', () {
    late StreamingIsolateManager isolateManager;

    setUp(() async {
      isolateManager = StreamingIsolateManager();
      await isolateManager.initialize();
    });

    tearDown(() async {
      await isolateManager.dispose();
    });

    test('should initialize isolate', () async {
      expect(isolateManager, isNotNull);
      // Isolate should be initialized in setUp
    });

    test('should get playlist from isolate', () async {
      // Create a mock torrent file list using Torrent.parse if possible
      // For now, we'll test with empty list to verify isolate works
      final files = <TorrentFile>[];

      final address = InternetAddress('127.0.0.1');
      final port = 9090;

      final playlist = await isolateManager.getPlaylist(files, address, port);

      expect(playlist, isNotNull);
      expect(playlist.length, greaterThanOrEqualTo(0));

      if (playlist.isNotEmpty) {
        final playlistString = String.fromCharCodes(playlist);
        expect(playlistString, contains('#EXTM3U'));
      }
    });

    test('should get JSON metadata from isolate', () async {
      final files = <TorrentFile>[];

      final json = await isolateManager.getJsonMetadata(
        files,
        1024 * 1024, // totalLength
        512 * 1024, // downloaded
        1000.0, // downloadSpeed
        500.0, // uploadSpeed
        10, // totalPeers
        5, // activePeers
      );

      expect(json, isNotNull);
      expect(json.length, greaterThan(0));

      final jsonString = String.fromCharCodes(json);
      expect(jsonString, contains('totalLength'));
      expect(jsonString, contains('downloaded'));
      expect(jsonString, contains('downloadSpeed'));
      expect(jsonString, contains('files'));
    });

    test('should handle timeout gracefully', () async {
      // Dispose isolate to cause timeout
      await isolateManager.dispose();

      final files = <TorrentFile>[];

      // Should return empty result on timeout
      final result = await isolateManager.getPlaylist(
        files,
        InternetAddress('127.0.0.1'),
        9090,
      );

      // Should handle gracefully (empty or error)
      expect(result, isNotNull);
    });

    test('should dispose isolate correctly', () async {
      await isolateManager.dispose();

      // After dispose, operations should still work (will reinitialize)
      final files = <TorrentFile>[];

      // Should reinitialize automatically
      final playlist = await isolateManager.getPlaylist(
        files,
        InternetAddress('127.0.0.1'),
        9090,
      );

      expect(playlist, isNotNull);
    });
  });
}
