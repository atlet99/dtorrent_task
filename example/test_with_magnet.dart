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

/// Comprehensive test script for magnet link downloads
/// This will download metadata first, then start the actual download
/// Provides detailed diagnostics and monitoring for testing release readiness
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
    print('');
    print('Test magnet:');
    print(
        '  dart run example/test_with_magnet.dart "magnet:?xt=urn:btih:6BE701C4B7B0C5F5F36799342DFF1250DE936BE2&dn=Nineteen+Eighty-Four+%281984%29+by+George+Orwell+EPUB&tr=http%3A%2F%2Fp4p.arenabg.com%3A1337%2Fannounce&tr=udp%3A%2F%2F47.ip-51-68-199.eu%3A6969%2Fannounce&tr=udp%3A%2F%2F9.rarbg.me%3A2780%2Fannounce&tr=udp%3A%2F%2F9.rarbg.to%3A2710%2Fannounce&tr=udp%3A%2F%2F9.rarbg.to%3A2730%2Fannounce&tr=udp%3A%2F%2F9.rarbg.to%3A2920%2Fannounce&tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce&tr=udp%3A%2F%2Fopentracker.i2p.rocks%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.cyberia.is%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.dler.org%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.internetwarriors.net%3A1337%2Fannounce&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.openbittorrent.com%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=udp%3A%2F%2Ftracker.pirateparty.gr%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.tiny-vps.com%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.torrent.eu.org%3A451%2Fannounce"');
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

    // Track peer connection statistics
    int connectionSuccesses = 0;
    int connectionAttempts = 0; // Track connection attempts
    int totalTrackerPeers = 0;
    final Set<String> connectedPeerAddresses = {};
    final Set<String> attemptedPeerAddresses =
        {}; // Track all peers we tried to connect to
    final Map<String, String> peerDisconnectReasons =
        {}; // Track why peers disconnect
    DateTime? firstConnectionAttempt;

    // Blacklist for peers that failed (disconnected quickly or with errors)
    // This helps avoid wasting time on peers that don't work
    final Set<String> failedPeerBlacklist = {};
    final Map<String, int> peerFailureCount =
        {}; // Track how many times a peer failed
    final Map<String, DateTime> peerFirstFailureTime =
        {}; // Track when peer first failed
    final Map<String, DateTime> peerConnectionTime =
        {}; // Track when peer connected

    print('Starting metadata download...');
    print(
        'DHT is enabled for peer discovery (handled internally by MetadataDownloader)');
    print(
        'Note: MetadataDownloader automatically announces to trackers from magnet link');

    // Helper function to filter and add peers
    // Only filter out clearly invalid data (port 0, invalid addresses)
    // Don't filter by port number - BitTorrent peers can use any port
    // Also filter out peers that have failed multiple times (blacklist)
    void filterAndAddPeers(List<CompactAddress> peers, String source) {
      int filteredByAddress = 0;
      int filteredByPort = 0;
      int filteredByBlacklist = 0;

      int validPeers = 0;
      final Set<int> seenPorts = {};

      for (var peer in peers) {
        final peerAddr = '${peer.address.address}:${peer.port}';

        // Filter out port 0 (invalid port from tracker)
        if (peer.port == 0) {
          filteredByPort++;
          continue;
        }
        // Filter out invalid addresses (loopback, link-local, multicast)
        if (peer.address.isLoopback ||
            peer.address.isLinkLocal ||
            peer.address.isMulticast) {
          filteredByAddress++;
          continue;
        }
        // Filter out peers that have failed multiple times (blacklist)
        // Remove from blacklist after 5 minutes to allow retry
        if (failedPeerBlacklist.contains(peerAddr)) {
          final firstFailure = peerFirstFailureTime[peerAddr];
          if (firstFailure != null) {
            final timeSinceFailure = DateTime.now().difference(firstFailure);
            if (timeSinceFailure.inMinutes >= 5) {
              // Remove from blacklist after 5 minutes
              failedPeerBlacklist.remove(peerAddr);
              peerFailureCount.remove(peerAddr);
              peerFirstFailureTime.remove(peerAddr);
            } else {
              filteredByBlacklist++;
              continue;
            }
          } else {
            // No timestamp, remove from blacklist anyway
            failedPeerBlacklist.remove(peerAddr);
          }
        }
        // Accept all other peers - let the BitTorrent client determine if they're valid
        validPeers++;
        seenPorts.add(peer.port);
        attemptedPeerAddresses.add(peerAddr);
        firstConnectionAttempt ??= DateTime.now();
        connectionAttempts++;
        metadata.addNewPeerAddress(peer, PeerSource.tracker);
      }

      totalTrackerPeers += validPeers;
      if (validPeers > 0 ||
          filteredByAddress > 0 ||
          filteredByPort > 0 ||
          filteredByBlacklist > 0) {
        var msg = 'Got ${peers.length} peer(s) from $source';
        if (validPeers < peers.length) {
          final filtered = peers.length - validPeers;
          var filterDetails = [];
          if (filteredByPort > 0) {
            filterDetails.add('$filteredByPort port 0');
          }
          if (filteredByAddress > 0) {
            filterDetails.add('$filteredByAddress invalid addresses');
          }
          if (filteredByBlacklist > 0) {
            filterDetails
                .add('$filteredByBlacklist failed peers (blacklisted)');
          }
          msg +=
              ' ($validPeers valid, $filtered filtered: ${filterDetails.join(", ")})';
        }
        if (validPeers > 0 && seenPorts.length <= 5) {
          msg += ' [ports: ${seenPorts.toList()..sort()}]';
        } else if (validPeers > 0) {
          final sortedPorts = seenPorts.toList()..sort();
          msg +=
              ' [ports: ${sortedPorts.take(5).join(", ")}... (${seenPorts.length} unique)]';
        }
        msg += ' (total valid: $totalTrackerPeers)';
        print(msg);
      }
    }

    // Start download - MetadataDownloader will automatically announce to trackers from magnet link
    metadata.startDownload();

    // Create additional tracker ONLY for public trackers (not for magnet trackers)
    // This allows us to filter peers from public trackers
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

      // Listen for peers from public trackers only
      trackerListener.on<AnnouncePeerEventEvent>((event) {
        if (trackerDisposed || tracker == null) return;
        if (event.event == null) return;
        final peers = event.event!.peers;
        if (peers.isNotEmpty) {
          filterAndAddPeers(peers.toList(), 'public tracker');
        }
      });

      // Use public trackers as backup (magnet trackers are handled by MetadataDownloader)
      trackerSubscription = findPublicTrackers().timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          print(
              '⚠ Public trackers timeout, continuing with magnet trackers and DHT...');
          sink.close();
        },
      ).listen((announceUrls) {
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
      print(
          '⚠ Public tracker setup failed: $e, continuing with magnet trackers and DHT...');
    }

    // Wait for metadata
    print('Waiting for metadata download (max 180 seconds)...');
    print('Note: Metadata download may take time if torrent is not active');
    print('      Some peers may need time to respond to metadata requests');
    print('');
    final metadataCompleter = Completer<Uint8List>();
    int lastProgress = 0;
    int peerCount = 0;

    // Monitor peer connections and track statistics
    int lastActivePeersCount = 0;
    final Set<String> lastActivePeerAddresses = {};

    Timer.periodic(const Duration(seconds: 5), (timer) {
      final currentPeers = metadata.activePeers;
      final currentPeersCount = currentPeers.length;

      // Track new connections and count DHT peers
      final currentPeerAddresses = currentPeers
          .map((p) => '${p.address.address}:${p.address.port}')
          .toSet();

      // Count DHT peers by checking peer source (if available through address tracking)
      // Note: We can't directly access peer.source, but DHT is handled internally

      // Find newly connected peers
      final newlyConnected =
          currentPeerAddresses.difference(lastActivePeerAddresses);
      if (newlyConnected.isNotEmpty) {
        connectionSuccesses += newlyConnected.length;
        for (var addr in newlyConnected) {
          connectedPeerAddresses.add(addr);
          peerConnectionTime[addr] = DateTime.now(); // Track connection time
          print('  ✓ Peer connected: $addr');
        }
      }

      // Find disconnected peers
      final disconnected =
          lastActivePeerAddresses.difference(currentPeerAddresses);
      if (disconnected.isNotEmpty && lastActivePeersCount > 0) {
        for (var addr in disconnected) {
          final reason = peerDisconnectReasons[addr] ?? 'unknown reason';
          print('  ✗ Peer disconnected: $addr ($reason)');

          // Check if peer disconnected too quickly (less than 10 seconds)
          // This indicates the peer is not working properly
          final connectionTime = peerConnectionTime[addr];
          if (connectionTime != null) {
            final connectionDuration =
                DateTime.now().difference(connectionTime);
            if (connectionDuration.inSeconds < 10) {
              // Peer disconnected too quickly - add to blacklist
              final failureCount = (peerFailureCount[addr] ?? 0) + 1;
              peerFailureCount[addr] = failureCount;

              if (failureCount >= 2) {
                // After 2 failures, add to blacklist
                if (!failedPeerBlacklist.contains(addr)) {
                  failedPeerBlacklist.add(addr);
                  peerFirstFailureTime[addr] = DateTime.now();
                  print(
                      '  ⚠ Peer $addr added to blacklist (failed $failureCount times, disconnected after ${connectionDuration.inSeconds}s)');
                }
              }
            }
          }

          peerDisconnectReasons.remove(addr);
          peerConnectionTime.remove(addr);
        }
      }

      if (currentPeersCount != peerCount) {
        peerCount = currentPeersCount;
        print('Connected metadata peers: $peerCount');
      }

      lastActivePeersCount = currentPeersCount;
      lastActivePeerAddresses.clear();
      lastActivePeerAddresses.addAll(currentPeerAddresses);

      // Show statistics
      if (totalTrackerPeers > 0 || connectionAttempts > 0) {
        final connectionRate = connectionAttempts > 0
            ? (connectionSuccesses / connectionAttempts * 100)
                .toStringAsFixed(1)
            : '0.0';
        print(
            '  Stats: $connectionSuccesses/$connectionAttempts connected ($connectionRate%), $totalTrackerPeers valid peers from trackers');
        if (connectionAttempts > 0 && connectionSuccesses == 0) {
          final timeSinceFirstAttempt = firstConnectionAttempt != null
              ? DateTime.now().difference(firstConnectionAttempt!).inSeconds
              : 0;
          if (timeSinceFirstAttempt > 30) {
            print(
                '  ⚠ No connections after ${timeSinceFirstAttempt}s - peers may be inactive or unreachable');
          }
        }
        print(
            '  Note: DHT peer discovery is handled automatically by MetadataDownloader');
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
        const Duration(seconds: 180),
        onTimeout: () {
          print('');
          print('ERROR: Metadata download timeout after 180 seconds');
          print('');
          print('Diagnostics:');
          print('  Active peers: ${metadata.activePeers.length}');
          print(
              '  Metadata progress: ${metadata.progress.toStringAsFixed(1)}%');
          print(
              '  Metadata size: ${metadata.metaDataSize != null ? "${(metadata.metaDataSize! / 1024).toStringAsFixed(1)} KB" : "unknown"}');
          print(
              '  Bytes downloaded: ${metadata.bytesDownloaded != null ? "${(metadata.bytesDownloaded! / 1024).toStringAsFixed(1)} KB" : "0 KB"}');
          print('  Peers from trackers: $totalTrackerPeers');
          print('  Connection attempts: $connectionAttempts');
          print('  Successful connections: $connectionSuccesses');
          final connectionRate = connectionAttempts > 0
              ? (connectionSuccesses / connectionAttempts * 100)
                  .toStringAsFixed(1)
              : '0.0';
          print('  Connection success rate: $connectionRate%');
          if (firstConnectionAttempt != null) {
            final duration = DateTime.now().difference(firstConnectionAttempt!);
            print('  Time since first attempt: ${duration.inSeconds}s');
          }
          if (failedPeerBlacklist.isNotEmpty) {
            print(
                '  Blacklisted peers (failed multiple times): ${failedPeerBlacklist.length}');
            print('    (These peers are filtered to avoid wasting time)');
          }
          print(
              '  Note: DHT peer discovery is handled automatically by MetadataDownloader');
          if (connectedPeerAddresses.isNotEmpty) {
            print('  Connected peer addresses:');
            for (var addr in connectedPeerAddresses.take(10)) {
              print('    - $addr');
            }
            if (connectedPeerAddresses.length > 10) {
              print('    ... and ${connectedPeerAddresses.length - 10} more');
            }
          }
          print('');
          print('Analysis:');
          if (totalTrackerPeers > 0 &&
              connectionAttempts > 0 &&
              connectionSuccesses == 0) {
            print(
                '  ⚠ Got $totalTrackerPeers peers, attempted $connectionAttempts connections, but none succeeded!');
            print('    Possible causes:');
            print('    1. Peers are not active (torrent may be dead)');
            print('    2. Firewall blocking outbound connections');
            print('    3. Network connectivity issues');
            print('    4. Peers are behind NAT and not accepting connections');
            print(
                '    5. Peers do not support the BitTorrent protocol version');
            if (connectionAttempts >= 20) {
              print(
                  '    ⚠ High number of failed attempts suggests peers are inactive');
            }
          } else if (totalTrackerPeers > 0 && connectionAttempts == 0) {
            print(
                '  ⚠ Got $totalTrackerPeers peers but no connection attempts made!');
            print('    This suggests a problem with peer address processing');
          } else if (totalTrackerPeers == 0 && connectionSuccesses == 0) {
            print('  ⚠ No peers found from trackers');
            print('    Torrent may be inactive or not popular');
            print('    DHT may find peers, but it takes time to bootstrap');
          } else if (connectionSuccesses > 0) {
            // Check if connected peers had suspicious ports
            bool hasSuspiciousPorts = false;
            for (var addr in connectedPeerAddresses) {
              if (addr.contains(':80') ||
                  addr.contains(':443') ||
                  addr.contains(':8080') ||
                  addr.contains(':8443')) {
                hasSuspiciousPorts = true;
                break;
              }
            }
            if (hasSuspiciousPorts) {
              print('  ⚠ Some peers connected but immediately disconnected');
              print(
                  '    Problem: Tracker returned some HTTP/proxy servers (port 80) instead of BitTorrent peers');
              print(
                  '    These are not BitTorrent clients - they send HTTP responses');
              print('    This causes "Invalid message length" errors');
              print(
                  '    Note: These peers are automatically disconnected by the client');
            } else {
              final metadataProgress = metadata.progress;
              if (metadataProgress > 0) {
                print(
                    '  ⚠ Peers connected and metadata download started (${metadataProgress.toStringAsFixed(1)}%)');
                print('    But download did not complete within timeout');
                print('    Possible reasons:');
                print('    1. Peers are slow to respond to metadata requests');
                print(
                    '    2. Peers disconnected before completing metadata transfer');
                print('    3. Network issues causing packet loss');
                print('    Suggestion: Try again or increase timeout');
              } else {
                print('  ⚠ Peers connected but metadata not downloading');
                print('    Possible reasons:');
                print('    1. Peers do not support ut_metadata extension');
                print('    2. Peers disconnected before metadata exchange');
                print(
                    '    3. Peers are not seeders (do not have complete metadata)');
                print('    4. Network issues preventing metadata requests');
              }
            }
          }
          print('');
          print('Possible reasons:');
          print('  - Torrent is not active or has no seeders');
          print('  - Network connectivity issues');
          print('  - Firewall blocking connections');
          print('  - Peers are not responding to metadata requests');
          print('  - Peers do not support ut_metadata extension');
          print('');
          print('Suggestions:');
          print('  - Try using a more popular torrent');
          print('  - Provide a .torrent file instead of magnet link');
          print('  - Check your network/firewall settings');
          print('  - Verify torrent is active on tracker');
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
    print(
        'Piece size: ${(torrentModel.pieceLength / 1024 / 1024).toStringAsFixed(2)} MB');
    print('Files: ${torrentModel.files.length}');
    if (torrentModel.files.length <= 10) {
      print('File list:');
      for (var i = 0; i < torrentModel.files.length; i++) {
        final file = torrentModel.files[i];
        print(
            '  [$i] ${file.name} (${(file.length / 1024 / 1024).toStringAsFixed(2)} MB)');
      }
    } else {
      print('First 5 files:');
      for (var i = 0; i < 5; i++) {
        final file = torrentModel.files[i];
        print(
            '  [$i] ${file.name} (${(file.length / 1024 / 1024).toStringAsFixed(2)} MB)');
      }
      print('  ... and ${torrentModel.files.length - 5} more files');
    }
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
    int lastSeederCount = 0;
    DateTime? firstDataReceived;
    DateTime? firstPeerConnected;
    DateTime? taskStartTime;
    bool hasReceivedData = false;
    int lastTotalPieces = 0;

    // Monitor events
    final downloadCompleted = Completer<void>();
    final listener = task.createListener();
    listener
      ..on<TaskStarted>((event) {
        taskStartTime = DateTime.now();
        print('✓ Task started');
      })
      ..on<TaskCompleted>((event) {
        print('');
        print('🎉 Download completed!');
        if (taskStartTime != null) {
          final duration = DateTime.now().difference(taskStartTime!);
          print(
              '   Total time: ${duration.inMinutes}m ${duration.inSeconds % 60}s');
        }
        // Signal that download is complete so we can exit early
        if (!downloadCompleted.isCompleted) {
          downloadCompleted.complete();
        }
      })
      ..on<StateFileUpdated>((event) {
        final downloaded = task.downloaded ?? 0;
        if (downloaded > lastDownloaded && !hasReceivedData) {
          hasReceivedData = true;
          firstDataReceived = DateTime.now();
          final timeSinceConnection = firstPeerConnected != null
              ? firstDataReceived!.difference(firstPeerConnected!).inSeconds
              : 0;
          final timeSinceStart = taskStartTime != null
              ? firstDataReceived!.difference(taskStartTime!).inSeconds
              : 0;
          print('');
          print('🎉 FIRST DATA RECEIVED!');
          print('   Downloaded: ${(downloaded / 1024).toStringAsFixed(2)} KB');
          print('   Time since first peer: ${timeSinceConnection}s');
          print('   Time since task start: ${timeSinceStart}s');
          print('');
        }
      });

    print('Starting download...');
    await task.start();
    print('');

    // Transfer peers from MetadataDownloader to TorrentTask
    // This is critical: peers that were connected during metadata download
    // should be reused for actual download to avoid reconnection delays
    // NOTE: Must be called AFTER task.start() because peersManager is initialized there
    final metadataPeers = metadata.activePeers;
    if (metadataPeers.isNotEmpty) {
      print(
          'Transferring ${metadataPeers.length} peer(s) from metadata downloader...');
      int transferredCount = 0;
      for (var peer in metadataPeers) {
        try {
          // Get peer address and type
          final peerAddress = peer.address;
          final peerType = peer.type;

          // Add peer to task (will reconnect with new handshake)
          task.addPeer(peerAddress, PeerSource.manual, type: peerType);
          transferredCount++;
        } catch (e) {
          // Skip peers that can't be transferred
          print('  ⚠ Failed to transfer peer ${peer.address}: $e');
        }
      }
      print('  ✓ Transferred $transferredCount peer(s)');
      print('');
    }

    // Add trackers from magnet link to TorrentTask
    // This ensures we use trackers from magnet link even if they're not in metadata
    // NOTE: Must be called AFTER task.start() because tracker is initialized there
    if (magnet.trackers.isNotEmpty) {
      print('Adding ${magnet.trackers.length} tracker(s) from magnet link...');
      final infoHashBuffer = Uint8List.fromList(
        List.generate(magnet.infoHashString.length ~/ 2, (i) {
          final s = magnet.infoHashString.substring(i * 2, i * 2 + 2);
          return int.parse(s, radix: 16);
        }),
      );
      for (var trackerUrl in magnet.trackers) {
        try {
          task.startAnnounceUrl(trackerUrl, infoHashBuffer);
        } catch (e) {
          print('  ⚠ Failed to add tracker $trackerUrl: $e');
        }
      }
      print('  ✓ Added ${magnet.trackers.length} tracker(s)');
      print('');
    }

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
      final seederCount = task.seederNumber;
      final downloadSpeed =
          ((task.currentDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);
      final avgDownloadSpeed =
          ((task.averageDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);
      final uploadSpeed = ((task.uploadSpeed) * 1000 / 1024).toStringAsFixed(2);

      // Track first peer
      if (connectedPeers > 0 && firstPeerConnected == null) {
        firstPeerConnected = DateTime.now();
        final timeSinceStart = taskStartTime != null
            ? firstPeerConnected!.difference(taskStartTime!).inSeconds
            : 0;
        print('✓ First peer connected (${timeSinceStart}s after start)');
      }

      final downloadedDelta = downloaded - lastDownloaded;
      final peersDelta = connectedPeers - lastConnectedPeers;
      final seederDelta = seederCount - lastSeederCount;

      // Calculate pieces downloaded
      int currentTotalPieces = 0;
      final stateFile = task.stateFile;
      if (stateFile != null) {
        currentTotalPieces = stateFile.bitfield.completedPieces.length;
      }
      final piecesDelta = currentTotalPieces - lastTotalPieces;

      print('─' * 60);
      print('Progress: ${progress.toStringAsFixed(2)}% | '
          'Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB | '
          'Peers: $connectedPeers/$allPeers ($seederCount seeders) | '
          'Speed: $downloadSpeed KB/s (avg: $avgDownloadSpeed KB/s)');

      if (uploadSpeed != '0.00') {
        print('  Upload: $uploadSpeed KB/s');
      }

      // Detailed peer information
      final activePeers = task.activePeers;
      if (activePeers != null && activePeers.isNotEmpty) {
        var downloadingCount = 0;
        var uploadingCount = 0;
        var interestedCount = 0;
        var chokedCount = 0;
        var unchokedCount = 0;

        for (var peer in activePeers) {
          if (peer.isDownloading) downloadingCount++;
          // Check if peer is requesting from us (uploading)
          if (peer.remoteRequestBuffer.isNotEmpty) uploadingCount++;
          // Check if we are interested in peer
          if (peer.interestedRemote) interestedCount++;
          // Check if peer choked us
          if (peer.chokeMe) chokedCount++;
          if (!peer.chokeMe) unchokedCount++;
        }

        if (downloadingCount > 0 || uploadingCount > 0 || piecesDelta > 0) {
          print(
              '  Active: $downloadingCount downloading, $uploadingCount uploading');
        }
        if (piecesDelta > 0) {
          print(
              '  ✓ Completed $piecesDelta piece(s) (total: $currentTotalPieces/${torrentModel.pieces.length})');
        }
        if (interestedCount > 0) {
          print(
              '  Peer states: $interestedCount interested, $unchokedCount unchoked, $chokedCount choked');
        }
      }

      if (downloadedDelta > 0) {
        print(
            '  ✓ Downloading: +${(downloadedDelta / 1024).toStringAsFixed(2)} KB');
      } else if (connectedPeers > 0) {
        if (peersDelta > 0) {
          print('  +$peersDelta new peer(s)');
        }
        if (seederDelta > 0) {
          print('  +$seederDelta new seeder(s)');
        }
        if (connectedPeers >= 12 && downloadedDelta == 0 && !hasReceivedData) {
          print('');
          print('⚠⚠⚠ POTENTIAL ISSUE: 12+ peers but no download!');
          print('   This may indicate a problem with peer communication.');
          print('   Checking peer states...');
          if (activePeers != null) {
            var hasInterested = false;
            var hasUnchoked = false;
            for (var peer in activePeers) {
              if (peer.interestedRemote) hasInterested = true;
              if (!peer.chokeMe) hasUnchoked = true;
            }
            print('   Interested peers: $hasInterested');
            print('   Unchoked peers: $hasUnchoked');
          }
          print('');
        }
      } else if (allPeers > 0 && connectedPeers == 0) {
        print('  ⚠ Warning: $allPeers peer(s) known but none connected');
      }

      lastDownloaded = downloaded;
      lastConnectedPeers = connectedPeers;
      lastSeederCount = seederCount;
      lastTotalPieces = currentTotalPieces;
    });

    // Run for 2 minutes (enough to test the fix and verify stability)
    // Or until download completes
    print('Running test for 2 minutes (or until download completes)...');
    print('Press Ctrl+C to stop early');
    print('');

    try {
      // Wait for either download completion or 2 minutes timeout
      await Future.any([
        downloadCompleted.future,
        Future.delayed(const Duration(minutes: 2)),
      ]);

      // If download completed, wait a bit more to show final stats
      if (downloadCompleted.isCompleted) {
        print('');
        print('Download completed! Waiting 3 seconds for final stats...');
        await Future.delayed(const Duration(seconds: 3));
      }
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
    final finalSeederCount = task.seederNumber;
    final finalDownloaded = task.downloaded ?? 0;
    final finalProgress = task.progress;
    final finalDownloadSpeed =
        ((task.currentDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);
    final finalAvgDownloadSpeed =
        ((task.averageDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);

    int finalCompletedPieces = 0;
    int totalPieces = torrentModel.pieces.length;
    final stateFile = task.stateFile;
    if (stateFile != null) {
      finalCompletedPieces = stateFile.bitfield.completedPieces.length;
    }

    print('Connected peers: $finalConnected');
    print('Total peers: $finalAll');
    print('Seeders: $finalSeederCount');
    print(
        'Downloaded: ${(finalDownloaded / 1024 / 1024).toStringAsFixed(2)} MB');
    print('Progress: ${(finalProgress * 100).toStringAsFixed(2)}%');
    print('Pieces completed: $finalCompletedPieces/$totalPieces');
    print('Current speed: $finalDownloadSpeed KB/s');
    print('Average speed: $finalAvgDownloadSpeed KB/s');

    if (taskStartTime != null) {
      final duration = DateTime.now().difference(taskStartTime!);
      print(
          'Test duration: ${duration.inMinutes}m ${duration.inSeconds % 60}s');
    }

    print('');
    print('Results:');
    if (hasReceivedData) {
      print('✓ SUCCESS: Data downloaded! Fix is working.');
      if (firstPeerConnected != null && firstDataReceived != null) {
        final delay =
            firstDataReceived!.difference(firstPeerConnected!).inSeconds;
        print('✓ Data started $delay s after first peer connection');
        if (delay > 30) {
          print(
              '  ⚠ Note: Delay is longer than expected, but download is working');
        }
      }
      if (finalProgress >= 1.0) {
        print('✓ Download completed successfully!');
      } else if (finalProgress > 0.1) {
        print(
            '✓ Download is progressing well (${(finalProgress * 100).toStringAsFixed(1)}% complete)');
      } else {
        print(
            '✓ Download started successfully (${(finalProgress * 100).toStringAsFixed(1)}% complete)');
      }
    } else if (finalConnected >= 12) {
      print('✗ FAILURE: 12+ peers but no download - bug may still exist');
      print('  This indicates a potential issue with peer communication.');
      print('  Please check:');
      print('    - Are peers sending bitfield messages?');
      print('    - Are we sending interested messages?');
      print('    - Are peers unchoking us?');
    } else if (finalConnected > 0) {
      print('⚠ INCONCLUSIVE: Only $finalConnected peer(s) connected');
      print('  Need 12+ peers to properly test the fix.');
      if (finalSeederCount == 0) {
        print('  ⚠ No seeders found - torrent may not be active.');
      }
    } else {
      print('⚠ INCONCLUSIVE: No peers connected');
      print('  Possible reasons:');
      print('    - Torrent is not active or has no seeders');
      print('    - Network connectivity issues');
      print('    - Firewall blocking connections');
      print('    - Tracker issues');
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
