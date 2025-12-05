import 'dart:async';
import 'dart:io';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// Real torrent example with sequential download
///
/// Usage:
///   dart run example/sequential_real_torrent_example.dart [torrent_file]
///
/// If no torrent file is provided, it will use tmp/test.torrent
void main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    if (record.level >= Level.WARNING) {
      print('[${record.level.name}] ${record.message}');
    }
  });

  print('=' * 60);
  print('Sequential Download - Real Torrent Example');
  print('=' * 60);
  print('');

  String torrentFile;
  
  if (args.isNotEmpty) {
    torrentFile = args[0];
  } else {
    torrentFile = 'tmp/test.torrent';
  }
  
  if (!await File(torrentFile).exists()) {
    print('Error: Torrent file not found: $torrentFile');
    print('Please provide a torrent file or place one at: tmp/test.torrent');
    exit(1);
  }
  
  print('Using torrent file: $torrentFile');
  print('');

  final torrent = await Torrent.parse(torrentFile);
  print('Torrent information:');
  print('  Name: ${torrent.name}');
  print('  Size: ${(torrent.length / 1024 / 1024).toStringAsFixed(2)} MB');
  print('  Pieces: ${torrent.pieces.length}');
  print('  Files: ${torrent.files.length}');
  
  if (torrent.files.length <= 10) {
    print('');
    print('  Files:');
    for (var i = 0; i < torrent.files.length; i++) {
      final file = torrent.files[i];
      print('    [$i] ${file.name} (${(file.length / 1024 / 1024).toStringAsFixed(2)} MB)');
    }
  }
  print('');

  final config = SequentialConfig.forVideoStreaming();
  print('Sequential configuration:');
  print('  Look-ahead buffer: ${config.lookAheadSize} pieces');
  print('  Critical zone: ${(config.criticalZoneSize / 1024 / 1024).toStringAsFixed(1)} MB');
  print('  Adaptive strategy: ${config.adaptiveStrategy}');
  print('');

  // Create save directory in tmp
  final savePath = path.join('tmp', 'real_torrent_test', torrent.name);
  await Directory(savePath).create(recursive: true);
  print('Save path: $savePath');
  print('');

  final task = TorrentTask.newTask(torrent, savePath, true, null, null, config);
  final downloadStartTime = DateTime.now();
  Timer? statsTimer;
  int maxPeers = 0;
  double maxSpeed = 0;

  final listener = task.createListener();
  
  listener
    ..on<TaskStarted>((event) {
      print('Download started');
      print('');
      
      statsTimer = Timer.periodic(Duration(seconds: 10), (timer) {
        final stats = task.getSequentialStats();
        if (stats != null) {
          print('');
          print('Sequential Statistics:');
          print('  Buffer health: ${stats.bufferHealth.toStringAsFixed(1)}%');
          print('  Buffered pieces: ${stats.bufferedPieces}/${config.lookAheadSize}');
          print('  Strategy: ${stats.currentStrategy.name}');
          
          if (stats.timeToFirstByte != null) {
            print('  Time to first byte: ${stats.timeToFirstByte}ms');
          }
          
          if (stats.moovAtomDownloaded != null) {
            print('  Moov atom ready: ${stats.moovAtomDownloaded}');
          }
          print('');
        }
      });
    })
    ..on<TaskCompleted>((event) {
      final elapsed = DateTime.now().difference(downloadStartTime);
      
      print('');
      print('=' * 60);
      print('Download completed!');
      print('=' * 60);
      print('Time: ${elapsed.inHours}h ${elapsed.inMinutes % 60}m ${elapsed.inSeconds % 60}s');
      print('Max peers: $maxPeers');
      print('Max speed: ${(maxSpeed / 1024).toStringAsFixed(2)} KB/s');
      
      final stats = task.getSequentialStats();
      if (stats != null) {
        print('');
        print('Final Statistics:');
        print('  Seeks: ${stats.seekCount}');
        if (stats.averageSeekLatency != null) {
          print('  Avg seek latency: ${stats.averageSeekLatency}ms');
        }
        if (stats.timeToFirstByte != null) {
          print('  Time to first byte: ${stats.timeToFirstByte}ms');
        }
      }
      
      statsTimer?.cancel();
      exit(0);
    })
    ..on<StateFileUpdated>((event) {
      final downloaded = task.downloaded ?? 0;
      final progress = task.progress * 100;
      final peers = task.connectedPeersNumber;
      final speed = (task.currentDownloadSpeed) * 1000;
      
      if (peers > maxPeers) maxPeers = peers;
      if (speed > maxSpeed) maxSpeed = speed;
      
      final stats = task.getSequentialStats();
      final bufferHealth = stats?.bufferHealth.toStringAsFixed(1) ?? 'N/A';
      final strategy = stats?.currentStrategy.name ?? 'N/A';
      
      print('Progress: ${progress.toStringAsFixed(1)}% | '
          'Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB | '
          'Peers: $peers | '
          'Speed: ${(speed / 1024).toStringAsFixed(2)} KB/s | '
          'Buffer: $bufferHealth% | '
          'Strategy: $strategy');
    });

  print('Starting sequential download...');
  print('Press Ctrl+C to stop');
  print('');
  
  await task.start();
  await Future.delayed(Duration(hours: 24));
}
