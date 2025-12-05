import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// Sequential streaming test with magnet link
///
/// This demonstrates the full sequential download workflow with a real torrent
void main(List<String> args) async {
  // Setup logging
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    if (record.level >= Level.INFO) {
      print('[${record.level.name}] ${record.message}');
    }
  });

  String magnetUri;

  if (args.isNotEmpty) {
    magnetUri = args[0];
  } else {
    // Default test magnet (small file for quick testing)
    print('Usage: dart run example/test_sequential_magnet.dart <magnet_uri>');
    print('');
    print('Using default test magnet...');
    magnetUri =
        'magnet:?xt=urn:btih:6BE701C4B7B0C5F5F36799342DFF1250DE936BE2&dn=Nineteen+Eighty-Four';
  }

  print('=' * 60);
  print('Sequential Download - Magnet Test');
  print('=' * 60);
  print('Magnet: ${magnetUri.substring(0, 60)}...');
  print('');

  // Parse magnet
  final magnet = MagnetParser.parse(magnetUri);
  if (magnet == null) {
    print('ERROR: Failed to parse magnet URI');
    exit(1);
  }

  print('Parsed magnet:');
  print('  Info hash: ${magnet.infoHashString}');
  print('  Name: ${magnet.displayName ?? "Unknown"}');
  print('  Trackers: ${magnet.trackers.length}');
  print('');

  // Download metadata
  print('Downloading metadata...');
  final metadata = MetadataDownloader.fromMagnet(magnetUri);
  final metadataListener = metadata.createListener();

  final metadataCompleter = Completer<List<int>>();
  int lastProgress = 0;

  metadataListener
    ..on<MetaDataDownloadProgress>((event) {
      final progress = (event.progress * 100).toInt();
      if (progress != lastProgress && progress % 10 == 0) {
        lastProgress = progress;
        print('  Metadata: $progress%');
      }
    })
    ..on<MetaDataDownloadComplete>((event) {
      print('  Metadata downloaded!');
      metadataCompleter.complete(event.data);
    });

  metadata.startDownload();

  List<int> metadataBytes;
  try {
    metadataBytes = await metadataCompleter.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        print('ERROR: Metadata download timeout');
        exit(1);
      },
    );
  } catch (e) {
    print('ERROR: $e');
    exit(1);
  }

  // Parse torrent
  final msg = decode(Uint8List.fromList(metadataBytes));
  final torrentMap = <String, dynamic>{'info': msg};
  final torrent = parseTorrentFileContent(torrentMap);

  if (torrent == null) {
    print('ERROR: Failed to parse torrent');
    exit(1);
  }

  print('');
  print('Torrent info:');
  print('  Name: ${torrent.name}');
  print('  Size: ${(torrent.length / 1024 / 1024).toStringAsFixed(2)} MB');
  print('  Pieces: ${torrent.pieces.length}');
  print('  Files: ${torrent.files.length}');
  print('');

  // Create sequential config
  final config = SequentialConfig.forVideoStreaming();
  print('Sequential Config:');
  print('  Look-ahead: ${config.lookAheadSize} pieces');
  print(
      '  Critical zone: ${(config.criticalZoneSize / 1024 / 1024).toStringAsFixed(1)} MB');
  print('  Adaptive: ${config.adaptiveStrategy}');
  print('  Auto-detect moov: ${config.autoDetectMoovAtom}');
  print('');

  // Create save path
  final savePath = path.join(Directory.current.path, 'downloads');
  await Directory(savePath).create(recursive: true);

  // Create task with sequential config
  final task = TorrentTask.newTask(
    torrent,
    savePath,
    true, // streaming mode
    magnet.webSeeds.isNotEmpty ? magnet.webSeeds : null,
    magnet.acceptableSources.isNotEmpty ? magnet.acceptableSources : null,
    config, // sequential config
  );

  // Setup listeners
  final listener = task.createListener();
  Timer? statsTimer;

  listener
    ..on<TaskStarted>((event) {
      print('Task started');
      print('');

      // Start periodic stats reporting
      statsTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        final stats = task.getSequentialStats();
        if (stats != null) {
          print('Sequential Stats:');
          print('  Buffer health: ${stats.bufferHealth.toStringAsFixed(1)}%');
          print('  Buffered pieces: ${stats.bufferedPieces}');
          print('  Strategy: ${stats.currentStrategy.name}');
          if (stats.timeToFirstByte != null) {
            print('  Time to first byte: ${stats.timeToFirstByte}ms');
          }
          print('');
        }
      });
    })
    ..on<TaskCompleted>((event) {
      print('Download completed!');
      statsTimer?.cancel();
      exit(0);
    })
    ..on<StateFileUpdated>((event) {
      final downloaded = task.downloaded ?? 0;
      final progress = task.progress * 100;
      final peers = task.connectedPeersNumber;
      final speed =
          ((task.currentDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);

      print('Progress: ${progress.toStringAsFixed(1)}% | '
          'Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB | '
          'Peers: $peers | Speed: $speed KB/s');
    });

  // Start download
  print('Starting sequential download...');
  await task.start();

  // Transfer peers from metadata downloader
  final metadataPeers = metadata.activePeers;
  if (metadataPeers.isNotEmpty) {
    print('Transferring ${metadataPeers.length} peer(s) from metadata...');
    for (var peer in metadataPeers) {
      task.addPeer(peer.address, PeerSource.manual, type: peer.type);
    }
  }

  print('');
  print('Download in progress... (Press Ctrl+C to stop)');
  print('');

  // Keep running
  await Future.delayed(Duration(hours: 24));
}
