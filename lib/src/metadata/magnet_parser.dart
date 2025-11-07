import 'dart:typed_data';

import 'package:logging/logging.dart';

var _log = Logger('MagnetParser');

/// Tracker tier - group of trackers that should be tried together (BEP 0012)
class TrackerTier {
  /// Trackers in this tier
  final List<Uri> trackers;

  TrackerTier(this.trackers);

  @override
  String toString() => 'TrackerTier(${trackers.length} trackers)';
}

/// Parsed magnet link data
class MagnetLink {
  /// Info hash (20 bytes)
  final Uint8List infoHash;

  /// Display name
  final String? displayName;

  /// Trackers (announce URLs) - flat list for backward compatibility
  final List<Uri> trackers;

  /// Trackers grouped by tiers (BEP 0012)
  /// If tiers are not specified, all trackers are in a single tier
  final List<TrackerTier> trackerTiers;

  /// Exact length (if specified)
  final int? exactLength;

  /// Web seed URLs (BEP 0019)
  /// Parameter 'ws' (Web Seed) - URLs for HTTP/FTP seeding
  final List<Uri> webSeeds;

  /// Acceptable source URLs (BEP 0019)
  /// Parameter 'as' (Acceptable Source) - direct file URLs
  final List<Uri> acceptableSources;

  /// Selected file indices (BEP 0053)
  /// Parameter 'so' (select only) - indices of files to download
  final List<int>? selectedFileIndices;

