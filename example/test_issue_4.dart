import 'dart:async';
import 'dart:io';

import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Test script for issue #4
/// Tests that downloads start when peers are connected
void main(List<String> args) async {
  final savePath = path.join(Directory.current.path, 'tmp');
  await Directory(savePath).create(recursive: true);

  print('=' * 60);
  print('Testing Issue #4 Fix');
  print('=' * 60);
  print('Save path: $savePath');
  print('');

  String? torrentPath;
  
  // Check if torrent path provided as argument
  if (args.isNotEmpty) {
    torrentPath = args[0];
  } else {
    // Try to find torrent in common locations
    final possiblePaths = [
      path.join(Directory.current.path, 'test.torrent'),
      path.join(Directory.current.path, 'tmp', 'test.torrent'),
      path.join(Directory.current.path, '..', 'torrents', 'big-buck-bunny.torrent'),
    ];
    
    for (final p in possiblePaths) {
      if (await File(p).exists()) {
        torrentPath = p;
        break;
      }
    }
  }

  if (torrentPath == null || !await File(torrentPath).exists()) {
    print('ERROR: Torrent file not found!');
    print('');
    print('Please provide a torrent file:');
    print('  dart run example/test_issue_4.dart path/to/torrent.torrent');
    print('');
    print('Or place a torrent file named "test.torrent" in the project root.');
    exit(1);
  }

  print('Using torrent: $torrentPath');
  print('');

  TorrentTask? task;

  try {
    // Parse torrent
    final model = await Torrent.parse(torrentPath);
    print('Torrent: ${model.name}');
    print('Size: ${(model.length / 1024 / 1024).toStringAsFixed(2)} MB');
    print('Pieces: ${model.pieces.length}');
    print('');

    // Create task
    task = TorrentTask.newTask(model, savePath);

    // Track metrics
    int lastDownloaded = 0;
    int lastConnectedPeers = 0;
    DateTime? firstDataReceived;
    DateTime? firstPeerConnected;
    bool hasReceivedData = false;

    // Monitor events
    final listener = task.createListener();
    listener
      ..on<TaskStarted>((event) {
        print('✓ Task started');
      })
      ..on<TaskCompleted>((event) {
        print('');
        print('🎉 Download completed!');
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
    await task.start();
    print('');

    // Add DHT nodes
    for (var node in model.nodes) {
      task.addDHTNode(node);
    }

    // Monitor progress
    final timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final downloaded = task?.downloaded ?? 0;
      final progress = (task?.progress ?? 0) * 100;
      final connectedPeers = task?.connectedPeersNumber ?? 0;
      final allPeers = task?.allPeersNumber ?? 0;
      final downloadSpeed =
          ((task?.currentDownloadSpeed ?? 0) * 1000 / 1024).toStringAsFixed(2);

      // Track first peer
      if (connectedPeers > 0 && firstPeerConnected == null) {
        firstPeerConnected = DateTime.now();
        print('✓ First peer connected at $firstPeerConnected');
      }

      final downloadedDelta = downloaded - lastDownloaded;
      final peersDelta = connectedPeers - lastConnectedPeers;

      print('─' * 60);
      print('Progress: ${progress.toStringAsFixed(2)}% | '
          'Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB | '
          'Peers: $connectedPeers/$allPeers | '
          'Speed: $downloadSpeed KB/s');

      if (downloadedDelta > 0) {
        print('✓ Downloading: +${(downloadedDelta / 1024).toStringAsFixed(2)} KB');
      } else if (connectedPeers > 0) {
        if (peersDelta > 0) {
          print('  +$peersDelta new peer(s)');
        }
        if (connectedPeers >= 12 && downloadedDelta == 0 && !hasReceivedData) {
          print('');
          print('⚠⚠⚠ ISSUE REPRODUCED: 12+ peers but no download!');
          print('');
        }
      }

      lastDownloaded = downloaded;
      lastConnectedPeers = connectedPeers;

      // Check active peers
      final activePeers = task?.activePeers;
      if (activePeers != null) {
        var downloadingCount = 0;
        for (var peer in activePeers) {
          if (peer.isDownloading) {
            downloadingCount++;
          }
        }
        if (downloadingCount > 0) {
          print('  → $downloadingCount peer(s) downloading');
        }
      }
    });

    // Run for 2 minutes
    await Future.delayed(const Duration(minutes: 2));
    timer.cancel();

    // Summary
    print('');
    print('=' * 60);
    print('TEST SUMMARY');
    print('=' * 60);
    final finalConnected = task.connectedPeersNumber;
    final finalAll = task.allPeersNumber;
    final finalDownloaded = task.downloaded ?? 0;
    final finalProgress = task.progress;
    
    print('Connected peers: $finalConnected');
    print('Total peers: $finalAll');
    print('Downloaded: ${(finalDownloaded / 1024 / 1024).toStringAsFixed(2)} MB');
    print('Progress: ${(finalProgress * 100).toStringAsFixed(2)}%');

    if (hasReceivedData) {
      print('✓ SUCCESS: Data downloaded! Fix is working.');
    } else if (finalConnected >= 12) {
      print('✗ FAILURE: 12+ peers but no download - bug may still exist');
    } else {
      print('⚠ INCONCLUSIVE: Need 12+ peers to test');
    }
    print('=' * 60);

    await task.stop();
    await task.dispose();
  } catch (e, stackTrace) {
    print('');
    print('ERROR: $e');
    print('Stack trace: $stackTrace');
    await task?.stop();
    await task?.dispose();
    exit(1);
  }
}

