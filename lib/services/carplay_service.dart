import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';
import 'audio_service_helper.dart';
import 'finamp_settings_helper.dart';
import 'jellyfin_api_helper.dart';

/// Handles the native CarPlay ↔ Flutter MethodChannel bridge.
///
/// Swift calls into Dart for data (getEnabledTabs, getItems) and
/// playback (playItems). A short-lived in-process cache maps item IDs
/// back to their full [BaseItemDto] so playback works without re-fetching.
class CarPlayService {
  static const _channel = MethodChannel('com.moonie.angleramp/carplay');

  final _jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
  final _audioServiceHelper = GetIt.instance<AudioServiceHelper>();
  final _log = Logger('CarPlayService');

  /// Short-lived cache: populated on every `getItems` call so that
  /// `playItems` can reconstruct the full [BaseItemDto] by ID.
  final Map<String, BaseItemDto> _itemCache = {};

  void initialize() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  // ── dispatch ─────────────────────────────────────────────────────────────

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'getEnabledTabs':
          return _getEnabledTabs();
        case 'getItems':
          return await _getItems(
              Map<Object?, Object?>.from(call.arguments as Map));
        case 'playItems':
          await _playItems(Map<Object?, Object?>.from(call.arguments as Map));
          return null;
        default:
          throw PlatformException(
            code: 'NOT_IMPLEMENTED',
            message: 'Method "${call.method}" not implemented',
          );
      }
    } catch (e, st) {
      _log.severe('CarPlay method ${call.method} failed', e, st);
      rethrow;
    }
  }

  // ── getEnabledTabs ────────────────────────────────────────────────────────

  /// Returns the user's enabled tabs in their configured order, excluding
  /// Genres (which has no direct CarPlay equivalent) as strings like
  /// "albums", "artists", etc.
  List<String> _getEnabledTabs() {
    final settings = FinampSettingsHelper.finampSettings;
    return settings.tabOrder
        .where((tab) => settings.showTabs[tab] ?? true)
        .map(_tabToString)
        .whereType<String>()
        .toList();
  }

  String? _tabToString(TabContentType tab) {
    switch (tab) {
      case TabContentType.albums:
        return 'albums';
      case TabContentType.artists:
        return 'artists';
      case TabContentType.songs:
        return 'songs';
      case TabContentType.playlists:
        return 'playlists';
      case TabContentType.audiobooks:
        return 'audiobooks';
      case TabContentType.folders:
        return 'folders';
      case TabContentType.genres:
        // CarPlay shows no Genres tab – genres are accessed by drilling from
        // Artists in supported apps; we skip them here.
        return null;
    }
  }

  // ── getItems ──────────────────────────────────────────────────────────────

  Future<List<Map<String, Object?>>> _getItems(
      Map<Object?, Object?> args) async {
    final tabType    = args['tabType']    as String? ?? 'albums';
    final parentId   = args['parentId']   as String?;
    final parentType = args['parentType'] as String?;
    final parentPath = args['parentPath'] as String?;

    // Reconstruct a minimal parent so JellyfinApiHelper's switch logic works.
    BaseItemDto? parentItem;
    if (parentId != null && parentType != null) {
      parentItem = BaseItemDto(
        id: parentId,
        type: parentType,
        path: parentPath,
      );
    }

    final items = await _jellyfinApiHelper.getItems(
      parentItem: parentItem,
      includeItemTypes: _tabToIncludeItemTypes(tabType, parentType: parentType),
      isGenres: tabType == 'genres',
      sortBy: _sortBy(tabType, parentType: parentType),
      sortOrder: 'Ascending',
    );

    if (items == null) return [];

    // Populate cache so playItems can look up full DTOs.
    for (final item in items) {
      _itemCache[item.id] = item;
    }

    return items.map(_toMap).toList();
  }

  Map<String, Object?> _toMap(BaseItemDto item) {
    final imageUrl = _jellyfinApiHelper.getImageUrl(
      item: item,
      maxWidth: 200,
      maxHeight: 200,
    )?.toString();

    return {
      'id': item.id,
      'name': item.name ?? '',
      'type': item.type ?? '',
      'albumArtist': item.albumArtist,
      'artists': item.artists ?? const <String>[],
      'imageUrl': imageUrl,
      // path is needed so CarPlay can pass it back when drilling into folders
      'path': item.path,
    };
  }

  String? _tabToIncludeItemTypes(String tabType, {String? parentType}) {
    // When drilling into an artist, we want albums.
    // When drilling into a genre, we want albums.
    // The parentType branch handles the switch inside JellyfinApiHelper.
    switch (tabType) {
      case 'songs':
        return 'Audio';
      case 'albums':
        return 'MusicAlbum';
      case 'artists':
        return 'MusicArtist';
      case 'genres':
        return 'MusicGenre';
      case 'playlists':
        return 'Playlist';
      case 'audiobooks':
        return 'AudioBook';
      case 'folders':
        return 'Folder';
      default:
        return null;
    }
  }

  String _sortBy(String tabType, {String? parentType}) {
    // Track lists inside an album / playlist / audiobook
    // must be sorted by disc + track number.
    if (tabType == 'songs' ||
        parentType == 'MusicAlbum' ||
        parentType == 'Playlist' ||
        parentType == 'AudioBook') {
      return 'ParentIndexNumber,IndexNumber,SortName';
    }
    return 'SortName';
  }

  // ── playItems ─────────────────────────────────────────────────────────────

  /// Receives a list of item maps (as returned by getItems) and a startIndex.
  /// Uses the ID cache to look up full [BaseItemDto] objects, then hands off
  /// to [AudioServiceHelper.replaceQueueWithItem].
  Future<void> _playItems(Map<Object?, Object?> args) async {
    final rawItems   = args['items']      as List<Object?>;
    final startIndex = args['startIndex'] as int? ?? 0;

    final items = rawItems
        .whereType<Map<Object?, Object?>>()
        .map((m) => m['id'] as String?)
        .whereType<String>()
        .map((id) => _itemCache[id])
        .whereType<BaseItemDto>()
        .toList();

    if (items.isEmpty) {
      _log.warning('playItems: no items resolved from cache');
      return;
    }

    final safeIndex = startIndex.clamp(0, items.length - 1);
    await _audioServiceHelper.replaceQueueWithItem(
      itemList: items,
      initialIndex: safeIndex,
    );
  }
}
