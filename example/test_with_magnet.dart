import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_tracker/dtorrent_tracker.dart';
import 'package:events_emitter2/events_emitter2.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// Test script for issue #4 using magnet link
/// This will download metadata first, then start the actual download
void main(List<String> args) async {
  // Reduce logging noise
  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen((record) {
    // Only show warnings and errors
    if (record.level >= Level.WARNING) {
      // Filter out warnings about disposed emitters - these are harmless
      // and occur when tracker async operations complete after dispose
      if (record.message.contains('failed to emit event') &&
          record.message.contains('disposed emitter')) {
        return; // Skip these warnings
      }
      print('[${record.level.name}] ${record.message}');
    }
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

  // Declare tracker variables at function scope so they're accessible in catch blocks
  TorrentAnnounceTracker? tracker;
  StreamSubscription? trackerSubscription;
  EventsListener? trackerListener;
  bool trackerDisposed = false;

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
    if (magnet.trackerTiers.isNotEmpty) {
      print('  Tracker tiers: ${magnet.trackerTiers.length}');
    }
    if (magnet.webSeeds.isNotEmpty) {
      print('  Web seeds: ${magnet.webSeeds.length}');
    }
    if (magnet.acceptableSources.isNotEmpty) {
      print('  Acceptable sources: ${magnet.acceptableSources.length}');
    }
    if (magnet.selectedFileIndices != null &&
        magnet.selectedFileIndices!.isNotEmpty) {
      print(
          '  Selected files (BEP 0053): ${magnet.selectedFileIndices!.join(", ")}');
    }
    print('');

    // Create metadata downloader
    final metadata = MetadataDownloader.fromMagnet(magnetUri);
    final metadataListener = metadata.createListener();

    print('Starting metadata download...');
    metadata.startDownload();

    try {
      tracker = TorrentAnnounceTracker(metadata);
      trackerListener = tracker.createListener();
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
        // Check if tracker is disposed before processing events
        if (trackerDisposed || tracker == null) return;
        if (event.event == null) return;
        final peers = event.event!.peers;
        print('Got ${peers.length} peer(s) from tracker');
        for (var peer in peers) {
          if (!trackerDisposed && tracker != null) {
            metadata.addNewPeerAddress(peer, PeerSource.tracker);
          }
        }
      });

      // First, use trackers from magnet link directly
      if (magnet.trackers.isNotEmpty) {
        print('Using ${magnet.trackers.length} tracker(s) from magnet link...');
        for (var trackerUrl in magnet.trackers) {
          try {
            tracker.runTracker(trackerUrl, infoHashBuffer);
            print('  → Announced to: $trackerUrl');
          } catch (e) {
            print('  ⚠ Failed to announce to $trackerUrl: $e');
          }
        }
      }

      // Also use public trackers as backup
      trackerSubscription = findPublicTrackers().timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          print(
              '⚠ Public trackers timeout, continuing with magnet trackers and DHT...');
          sink.close();
        },
      ).listen((announceUrls) {
        // Don't add trackers if already disposed
        if (trackerDisposed || tracker == null) return;
        print('Using ${announceUrls.length} public tracker(s)...');
        for (var url in announceUrls) {
          try {
            if (!trackerDisposed && tracker != null) {
              tracker!.runTracker(url, infoHashBuffer);
            }
          } catch (e) {
            // Ignore errors for public trackers
          }
        }
      });
    } catch (e) {
      print('⚠ Tracker setup failed: $e, continuing with DHT only...');
    }

    // Wait for metadata
    print('Waiting for metadata download (max 60 seconds)...');
    final metadataCompleter = Completer<Uint8List>();
    int lastProgress = 0;
    int peerCount = 0;

    // Monitor peer connections
    Timer.periodic(const Duration(seconds: 5), (timer) {
      final currentPeers = metadata.activePeers.length;
      if (currentPeers != peerCount) {
        peerCount = currentPeers;
        print('Connected peers: $peerCount');
      }
    });

    metadataListener
      ..on<MetaDataDownloadProgress>((event) {
        final progressPercent = (event.progress * 100).toInt();
        // Show progress when it changes
        if (progressPercent != lastProgress) {
          lastProgress = progressPercent;
          print('Metadata progress: $progressPercent%');
        }
      })
      ..on<MetaDataDownloadComplete>((event) {
        if (!metadataCompleter.isCompleted) {
          print('✓ Metadata download complete!');
          metadataCompleter.complete(Uint8List.fromList(event.data));
        }
      });

    Uint8List metadataBytes;
    try {
      metadataBytes = await metadataCompleter.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          print('');
          print('ERROR: Metadata download timeout after 60 seconds');
          print(
              'This may be normal if the torrent is not active or has no seeders.');
          print(
              'Try using a more popular torrent or provide a .torrent file instead.');
          // Set flag first to prevent new tracker operations
          trackerDisposed = true;
          trackerSubscription?.cancel();
          // Dispose listener first to stop receiving events
          trackerListener?.dispose();
          trackerListener = null;
          // Then dispose tracker (this will stop all async operations)
          tracker?.dispose();
          tracker = null;
          exit(1);
        },
      );
    } catch (e) {
      trackerDisposed = true;
      trackerSubscription?.cancel();
      trackerListener?.dispose();
      trackerListener = null;
      await tracker?.dispose();
      tracker = null;
      rethrow;
    }

    print('✓ Metadata downloaded!');
    // Set flag first to prevent new tracker operations
    trackerDisposed = true;
    trackerSubscription?.cancel();
    // Dispose listener first to stop receiving events
    trackerListener?.dispose();
    trackerListener = null;
    // Then dispose tracker (this will stop all async operations)
    await tracker?.dispose();
    tracker = null;

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
    print('Files: ${torrentModel.files.length}');
    print('');

    // Now start the actual download
    // Pass web seeds and acceptable sources from magnet link (BEP 0019)
    final task = TorrentTask.newTask(
      torrentModel,
      savePath,
      false, // stream
      magnet.webSeeds.isNotEmpty ? magnet.webSeeds : null,
      magnet.acceptableSources.isNotEmpty ? magnet.acceptableSources : null,
    );

    if (magnet.webSeeds.isNotEmpty || magnet.acceptableSources.isNotEmpty) {
      print('Web seeding enabled:');
      if (magnet.webSeeds.isNotEmpty) {
        print('  Web seeds: ${magnet.webSeeds.length}');
        for (var ws in magnet.webSeeds) {
          print('    - $ws');
        }
      }
      if (magnet.acceptableSources.isNotEmpty) {
        print('  Acceptable sources: ${magnet.acceptableSources.length}');
        for (var as in magnet.acceptableSources) {
          print('    - $as');
        }
      }
      print('');
    }

    // Apply selected files from magnet link (BEP 0053)
    if (magnet.selectedFileIndices != null &&
        magnet.selectedFileIndices!.isNotEmpty) {
      print(
          'Applying selected files from magnet link: ${magnet.selectedFileIndices!.join(", ")}');
      task.applySelectedFiles(magnet.selectedFileIndices!);
      print('');
    }

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
        print(
            '✓ Downloading: +${(downloadedDelta / 1024).toStringAsFixed(2)} KB');
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

    // Run for 1 minute (enough to test the fix)
    print('Running test for 1 minute...');
    print('Press Ctrl+C to stop early');
    print('');

    try {
      await Future.delayed(const Duration(minutes: 1));
    } catch (e) {
      // Handle interruption
    }
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
    print(
        'Downloaded: ${(finalDownloaded / 1024 / 1024).toStringAsFixed(2)} MB');
    print('Progress: ${(finalProgress * 100).toStringAsFixed(2)}%');

    if (hasReceivedData) {
      print('✓ SUCCESS: Data downloaded! Fix is working.');
      if (firstPeerConnected != null && firstDataReceived != null) {
        final delay =
            firstDataReceived!.difference(firstPeerConnected!).inSeconds;
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
    // Cleanup tracker resources
    trackerDisposed = true;
    trackerSubscription?.cancel();
    trackerListener?.dispose();
    trackerListener = null;
    await tracker?.dispose();
    tracker = null;
    await metadata.stop();
  } on TimeoutException catch (e) {
    print('');
    print('ERROR: Operation timed out: $e');
    print('This may be normal if the torrent is not active.');
    trackerDisposed = true;
    trackerSubscription?.cancel();
    trackerListener?.dispose();
    trackerListener = null;
    await tracker?.dispose();
    tracker = null;
    exit(1);
  } catch (e, stackTrace) {
    print('');
    print('ERROR: $e');
    if (e.toString().contains('disposed') ||
        e.toString().contains('cancelled')) {
      print('(This may be normal if the process was interrupted)');
    } else {
      print('Stack trace: $stackTrace');
    }
    trackerDisposed = true;
    trackerSubscription?.cancel();
    trackerListener?.dispose();
    trackerListener = null;
    await tracker?.dispose();
    tracker = null;
    exit(1);
  }
}