  /// Info hash as hex string
  String get infoHashString {
    return infoHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  MagnetLink({
    required this.infoHash,
    this.displayName,
    List<Uri>? trackers,
    List<TrackerTier>? trackerTiers,
    this.exactLength,
    List<Uri>? webSeeds,
    List<Uri>? acceptableSources,
    this.selectedFileIndices,
  })  : trackers = trackers ?? [],
        trackerTiers = trackerTiers ??
            (trackers != null && trackers.isNotEmpty
                ? [TrackerTier(trackers)]
                : []),
        webSeeds = webSeeds ?? [],
        acceptableSources = acceptableSources ?? [];

  @override
  String toString() {
    final parts = <String>[
      'infoHash: $infoHashString',
      'name: $displayName',
      'trackers: ${trackers.length}',
      'tiers: ${trackerTiers.length}',
    ];
    if (webSeeds.isNotEmpty) {
      parts.add('webSeeds: ${webSeeds.length}');
    }
    if (acceptableSources.isNotEmpty) {
      parts.add('acceptableSources: ${acceptableSources.length}');
    }
    if (selectedFileIndices != null) {
      parts.add('selectedFiles: ${selectedFileIndices!.length}');
    }
    return 'MagnetLink(${parts.join(', ')})';
  }
}

/// Parser for magnet:? URIs
///
/// Supports parameters:
/// - xt: exact topic (info hash) - required
/// - dn: display name
/// - tr: tracker URL (can be multiple, supports tr.1, tr.2 for tiers - BEP 0012)
/// - xl: exact length
/// - ws: web seed URL (BEP 0019) - HTTP/FTP seeding
/// - as: acceptable source URL (BEP 0019) - direct file URLs
/// - so: select only file index (BEP 0053) - can be multiple
///
/// Example:
/// ```dart
/// var magnet = MagnetParser.parse('magnet:?xt=urn:btih:...&dn=example&tr=...&ws=...&so=0&so=2');
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
      // Parse query parameters manually to handle multiple parameters
      final params = <String, String>{};
      final multiValueParams =
          <String, List<String>>{}; // For so, ws, as parameters
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
            } else if (key == 'so' || key == 'ws' || key == 'as') {
              // Collect multiple values for so, ws, as parameters
              multiValueParams.putIfAbsent(key, () => []).add(value);
              // Also store in params for backward compatibility
              if (!params.containsKey(key)) {
                params[key] = value;
              }
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
          // Base32 format (RFC 4648)
          try {
            infoHash = _base32ToBytes(hexHash);
            if (infoHash.length != 20) {
              _log.warning(
                  'Invalid base32 decoded length: expected 20 bytes, got ${infoHash.length}');
              return null;
            }
          } catch (e) {
            _log.warning('Failed to decode base32 hash: $hexHash', e);
            return null;
          }
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

      // Parse trackers with support for tiers (BEP 0012)
      // Trackers can be:
      // 1. Multiple 'tr' parameters (all in one tier)
      // 2. 'tr.1', 'tr.2', etc. (different tiers)
      final trackers = <Uri>[];
      final trackerTiers = <TrackerTier>[];
      final tierMap = <int, List<Uri>>{};

      // First, collect all trackers from 'tr' parameter (tier 0)
      final trParams = params['tr'];
      if (trParams != null) {
        final tier0Trackers = <Uri>[];
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
              tier0Trackers.add(trackerUri);
            } else {
              _log.warning('Invalid tracker URL: $url');
            }
          } catch (e) {
            _log.warning('Failed to parse tracker URL: $url', e);
          }
        }
        if (tier0Trackers.isNotEmpty) {
          tierMap[0] = tier0Trackers;
        }
      }

      // Parse numbered tracker parameters (tr.1, tr.2, etc.) - each is a separate tier
      for (final key in params.keys) {
        if (key.startsWith('tr.') && key.length > 3) {
          try {
            final tierNumberStr = key.substring(3);
            final tierNumber = int.tryParse(tierNumberStr);
            if (tierNumber == null) continue;

            final trackerUri = Uri.parse(params[key]!);
            if (trackerUri.hasScheme &&
                (trackerUri.scheme == 'http' ||
                    trackerUri.scheme == 'https' ||
                    trackerUri.scheme == 'udp')) {
              trackers.add(trackerUri);
              tierMap.putIfAbsent(tierNumber, () => []).add(trackerUri);
            }
          } catch (e) {
            _log.warning(
                'Failed to parse tracker URL from $key: ${params[key]}', e);
          }
        }
      }

      // Build tracker tiers
      if (tierMap.isNotEmpty) {
        // Sort tiers by number and create TrackerTier objects
        final sortedTierNumbers = tierMap.keys.toList()..sort();
        for (final tierNumber in sortedTierNumbers) {
          trackerTiers.add(TrackerTier(tierMap[tierNumber]!));
        }
      } else if (trackers.isNotEmpty) {
        // If no tiers specified, put all trackers in one tier
        trackerTiers.add(TrackerTier(trackers));
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

      // Parse web seeds (BEP 0019) - parameter 'ws'
      final webSeeds = <Uri>[];
      // Use multiValueParams if available, otherwise fall back to params
      final wsValues = multiValueParams['ws'] ??
          (params['ws'] != null ? [params['ws']!] : []);
      for (final url in wsValues) {
        try {
          final wsUri = Uri.parse(url);
          if (wsUri.hasScheme &&
              (wsUri.scheme == 'http' ||
                  wsUri.scheme == 'https' ||
                  wsUri.scheme == 'ftp')) {
            webSeeds.add(wsUri);
          } else {
            _log.warning('Invalid web seed URL: $url');
          }
        } catch (e) {
          _log.warning('Failed to parse web seed URL: $url', e);
        }
      }
      // Also check for numbered ws parameters (ws.1, ws.2, etc.)
      for (final key in params.keys) {
        if (key.startsWith('ws.') && key.length > 3) {
          try {
            final wsUri = Uri.parse(params[key]!);
            if (wsUri.hasScheme &&
                (wsUri.scheme == 'http' ||
                    wsUri.scheme == 'https' ||
                    wsUri.scheme == 'ftp')) {
              webSeeds.add(wsUri);
            }
          } catch (e) {
            _log.warning(
                'Failed to parse web seed URL from $key: ${params[key]}', e);
          }
        }
      }

      // Parse acceptable sources (BEP 0019) - parameter 'as'
      final acceptableSources = <Uri>[];
      // Use multiValueParams if available, otherwise fall back to params
      final asValues = multiValueParams['as'] ??
          (params['as'] != null ? [params['as']!] : []);
      for (final url in asValues) {
        try {
          final asUri = Uri.parse(url);
          if (asUri.hasScheme &&
              (asUri.scheme == 'http' ||
                  asUri.scheme == 'https' ||
                  asUri.scheme == 'ftp')) {
            acceptableSources.add(asUri);
          } else {
            _log.warning('Invalid acceptable source URL: $url');
          }
        } catch (e) {
          _log.warning('Failed to parse acceptable source URL: $url', e);
        }
      }
      // Also check for numbered as parameters (as.1, as.2, etc.)
      for (final key in params.keys) {
        if (key.startsWith('as.') && key.length > 3) {
          try {
            final asUri = Uri.parse(params[key]!);
            if (asUri.hasScheme &&
                (asUri.scheme == 'http' ||
                    asUri.scheme == 'https' ||
                    asUri.scheme == 'ftp')) {
              acceptableSources.add(asUri);
            }
          } catch (e) {
            _log.warning(
                'Failed to parse acceptable source URL from $key: ${params[key]}',
                e);
          }
        }
      }

      // Parse selected file indices (BEP 0053) - parameter 'so'
      final selectedFileIndices = <int>[];
      // Use multiValueParams if available, otherwise fall back to params
      final soValues = multiValueParams['so'] ??
          (params['so'] != null ? [params['so']!] : []);
      for (final value in soValues) {
        if (value.isNotEmpty) {
          final index = int.tryParse(value);
          if (index != null && index >= 0) {
            selectedFileIndices.add(index);
          } else {
            _log.warning('Invalid file index in so parameter: $value');
          }
        }
      }
      // Also check for numbered so parameters (so.1, so.2, etc.)
      for (final key in params.keys) {
        if (key.startsWith('so.') && key.length > 3) {
          final value = params[key];
          if (value != null && value.isNotEmpty) {
            final index = int.tryParse(value);
            if (index != null && index >= 0) {
              selectedFileIndices.add(index);
            } else {
              _log.warning('Invalid file index in $key: $value');
            }
          }
        }
      }
      // Remove duplicates and sort
      final uniqueIndices = selectedFileIndices.toSet().toList()..sort();
      final finalSelectedIndices =
          uniqueIndices.isNotEmpty ? uniqueIndices : null;

      return MagnetLink(
        infoHash: infoHash,
        displayName: displayName,
        trackers: trackers,
        trackerTiers: trackerTiers,
        exactLength: exactLength,
        webSeeds: webSeeds,
        acceptableSources: acceptableSources,
        selectedFileIndices: finalSelectedIndices,
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

  /// Convert base32 string to bytes (RFC 4648)
  ///
  /// Base32 alphabet: A-Z, 2-7 (case-insensitive)
  static Uint8List _base32ToBytes(String base32) {
    // Base32 alphabet: A-Z (0-25), 2-7 (26-31)
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final upperBase32 = base32.toUpperCase();

    // Validate characters
    for (var i = 0; i < upperBase32.length; i++) {
      if (!alphabet.contains(upperBase32[i])) {
        throw ArgumentError('Invalid base32 character: ${upperBase32[i]}');
      }
    }

    // Calculate output size: 32 chars = 20 bytes (32 * 5 bits / 8)
    final outputSize = (base32.length * 5) ~/ 8;
    final bytes = Uint8List(outputSize);

    var buffer = 0;
    var bitsLeft = 0;
    var outputIndex = 0;

    for (var i = 0; i < upperBase32.length; i++) {
      final charValue = alphabet.indexOf(upperBase32[i]);
      if (charValue == -1) {
        throw ArgumentError('Invalid base32 character: ${upperBase32[i]}');
      }

      buffer = (buffer << 5) | charValue;
      bitsLeft += 5;

      if (bitsLeft >= 8) {
        bytes[outputIndex++] = (buffer >> (bitsLeft - 8)) & 0xFF;
        bitsLeft -= 8;
      }
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

    for (var webSeed in magnet.webSeeds) {
      buffer.write('&ws=${Uri.encodeComponent(webSeed.toString())}');
    }

    for (var acceptableSource in magnet.acceptableSources) {
      buffer.write('&as=${Uri.encodeComponent(acceptableSource.toString())}');
    }

    if (magnet.selectedFileIndices != null) {
      for (var index in magnet.selectedFileIndices!) {
        buffer.write('&so=$index');
      }
    }

    return buffer.toString();
  }
}
