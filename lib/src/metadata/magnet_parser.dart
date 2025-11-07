import 'dart:typed_data';

import 'package:logging/logging.dart';

var _log = Logger('MagnetParser');

/// Parsed magnet link data
class MagnetLink {
  /// Info hash (20 bytes)
  final Uint8List infoHash;

  /// Display name
  final String? displayName;

  /// Trackers (announce URLs)
  final List<Uri> trackers;

  /// Exact length (if specified)
  final int? exactLength;

  /// Info hash as hex string
  String get infoHashString {
    return infoHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  MagnetLink({
    required this.infoHash,
    this.displayName,
    List<Uri>? trackers,
    this.exactLength,
  }) : trackers = trackers ?? [];

  @override
  String toString() {
    return 'MagnetLink(infoHash: $infoHashString, name: $displayName, trackers: ${trackers.length})';
  }
}

/// Parser for magnet:? URIs
///
/// Supports parameters:
/// - xt: exact topic (info hash) - required
/// - dn: display name
/// - tr: tracker URL
/// - xl: exact length
///
/// Example:
/// ```dart
/// var magnet = MagnetParser.parse('magnet:?xt=urn:btih:...&dn=example&tr=...');
/// ```
class MagnetParser {
  /// Parse a magnet URI string
  ///
  /// Returns null if the URI is invalid or missing required parameters
  static MagnetLink? parse(String magnetUri) {
    try {
      if (!magnetUri.startsWith('magnet:?')) {
        _log.warning('Invalid magnet URI format: must start with "magnet:?"');
        return null;
      }

      final uri = Uri.parse(magnetUri);
      // Parse query parameters manually to handle multiple 'tr' parameters
      final params = <String, String>{};
      final queryString = uri.query;
      if (queryString.isNotEmpty) {
        final pairs = queryString.split('&');
        for (final pair in pairs) {
          final parts = pair.split('=');
          if (parts.length == 2) {
            final key = Uri.decodeComponent(parts[0]);
            final value = Uri.decodeComponent(parts[1]);
            // For multiple 'tr' parameters, combine them with comma
            if (key == 'tr' && params.containsKey('tr')) {
              params['tr'] = '${params['tr']},$value';
            } else {
              params[key] = value;
            }
          }
        }
      }

      // Parse info hash from xt parameter (required)
      final xt = params['xt'];
      if (xt == null || xt.isEmpty) {
        _log.warning('Magnet URI missing required "xt" parameter');
        return null;
      }

      Uint8List? infoHash;
      if (xt.startsWith('urn:btih:')) {
        // Hex format: urn:btih:40-character hex string
        final hexHash = xt.substring(9);
        if (hexHash.length == 40) {
          infoHash = _hexToBytes(hexHash);
        } else if (hexHash.length == 32) {
          // Base32 format - would need base32 decoder
          _log.warning('Base32 info hash format not yet supported');
          return null;
        } else {
          _log.warning('Invalid info hash length: ${hexHash.length}');
          return null;
        }
      } else if (xt.startsWith('urn:sha1:')) {
        // SHA1 format
        final hexHash = xt.substring(9);
        if (hexHash.length == 40) {
          infoHash = _hexToBytes(hexHash);
        } else {
          _log.warning('Invalid SHA1 hash length: ${hexHash.length}');
          return null;
        }
      } else {
        _log.warning('Unsupported xt format: $xt');
        return null;
      }

      if (infoHash.length != 20) {
        _log.warning(
            'Invalid info hash: must be 20 bytes, got ${infoHash.length}');
        return null;
      }

      // Parse display name (URL decode it)
      final displayName =
          params['dn'] != null ? Uri.decodeComponent(params['dn']!) : null;

      // Parse trackers (can be multiple)
      final trackers = <Uri>[];
      final trParams = params['tr'];
      if (trParams != null) {
        // Can be single value or comma-separated
        final trackerUrls =
            trParams.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
        for (final url in trackerUrls) {
          try {
            final trackerUri = Uri.parse(url);
            if (trackerUri.hasScheme &&
                (trackerUri.scheme == 'http' ||
                    trackerUri.scheme == 'https' ||
                    trackerUri.scheme == 'udp')) {
              trackers.add(trackerUri);
            } else {
              _log.warning('Invalid tracker URL: $url');
            }
          } catch (e) {
            _log.warning('Failed to parse tracker URL: $url', e);
          }
        }
      }

      // Also check for multiple tr parameters (some clients use tr.1, tr.2, etc.)
      for (final key in params.keys) {
        if (key.startsWith('tr.') && key.length > 3) {
          try {
            final trackerUri = Uri.parse(params[key]!);
            if (trackerUri.hasScheme &&
                (trackerUri.scheme == 'http' ||
                    trackerUri.scheme == 'https' ||
                    trackerUri.scheme == 'udp')) {
              trackers.add(trackerUri);
            }
          } catch (e) {
            _log.warning(
                'Failed to parse tracker URL from $key: ${params[key]}', e);
          }
        }
      }

      // Parse exact length
      int? exactLength;
      final xl = params['xl'];
      if (xl != null && xl.isNotEmpty) {
        exactLength = int.tryParse(xl);
        if (exactLength == null) {
          _log.warning('Invalid exact length: $xl');
        }
      }

      return MagnetLink(
        infoHash: infoHash,
        displayName: displayName,
        trackers: trackers,
        exactLength: exactLength,
      );
    } catch (e, stackTrace) {
      _log.warning('Failed to parse magnet URI: $magnetUri', e, stackTrace);
      return null;
    }
  }

  /// Convert hex string to bytes
  static Uint8List _hexToBytes(String hex) {
    if (hex.length % 2 != 0) {
      throw ArgumentError('Hex string must have even length');
    }
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      bytes[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }

  /// Create a magnet URI from a MagnetLink
  static String toUri(MagnetLink magnet) {
    final buffer = StringBuffer('magnet:?');
    buffer.write('xt=urn:btih:${magnet.infoHashString}');

    if (magnet.displayName != null && magnet.displayName!.isNotEmpty) {
      buffer.write('&dn=${Uri.encodeComponent(magnet.displayName!)}');
    }

    for (var i = 0; i < magnet.trackers.length; i++) {
      buffer.write('&tr=${Uri.encodeComponent(magnet.trackers[i].toString())}');
    }

    if (magnet.exactLength != null) {
      buffer.write('&xl=${magnet.exactLength}');
    }

    return buffer.toString();
  }
}
