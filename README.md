## About
Dart library for implementing BitTorrent client.

The Dart Torrent client consists of several parts:
- [Bencode](https://pub.dev/packages/b_encode_decode) 
- [Tracker](https://pub.dev/packages/dtorrent_tracker)
- [DHT](https://pub.dev/packages/bittorrent_dht)
- [Torrent model](https://pub.dev/packages/dtorrent_parser)
- [Common library](https://pub.dev/packages/dtorrent_common)
- [UTP](https://pub.dev/packages/utp_protocol)

This package implements the regular BitTorrent Protocol and manages the above packages to work together for downloading.

## BEP Support
- [BEP 0003 The BitTorrent Protocol Specification](http://www.bittorrent.org/beps/bep_0003.html)
- [BEP 0005 DHT Protocol](http://www.bittorrent.org/beps/bep_0005.html)
- [BEP 0006 Fast Extension](http://www.bittorrent.org/beps/bep_0006.html)
- [BEP 0010 Extension Protocol](http://www.bittorrent.org/beps/bep_0010.html)
- [BEP 0011 Peer Exchange (PEX)](http://www.bittorrent.org/beps/bep_0011.html)
- [BEP 0014 Local Service Discovery](http://www.bittorrent.org/beps/bep_0014.html)
- [BEP 0015 UDP Tracker Protocol](http://www.bittorrent.org/beps/bep_0015.html)
- [BEP 0029 uTorrent transport protocol](http://www.bittorrent.org/beps/bep_0029.html)
- [BEP 0055 Holepunch extension](http://www.bittorrent.org/beps/bep_0055.html)

Developing:
- [BEP 0009 Extension for Peers to Send Metadata Files](http://www.bittorrent.org/beps/bep_0009.html)

Other support will come soon.

## How to use

This package requires dependency [`dtorrent_parser`](https://pub.dev/packages/dtorrent_parser):
```yaml
dependencies:
  dtorrent_parser: ^1.0.8
  dtorrent_task_v2: ^0.4.3
```

Download from: [DTORRENT_TASK_V2](https://pub.dev/packages/dtorrent_task_v2)

Import the library:
```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
```

First, create a `Torrent` model from a .torrent file:

```dart
  var model = await Torrent.parse('some.torrent');
```

Second, create a `Torrent Task` and start it:
```dart
  var task = TorrentTask.newTask(model, 'savepath');
  await task.start();
```

You can add event listeners to monitor `TorrentTask` execution:
```dart
  EventsListener<TaskEvent> listener = task.createListener();
  listener
    ..on<TaskCompleted>((event) {
      print('Download completed!');
    })
    ..on<TaskFileCompleted>((event) {
      print('File completed: ${event.file.originalFileName}');
    })
    ..on<TaskStopped>((event) {
      print('Task stopped');
    });
```

And there are methods to control the `TorrentTask`:

```dart
   // Stop task:
   await task.stop();
   // Pause task:
   task.pause();
   // Resume task:
   task.resume();
```

## Monitoring and Error Tracking

The library includes comprehensive error tracking for uTP protocol stability:

```dart
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';

// Check RangeError metrics
if (Peer.rangeErrorCount > 0) {
  print('Total RangeErrors: ${Peer.rangeErrorCount}');
  print('uTP RangeErrors: ${Peer.utpRangeErrorCount}');
  print('Errors by reason: ${Peer.rangeErrorByReason}');
}

// Reset metrics for new monitoring period
Peer.resetRangeErrorMetrics();
```

These metrics help monitor uTP protocol stability and debug RangeError crashes, particularly those related to selective ACK processing and buffer handling.

## Features

### Stability Improvements
- **uTP RangeError Protection**: Comprehensive protection against RangeError crashes in uTP protocol with:
  - Buffer bounds validation before all operations
  - Message length validation (negative, oversized, and overflow protection)
  - Integer overflow protection in calculations
  - Detailed error tracking and metrics
  - Extensive test coverage (stress tests, reordering, extreme values, long sessions)
- **Critical Bug Fixes**: Fixed race condition in bitfield processing that prevented downloads from starting (see [issue #4](https://github.com/atlet99/dtorrent_task_v2/issues/4))

### Protocol Support
- Full BitTorrent protocol implementation
- uTP (uTorrent transport protocol) support with enhanced stability
- TCP fallback support
- Multiple extension protocols (PEX, LSD, Holepunch, Metadata Exchange)
- Magnet link support via `MagnetParser`
- Torrent creation via `TorrentCreator`

### Performance
- Efficient piece management and selection
- Memory-optimized file handling
- Streaming support for media files with isolate-based processing
- Optimized congestion control for uTP connections
- Debounced progress events for reduced UI update frequency
