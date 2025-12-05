import 'dart:io';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Basic sequential streaming example
///
/// This example demonstrates how to use the advanced sequential download
/// feature for smooth video streaming.
///
/// Usage:
///   dart run example/sequential_streaming_example.dart [torrent_file]
///
/// If no torrent file is provided, it will use tmp/test.torrent
void main(List<String> args) async {
  print('=' * 60);
  print('Sequential Streaming Example');
  print('=' * 60);
  print('');

  String torrentFile;
  
  if (args.isNotEmpty) {
    // Use provided torrent file
    torrentFile = args[0];
  } else {
    // Use default torrent file from tmp/
    torrentFile = 'tmp/test.torrent';
  }
  
  if (!await File(torrentFile).exists()) {
    print('Error: Torrent file not found: $torrentFile');
    print('');
    print('Please provide a torrent file:');
    print('  dart run example/sequential_streaming_example.dart <torrent_file>');
    print('');
    print('Or place a torrent file at: tmp/test.torrent');
    exit(1);
  }
  
  print('Using torrent file: $torrentFile');
  print('');

  // Parse torrent file
  final torrent = await Torrent.parse(torrentFile);
  print('Torrent: ${torrent.name}');
  print('Size: ${(torrent.length / 1024 / 1024).toStringAsFixed(2)} MB');
  print('Pieces: ${torrent.pieces.length}');
  print('');

  // Create save directory in tmp
  final savePath = path.join('tmp', 'streaming_test', torrent.name);
  await Directory(savePath).create(recursive: true);
  print('Save path: $savePath');
  print('');

  // Create sequential configuration for video streaming
  final config = SequentialConfig.forVideoStreaming();
  print('Sequential Config:');
  print('  Look-ahead buffer: ${config.lookAheadSize} pieces');
  print(
      '  Critical zone: ${(config.criticalZoneSize / 1024 / 1024).toStringAsFixed(1)} MB');
  print('  Adaptive strategy: ${config.adaptiveStrategy}');
  print('  Auto-detect moov: ${config.autoDetectMoovAtom}');
  print('  Peer priority: ${config.enablePeerPriority}');
  print('  Fast resumption: ${config.enableFastResumption}');
  print('');

  // Create torrent task with sequential config
  final task = TorrentTask.newTask(
    torrent,
    savePath,
    true, // streaming mode
    null, // webSeeds
    null, // acceptableSources
    config, // sequential config
  );

  // Setup event listeners
  final listener = task.createListener();

  listener
    ..on<TaskStarted>((event) {
      print('Task started');
      print('');
    })
    ..on<TaskCompleted>((event) {
      print('');
      print('Download completed!');
      exit(0);
    })
    ..on<StateFileUpdated>((event) {
      final downloaded = task.downloaded ?? 0;
      final progress = task.progress * 100;
      final connectedPeers = task.connectedPeersNumber;
      final downloadSpeed =
          ((task.currentDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);

      print('Progress: ${progress.toStringAsFixed(1)}% | '
          'Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB | '
          'Peers: $connectedPeers | '
          'Speed: $downloadSpeed KB/s');
    });

  // Start download
  print('Starting sequential download...');
  await task.start();

  // Keep the program running
  await Future.delayed(Duration(hours: 24));
}
