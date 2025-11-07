import 'dart:io';
import 'package:test/test.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

// Helper function to check if error is a port conflict
bool _isPortConflict(dynamic e) {
  // Check if it's a SocketException
  if (e is SocketException) {
    return e.message.contains('Address already in use') ||
        e.osError?.errorCode == 48;
  }
  // Check error string representation
  final str = e.toString();
  return str.contains('Address already in use') ||
      str.contains('errno = 48') ||
      str.contains('port = 6771') ||
      str.contains('Failed to create datagram socket');
}

// Note: These tests may need to run with --concurrency=1 to avoid port conflicts
// when running with other tests that use LSD (port 6771)
void main() {
  group('Web Seeding Integration Tests', () {
    late Torrent mockTorrent;
    late File tempFile;
    late String savePath;
    late TorrentTask task;

    setUp(() async {
      // Create a temporary file for testing
      tempFile = File(
          '${Directory.systemTemp.path}/test_file_${DateTime.now().millisecondsSinceEpoch}.dat');
      await tempFile
          .writeAsBytes(List<int>.generate(16384 * 10, (i) => i % 256));

      // Create a torrent from the file
      final options = TorrentCreationOptions(
        pieceLength: 16384,
        trackers: [],
      );
      mockTorrent = await TorrentCreator.createTorrent(tempFile.path, options);

      // Create save directory
      savePath =
          '${Directory.systemTemp.path}/test_download_${DateTime.now().millisecondsSinceEpoch}';
      await Directory(savePath).create(recursive: true);
    });

    tearDown(() async {
      try {
        if (task.state.toString().contains('running') ||
            task.state.toString().contains('paused')) {
          await task.stop();
        }
        await task.dispose();
        // Wait a bit for ports to be released
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        // Ignore disposal errors
      }
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        // Ignore
      }
      try {
        if (await Directory(savePath).exists()) {
          await Directory(savePath).delete(recursive: true);
        }
      } catch (e) {
        // Ignore
      }
    });

    test('should create task with web seeds', () {
      final webSeeds = [
        Uri.parse('http://webseed1.example.com/file'),
        Uri.parse('http://webseed2.example.com/file'),
      ];

      task = TorrentTask.newTask(mockTorrent, savePath, false, webSeeds, null);

      expect(task, isNotNull);
      expect(task.metaInfo, equals(mockTorrent));
    });

    test('should create task with acceptable sources', () {
      final acceptableSources = [
        Uri.parse('http://source1.example.com/file'),
        Uri.parse('http://source2.example.com/file'),
      ];

      task = TorrentTask.newTask(
          mockTorrent, savePath, false, null, acceptableSources);

      expect(task, isNotNull);
      expect(task.metaInfo, equals(mockTorrent));
    });

    test('should create task with both web seeds and acceptable sources', () {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];
      final acceptableSources = [Uri.parse('http://source.example.com/file')];

      task = TorrentTask.newTask(
          mockTorrent, savePath, false, webSeeds, acceptableSources);

      expect(task, isNotNull);
      expect(task.metaInfo, equals(mockTorrent));
    });

    test('should create task without web seeds', () {
      task = TorrentTask.newTask(mockTorrent, savePath);

      expect(task, isNotNull);
      expect(task.metaInfo, equals(mockTorrent));
    });

    test('should initialize task with web seeds', () async {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];

      task = TorrentTask.newTask(mockTorrent, savePath, false, webSeeds, null);

      // Start task to initialize web seed downloader
      try {
        await task.start();
      } catch (e) {
        // Ignore port conflicts in tests (LSD port 6771 may be in use)
        if (_isPortConflict(e)) {
          return; // Skip this test if port is in use
        }
        rethrow;
      }

      // Wait for initialization
      await Future.delayed(const Duration(milliseconds: 200));

      // Task should be initialized
      expect(task.state, isNotNull);
      expect(task.fileManager, isNotNull);
      expect(task.pieceManager, isNotNull);
    });

    test('should handle applySelectedFiles with web seeds', () async {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];

      task = TorrentTask.newTask(mockTorrent, savePath, false, webSeeds, null);

      try {
        await task.start();
      } catch (e) {
        // Ignore port conflicts in tests (LSD port 6771 may be in use)
        if (_isPortConflict(e)) {
          return; // Skip this test if port is in use
        }
        rethrow;
      }
      await Future.delayed(const Duration(milliseconds: 200));

      // Apply selected files should work even with web seeds
      if (mockTorrent.files.isNotEmpty) {
        task.applySelectedFiles([0]);
        // Should not throw
        expect(task, isNotNull);
      }
    });

    test('should dispose task with web seeds properly', () async {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];

      task = TorrentTask.newTask(mockTorrent, savePath, false, webSeeds, null);

      try {
        await task.start();
      } catch (e) {
        // Ignore port conflicts in tests (LSD port 6771 may be in use)
        if (_isPortConflict(e)) {
          return; // Skip this test if port is in use
        }
        rethrow;
      }
      await Future.delayed(const Duration(milliseconds: 200));

      // Dispose should work without errors
      await task.dispose();
      expect(task.state, isNotNull);
    });

    test('should handle task with both web seeds and acceptable sources',
        () async {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];
      final acceptableSources = [Uri.parse('http://source.example.com/file')];

      task = TorrentTask.newTask(
          mockTorrent, savePath, false, webSeeds, acceptableSources);

      try {
        await task.start();
      } catch (e) {
        // Ignore port conflicts in tests (LSD port 6771 may be in use)
        if (_isPortConflict(e)) {
          return; // Skip this test if port is in use
        }
        rethrow;
      }
      await Future.delayed(const Duration(milliseconds: 200));

      expect(task, isNotNull);
      expect(task.fileManager, isNotNull);
      expect(task.pieceManager, isNotNull);

      await task.dispose();
    });

    test('should handle task pause and resume with web seeds', () async {
      final webSeeds = [Uri.parse('http://webseed.example.com/file')];

      task = TorrentTask.newTask(mockTorrent, savePath, false, webSeeds, null);

      try {
        await task.start();
      } catch (e) {
        // Ignore port conflicts in tests (LSD port 6771 may be in use)
        if (_isPortConflict(e)) {
          return; // Skip this test if port is in use
        }
        rethrow;
      }
      await Future.delayed(const Duration(milliseconds: 200));

      task.pause();
      expect(task.state.toString(), contains('paused'));

      task.resume();
      expect(task.state.toString(), contains('running'));

      await task.dispose();
    });
  });
}
