import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:logging/logging.dart';

/// Quick test to verify sequential download compilation and basic functionality
void main() async {
  // Setup logging
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('[${record.level.name}] ${record.loggerName}: ${record.message}');
  });

  print('=' * 60);
  print('Sequential Download - Compilation Test');
  print('=' * 60);
  print('');

  // Test 1: SequentialConfig creation
  print('Test 1: Creating SequentialConfig...');
  final config = SequentialConfig.forVideoStreaming();
  print('  Config created: $config');
  print('');

  // Test 2: Factory methods
  print('Test 2: Testing factory methods...');
  final audioConfig = SequentialConfig.forAudioStreaming();
  print('  Audio config: lookAhead=${audioConfig.lookAheadSize}');

  final minimalConfig = SequentialConfig.minimal();
  print('  Minimal config: lookAhead=${minimalConfig.lookAheadSize}');
  print('');

  // Test 3: SequentialStats
  print('Test 3: Creating SequentialStats...');
  final stats = SequentialStats(
    bufferHealth: 85.5,
    timeToFirstByte: 1500,
    playbackPosition: 1024 * 1024 * 10, // 10MB
    bufferedPieces: 8,
    downloadingPieces: 2,
    currentStrategy: DownloadStrategy.sequential,
    seekCount: 3,
    averageSeekLatency: 800,
    moovAtomDownloaded: true,
  );
  print('  Stats created: $stats');
  print('');

  // Test 4: AdvancedSequentialPieceSelector
  print('Test 4: Creating AdvancedSequentialPieceSelector...');
  final selector = AdvancedSequentialPieceSelector(config);
  selector.initialize(100, 256 * 1024); // 100 pieces, 256KB each
  print('  Selector initialized');

  // Test moov detection
  selector.detectAndSetMoovAtom(25 * 1024 * 1024, 256 * 1024); // 25MB file
  print('  Moov atom detection completed');
  print('');

  // Test 5: Playback position
  print('Test 5: Testing playback position...');
  selector.setPlaybackPosition(5 * 1024 * 1024, 256 * 1024); // Seek to 5MB
  print('  Playback position set to 5MB');
  print('');

  print('=' * 60);
  print('All compilation tests passed!');
  print('=' * 60);
  print('');
  print('Sequential download is ready to use.');
  print('To test with a real torrent, run:');
  print('  dart run example/sequential_streaming_example.dart <torrent_file>');
  print('');
  print('Or use a magnet link with test_with_magnet.dart');
}
