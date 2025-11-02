## About
Dart library for implementing BitTorrent client. 

Whole Dart Torrent client contains several parts :
- [Bencode](https://pub.dev/packages/b_encode_decode) 
- [Tracker](https://pub.dev/packages/dtorrent_tracker)
- [DHT](https://pub.dev/packages/bittorrent_dht)
- [Torrent model](https://pub.dev/packages/dtorrent_parser)
- [Common library](https://pub.dev/packages/dtorrent_common)
- [UTP](https://pub.dev/packages/utp_protocol)

This package implements regular BitTorrent Protocol and manage above packages to work together for downloading.

## BEP Support:
- [BEP 0003 The BitTorrent Protocol Specification]
- [BEP 0005 DHT Protocal]
- [BEP 0006 Fast Extension]
- [BEP 0010	Extension Protocol]
- [BEP 0011	Peer Exchange (PEX)]
- [BEP 0014 Local Service Discovery]
- [BEP 0015 UDP Tracker Protocal]
- [BEP 0029 uTorrent transport protocol]
- [BEP 0055 Holepunch extension]

Developing:
- [BEP 0009	Extension for Peers to Send Metadata Files]

Other support will come soon.

## How to use

This package requires dependency [`dtorrent_parser`](https://pub.dev/packages/dtorrent_parser):
```yaml
dependencies:
  dtorrent_parser: ^1.0.8
  dtorrent_task: ^0.4.1
```

First , create a `Torrent` model via .torrent file:

```dart
  var model = await Torrent.parse('some.torrent');
```

Second, create a `Torrent Task` and start it:
```dart
  var task = TorrentTask.newTask(model, 'savepath');
  await task.start();
```

User can add event listeners to monitor `TorrentTask` running:
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
