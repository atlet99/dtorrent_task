import 'dart:io';

import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/torrent/torrent_creator.dart';

void main() {
  group('TorrentCreator Tests', () {
    late File testFile;
    late Directory testDir;

    setUp(() async {
      // Create a test file
      testFile = File(
          '${Directory.systemTemp.path}/test_file_${DateTime.now().millisecondsSinceEpoch}.dat');
      await testFile
          .writeAsBytes(List<int>.generate(1024 * 100, (i) => i % 256));

      // Create a test directory
      testDir = Directory(
          '${Directory.systemTemp.path}/test_dir_${DateTime.now().millisecondsSinceEpoch}');
      await testDir.create();

      // Add a file to the directory
      final file1 = File('${testDir.path}/file1.txt');
      await file1.writeAsString('Test content 1');

      final file2 = File('${testDir.path}/file2.txt');
      await file2.writeAsString('Test content 2');
    });

    tearDown(() async {
      if (await testFile.exists()) {
        await testFile.delete();
      }
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('should create torrent for single file', () async {
      final options = TorrentCreationOptions(
        pieceLength: 16384,
        trackers: [Uri.parse('http://tracker.example.com')],
        comment: 'Test torrent',
        createdBy: 'Test Creator',
      );

      final torrent =
          await TorrentCreator.createTorrent(testFile.path, options);

      expect(torrent, isNotNull);
      expect(torrent.name,
          equals(testFile.path.split(Platform.pathSeparator).last));
      expect(torrent.pieceLength, equals(16384));
      expect(torrent.length, equals(1024 * 100));
    });

    test('should create torrent for directory', () async {
      final options = TorrentCreationOptions(
        pieceLength: 16384,
        trackers: [Uri.parse('http://tracker.example.com')],
      );

      final torrent = await TorrentCreator.createTorrent(testDir.path, options);

      expect(torrent, isNotNull);
      expect(torrent.files.length, equals(2));
    });

    test('should create private torrent', () async {
      final options = TorrentCreationOptions(
        pieceLength: 16384,
        isPrivate: true,
        source: 'private-tracker',
      );

      final torrent =
          await TorrentCreator.createTorrent(testFile.path, options);

      expect(torrent, isNotNull);
      // Note: Private flag is stored in info dict, may need to check torrent structure
    });

    test('should handle multiple trackers', () async {
      final options = TorrentCreationOptions(
        pieceLength: 16384,
        trackers: [
          Uri.parse('http://tracker1.example.com'),
          Uri.parse('http://tracker2.example.com'),
          Uri.parse('udp://tracker3.example.com:1337'),
        ],
      );

      final torrent =
          await TorrentCreator.createTorrent(testFile.path, options);

      expect(torrent, isNotNull);
      expect(torrent.announces.length, greaterThanOrEqualTo(1));
    });

    test('should throw error for non-existent path', () async {
      final options = TorrentCreationOptions();

      expect(
        () => TorrentCreator.createTorrent('/non/existent/path', options),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw error for empty directory', () async {
      final emptyDir = Directory(
          '${Directory.systemTemp.path}/empty_dir_${DateTime.now().millisecondsSinceEpoch}');
      await emptyDir.create();

      final options = TorrentCreationOptions();

      expect(
        () => TorrentCreator.createTorrent(emptyDir.path, options),
        throwsA(isA<ArgumentError>()),
      );

      await emptyDir.delete();
    });
  });
}
