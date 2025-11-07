import 'dart:async';
import 'dart:io';

import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Test script to verify the fix for issue #4
/// This script monitors peer connections and verifies that downloads start
/// after peers are connected and bitfields are received.
///
/// Usage:
///   dart run example/test_download_fix.dart path/to/torrent.torrent
void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run example/test_download_fix.dart <torrent_file_path>');
    print('');
    print('Example:');
    print('  dart run example/test_download_fix.dart path/to/torrent.torrent');
    exit(1);
  }

  final torrentPath = args[0];
  final savePath = path.join(
    Directory.current.path,
    'test_download_${DateTime.now().millisecondsSinceEpoch}',
  );
  await Directory(savePath).create(recursive: true);

  print('=' * 60);
  print('Testing download fix for issue #4');
  print('=' * 60);
  print('Torrent file: $torrentPath');
  print('Save path: $savePath');
  print('');

  TorrentTask? task;

  try {
    // Parse torrent
    print('Parsing torrent file...');
    final model = await Torrent.parse(torrentPath);
    print('Torrent name: ${model.name}');
    print('Total size: ${(model.length / 1024 / 1024).toStringAsFixed(2)} MB');
    print('Pieces: ${model.pieces.length}');
    print('');

    // Create task
    task = TorrentTask.newTask(model, savePath);

    // Track key metrics
    int lastDownloaded = 0;
    int lastConnectedPeers = 0;
    DateTime? firstDataReceived;
    DateTime? firstPeerConnected;
    bool hasReceivedData = false;

    // Monitor task events
    final listener = task.createListener();
    listener
      ..on<TaskStarted>((event) {
        print('✓ Task started');
      })
      ..on<TaskCompleted>((event) {
        print('');
        print('🎉 Download completed!');
        if (firstPeerConnected != null) {
          final totalTime =
              DateTime.now().difference(firstPeerConnected!).inSeconds;
          print('Total time: ${totalTime}s');
        }
      })
      ..on<StateFileUpdated>((event) {
        final downloaded = task?.downloaded ?? 0;
        if (downloaded > lastDownloaded && !hasReceivedData) {
          hasReceivedData = true;
          firstDataReceived = DateTime.now();
          final timeSinceConnection = firstPeerConnected != null
              ? firstDataReceived!.difference(firstPeerConnected!).inSeconds
              : 0;
          print('');
          print('🎉 FIRST DATA RECEIVED!');
          print('   Downloaded: ${(downloaded / 1024).toStringAsFixed(2)} KB');
          print('   Time since first peer: ${timeSinceConnection}s');
          print('');
        }
      });

    // Start task
    print('Starting download...');
    final startMap = await task.start();
    print('Task started: $startMap');
    print('');

    // Add DHT nodes if available
    for (var node in model.nodes) {
      task.addDHTNode(node);
    }

    // Monitor progress
    final timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      final downloaded = task?.downloaded ?? 0;
      final progress = (task?.progress ?? 0) * 100;
      final connectedPeers = task?.connectedPeersNumber ?? 0;
      final allPeers = task?.allPeersNumber ?? 0;
      final downloadSpeed =
          ((task?.currentDownloadSpeed ?? 0) * 1000 / 1024).toStringAsFixed(2);

      // Track first peer connection
      if (connectedPeers > 0 && firstPeerConnected == null) {
        firstPeerConnected = DateTime.now();
        print('✓ First peer connected at $firstPeerConnected');
      }

      // Check if we're making progress
      final downloadedDelta = downloaded - lastDownloaded;
      final peersDelta = connectedPeers - lastConnectedPeers;

      print('─' * 60);
      print('Progress: ${progress.toStringAsFixed(2)}%');
      print('Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB');
      print('Peers: $connectedPeers connected, $allPeers total');
      print('Download speed: $downloadSpeed KB/s');

      if (downloadedDelta > 0) {
        print(
            '✓ Downloading: +${(downloadedDelta / 1024).toStringAsFixed(2)} KB');
      } else if (connectedPeers > 0) {
        if (peersDelta > 0) {
          print('  New peers connected (+$peersDelta)');
        }
        if (connectedPeers >= 12 && downloadedDelta == 0 && !hasReceivedData) {
          print('');
          print('⚠⚠⚠ ISSUE REPRODUCED: 12+ peers connected but no download!');
          print('   This indicates the bug is NOT fixed.');
          print('');
        } else if (connectedPeers >= 12 && !hasReceivedData) {
          print('  Waiting for data from $connectedPeers peers...');
        }
      }

      lastDownloaded = downloaded;
      lastConnectedPeers = connectedPeers;

      // Check active peers for request status
      final activePeers = task?.activePeers;
      if (activePeers != null && activePeers.isNotEmpty) {
        var downloadingCount = 0;
        for (var peer in activePeers) {
          if (peer.isDownloading) {
            downloadingCount++;
          }
        }
        if (downloadingCount > 0) {
          print('  → $downloadingCount peer(s) actively downloading');
        }
      }
    });

    // Run for 2 minutes or until completion
    final completedCompleter = Completer<void>();
    listener.on<TaskCompleted>((event) {
      if (!completedCompleter.isCompleted) {
        completedCompleter.complete();
      }
    });

    await Future.any([
      Future.delayed(const Duration(minutes: 2)),
      completedCompleter.future,
    ]);

    timer.cancel();

    // Final summary
    print('');
    print('=' * 60);
    print('TEST SUMMARY');
    print('=' * 60);
    final connectedPeersFinal = task.connectedPeersNumber;
    final allPeersFinal = task.allPeersNumber;
    final finalDownloaded = task.downloaded ?? 0;
    final finalProgress = task.progress;
    print('Connected peers: $connectedPeersFinal');
    print('Total peers: $allPeersFinal');
    print(
        'Downloaded: ${(finalDownloaded / 1024 / 1024).toStringAsFixed(2)} MB');
    print('Progress: ${(finalProgress * 100).toStringAsFixed(2)}%');

    if (hasReceivedData) {
      print('✓ SUCCESS: Data was downloaded!');
      print('✓ The fix appears to be working.');
      if (firstPeerConnected != null && firstDataReceived != null) {
        final delay =
            firstDataReceived!.difference(firstPeerConnected!).inSeconds;
        print(
            '✓ Data started downloading ${delay}s after first peer connection');
      }
    } else {
      if (connectedPeersFinal >= 12) {
        print('✗ FAILURE: Connected to 12+ peers but no data downloaded');
        print('✗ The bug may still be present.');
      } else {
        print('⚠ INCONCLUSIVE: Not enough peers connected to test');
        print('   (Need at least 12 peers to reproduce the original issue)');
      }
    }
    print('=' * 60);

    // Cleanup
    await task.stop();
    await task.dispose();

    // Optionally clean up download directory
    print('');
    print('Download saved to: $savePath');
    print('To clean up, run: rm -rf $savePath');
  } catch (e, stackTrace) {
    print('');
    print('ERROR: $e');
    if (e is! FileSystemException || e.message.contains('No such file')) {
      print('Stack trace: $stackTrace');
    }
    await task?.stop();
    await task?.dispose();
    exit(1);
  }
}
