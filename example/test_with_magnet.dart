import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_tracker/dtorrent_tracker.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// Test script for issue #4 using magnet link
/// This will download metadata first, then start the actual download
void main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('[${record.level.name}] ${record.message}');
  });

  String? magnetUri;
  
  if (args.isNotEmpty) {
    magnetUri = args[0];
  } else {
    print('Usage: dart run example/test_with_magnet.dart <magnet_uri>');
    print('');
    print('Example:');
    print('  dart run example/test_with_magnet.dart "magnet:?xt=urn:btih:..."');
    exit(1);
  }

  if (!magnetUri.startsWith('magnet:')) {
    print('ERROR: Invalid magnet URI. Must start with "magnet:"');
    exit(1);
  }

  final savePath = path.join(Directory.current.path, 'tmp');
  await Directory(savePath).create(recursive: true);

  print('=' * 60);
  print('Testing Issue #4 Fix with Magnet Link');
  print('=' * 60);
  print('Magnet: $magnetUri');
  print('Save path: $savePath');
  print('');

  try {
    // Parse magnet link
    final magnet = MagnetParser.parse(magnetUri);
    if (magnet == null) {
      print('ERROR: Failed to parse magnet URI');
      exit(1);
    }

    print('Parsed magnet link:');
    print('  Info hash: ${magnet.infoHashString}');
    print('  Name: ${magnet.displayName ?? "Unknown"}');
    print('  Trackers: ${magnet.trackers.length}');
    print('');

    // Create metadata downloader
    final metadata = MetadataDownloader.fromMagnet(magnetUri);
    final metadataListener = metadata.createListener();

    print('Starting metadata download...');
    metadata.startDownload();

    // Use public trackers to help find peers
    final tracker = TorrentAnnounceTracker(metadata);
    final trackerListener = tracker.createListener();
    // Convert hex string to bytes
    final hexStr = magnet.infoHashString;
    final infoHashBuffer = Uint8List.fromList(
      List.generate(hexStr.length ~/ 2, (i) {
        final s = hexStr.substring(i * 2, i * 2 + 2);
        return int.parse(s, radix: 16);
      }),
    );

    // Add peers from tracker
    trackerListener.on<AnnouncePeerEventEvent>((event) {
      if (event.event == null) return;
      final peers = event.event!.peers;
      for (var peer in peers) {
        metadata.addNewPeerAddress(peer, PeerSource.tracker);
      }
    });

    // Use public trackers
    findPublicTrackers().listen((announceUrls) {
      for (var url in announceUrls) {
        tracker.runTracker(url, infoHashBuffer);
      }
    });

    // Wait for metadata
    print('Waiting for metadata download...');
    final metadataCompleter = Completer<Uint8List>();
    
    metadataListener
      ..on<MetaDataDownloadProgress>((event) {
        print('Metadata progress: ${(event.progress * 100).toStringAsFixed(1)}%');
      })
      ..on<MetaDataDownloadComplete>((event) {
        if (!metadataCompleter.isCompleted) {
          metadataCompleter.complete(Uint8List.fromList(event.data));
        }
      });

    final metadataBytes = await metadataCompleter.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        print('ERROR: Metadata download timeout');
        exit(1);
      },
    );

    print('✓ Metadata downloaded!');
    tracker.stop(true);

    // Parse torrent from metadata
    final msg = decode(metadataBytes);
    final torrentMap = <String, dynamic>{'info': msg};
    final torrentModel = parseTorrentFileContent(torrentMap);
    
    if (torrentModel == null) {
      print('ERROR: Failed to parse torrent from metadata');
      exit(1);
    }

    print('Torrent: ${torrentModel.name}');
    print('Size: ${(torrentModel.length / 1024 / 1024).toStringAsFixed(2)} MB');
    print('Pieces: ${torrentModel.pieces.length}');
    print('');

    // Now start the actual download
    final task = TorrentTask.newTask(torrentModel, savePath);

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
        final downloaded = task.downloaded ?? 0;
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

    print('Starting download...');
    await task.start();
    print('');

    // Add DHT nodes
    for (var node in torrentModel.nodes) {
      task.addDHTNode(node);
    }

    // Monitor progress
    final timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      final downloaded = task.downloaded ?? 0;
      final progress = task.progress * 100;
      final connectedPeers = task.connectedPeersNumber;
      final allPeers = task.allPeersNumber;
      final downloadSpeed =
          ((task.currentDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);

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
      final activePeers = task.activePeers;
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

    // Run for 3 minutes
    await Future.delayed(const Duration(minutes: 3));
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
      if (firstPeerConnected != null && firstDataReceived != null) {
        final delay = firstDataReceived!.difference(firstPeerConnected!).inSeconds;
        print('✓ Data started ${delay}s after first peer connection');
      }
    } else if (finalConnected >= 12) {
      print('✗ FAILURE: 12+ peers but no download - bug may still exist');
    } else {
      print('⚠ INCONCLUSIVE: Need 12+ peers to test');
    }
    print('=' * 60);

    await task.stop();
    await task.dispose();
    await metadata.stop();
  } catch (e, stackTrace) {
    print('');
    print('ERROR: $e');
    print('Stack trace: $stackTrace');
    exit(1);
  }
}

