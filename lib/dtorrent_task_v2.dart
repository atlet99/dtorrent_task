import 'dart:io';

export 'src/torrent_task_base.dart';
export 'src/file/file_base.dart';
export 'src/piece/piece_base.dart';
export 'src/peer/peer_base.dart';
export 'src/stream/stream_events.dart';
export 'src/task_events.dart';
export 'src/metadata/metadata_downloader.dart';
export 'src/metadata/metadata_downloader_events.dart';
export 'src/metadata/magnet_parser.dart';
export 'src/torrent/torrent_creator.dart';
export 'src/piece/sequential_config.dart';
export 'src/piece/sequential_stats.dart';
export 'src/piece/advanced_sequential_selector.dart';

/// Peer ID prefix
const ID_PREFIX = '-DT0201-';

/// Current version number
Future<String?> getTorrentTaskVersion() async {
  var file = File('pubspec.yaml');
  if (await file.exists()) {
    var lines = await file.readAsLines();
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var strings = line.split(':');
      if (strings.length == 2) {
        var key = strings[0];
        var value = strings[1];
        if (key == 'version') return value;
      }
    }
  }
  return null;
}
