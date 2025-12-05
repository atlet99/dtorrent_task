import 'dart:async';
import 'dart:io';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Sequential download with seek operations example
///
/// Usage:
///   dart run example/sequential_seek_example.dart [torrent_file]
///
/// If no torrent file is provided, it will use tmp/test.torrent
void main(List<String> args) async {
  print('=' * 60);
  print('Sequential Download - Seek Example');
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

  // Parse torrent
  final torrent = await Torrent.parse(torrentFile);
  print('Torrent: ${torrent.name}');
  print('Size: ${(torrent.length / 1024 / 1024).toStringAsFixed(2)} MB');
  print('');

  // Create save directory in tmp
  final savePath = path.join('tmp', 'seek_test', torrent.name);
  await Directory(savePath).create(recursive: true);

  // Create sequential config optimized for seeking
  final config = SequentialConfig(
    lookAheadSize: 20,
    criticalZoneSize: 10 * 1024 * 1024,
    adaptiveStrategy: true,
    autoDetectMoovAtom: true,
    seekLatencyTolerance: 1,
    enablePeerPriority: true,
    enableFastResumption: true,
  );

  print('Sequential Config (optimized for seeking):');
  print('  Look-ahead buffer: ${config.lookAheadSize} pieces');
  print('  Seek latency tolerance: ${config.seekLatencyTolerance}s');
  print('  Save path: $savePath');
  print('');

  // Create task
  final task = TorrentTask.newTask(torrent, savePath, true, null, null, config);

  Timer? seekSimulationTimer;
  final listener = task.createListener();
  
  listener
    ..on<TaskStarted>((event) {
      print('Task started');
      print('Simulating seek operations every 10 seconds...');
      print('');

      seekSimulationTimer = Timer.periodic(Duration(seconds: 10), (timer) {
        final fileSize = torrent.length;
        final seekPositions = [
          (fileSize * 0.25).toInt(),
          (fileSize * 0.50).toInt(),
          (fileSize * 0.75).toInt(),
          (fileSize * 0.10).toInt(),
        ];

        final seekIndex = timer.tick % seekPositions.length;
        final seekPosition = seekPositions[seekIndex];
        
        print('');
        print('SEEK: ${(seekPosition / 1024 / 1024).toStringAsFixed(2)} MB '
            '(${((seekPosition / fileSize) * 100).toStringAsFixed(1)}%)');
        
        task.setPlaybackPosition(seekPosition);

        Timer(Duration(seconds: 2), () {
          final stats = task.getSequentialStats();
          if (stats != null) {
            print('Post-seek stats:');
            print('  Buffer health: ${stats.bufferHealth.toStringAsFixed(1)}%');
            print('  Buffered pieces: ${stats.bufferedPieces}');
            print('  Seek count: ${stats.seekCount}');
            if (stats.averageSeekLatency != null) {
              print('  Avg seek latency: ${stats.averageSeekLatency}ms');
            }
          }
        });
      });
    })
    ..on<TaskCompleted>((event) {
      print('');
      print('Download completed!');
      seekSimulationTimer?.cancel();
      exit(0);
    })
    ..on<StateFileUpdated>((event) {
      final downloaded = task.downloaded ?? 0;
      final progress = task.progress * 100;
      final peers = task.connectedPeersNumber;
      final speed = ((task.currentDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);
      final stats = task.getSequentialStats();
      final bufferHealth = stats?.bufferHealth.toStringAsFixed(1) ?? 'N/A';
      
      print('Progress: ${progress.toStringAsFixed(1)}% | '
          'Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB | '
          'Peers: $peers | Speed: $speed KB/s | Buffer: $bufferHealth%');
    });

  print('Starting sequential download with seek simulation...');
  await task.start();
  await Future.delayed(Duration(hours: 24));
}
