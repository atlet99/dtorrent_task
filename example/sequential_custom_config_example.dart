import 'dart:io';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Sequential download with custom configuration example
///
/// Usage:
///   dart run example/sequential_custom_config_example.dart [config_type] [torrent_file]
///
/// Config types: video, audio, minimal, custom
/// If no torrent file is provided, it will use tmp/test.torrent
void main(List<String> args) async {
  print('=' * 60);
  print('Sequential Download - Custom Configuration Example');
  print('=' * 60);
  print('');

  final configType = args.isNotEmpty ? args[0] : 'video';
  String torrentFile;
  
  if (args.length > 1) {
    torrentFile = args[1];
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

  // Create configuration based on type
  SequentialConfig config;
  
  switch (configType.toLowerCase()) {
    case 'video':
      config = SequentialConfig.forVideoStreaming();
      print('Using VIDEO streaming configuration:');
      break;
    case 'audio':
      config = SequentialConfig.forAudioStreaming();
      print('Using AUDIO streaming configuration:');
      break;
    case 'minimal':
      config = SequentialConfig.minimal();
      print('Using MINIMAL configuration:');
      break;
    case 'custom':
      config = const SequentialConfig(
        lookAheadSize: 25,
        criticalZoneSize: 15 * 1024 * 1024,
        adaptiveStrategy: true,
        minSpeedForSequential: 200 * 1024,
        autoDetectMoovAtom: true,
        seekLatencyTolerance: 2,
        enablePeerPriority: true,
        enableFastResumption: true,
      );
      print('Using CUSTOM configuration:');
      break;
    default:
      print('Unknown config type: $configType, using video');
      config = SequentialConfig.forVideoStreaming();
  }

  print('  Look-ahead buffer: ${config.lookAheadSize} pieces');
  print('  Critical zone: ${(config.criticalZoneSize / 1024 / 1024).toStringAsFixed(1)} MB');
  print('  Adaptive strategy: ${config.adaptiveStrategy}');
  print('  Min speed: ${(config.minSpeedForSequential / 1024).toStringAsFixed(1)} KB/s');
  print('');

  // Create save directory in tmp
  final savePath = path.join('tmp', 'custom_config_test', torrent.name);
  await Directory(savePath).create(recursive: true);
  print('Save path: $savePath');
  print('');

  final task = TorrentTask.newTask(torrent, savePath, true, null, null, config);
  final listener = task.createListener();
  
  listener
    ..on<TaskStarted>((event) {
      print('Task started with custom configuration');
      print('');
    })
    ..on<TaskCompleted>((event) {
      print('');
      print('Download completed!');
      
      final stats = task.getSequentialStats();
      if (stats != null) {
        print('');
        print('Final Statistics:');
        print('  Buffer health: ${stats.bufferHealth.toStringAsFixed(1)}%');
        print('  Time to first byte: ${stats.timeToFirstByte ?? "N/A"} ms');
        print('  Strategy: ${stats.currentStrategy.name}');
        print('  Seek count: ${stats.seekCount}');
      }
      exit(0);
    })
    ..on<StateFileUpdated>((event) {
      final downloaded = task.downloaded ?? 0;
      final progress = task.progress * 100;
      final peers = task.connectedPeersNumber;
      final speed = ((task.currentDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);
      final stats = task.getSequentialStats();
      
      if (stats != null) {
        print('Progress: ${progress.toStringAsFixed(1)}% | '
            'Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB | '
            'Peers: $peers | Speed: $speed KB/s | '
            'Buffer: ${stats.bufferHealth.toStringAsFixed(1)}% | '
            'Strategy: ${stats.currentStrategy.name}');
      }
    });

  print('Starting sequential download...');
  await task.start();
  await Future.delayed(Duration(hours: 24));
}
