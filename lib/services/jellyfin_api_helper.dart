import 'package:chopper/chopper.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'finamp_user_helper.dart';
import 'jellyfin_api.dart';
import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';

class JellyfinApiHelper {
  final jellyfinApi = JellyfinApi.create();
  final _jellyfinApiHelperLogger = Logger("JellyfinApiHelper");

  // Stores the ids of the artists that the user selected to mix
  List<String> selectedMixArtistsIds = [];

  // Stores the ids of albums that the user selected to mix
  List<String> selectedMixAlbumIds = [];

  Uri? baseUrlTemp;

  final _finampUserHelper = GetIt.instance<FinampUserHelper>();

  Future<List<BaseItemDto>?> getItems({
    BaseItemDto? parentItem,
    String? includeItemTypes,
    String? sortBy,
    String? sortOrder,
    String? searchTerm,
    required bool isGenres,
    String? filters,
    String? mediaTypes,

    /// The record index to start at. All items with a lower index will be
    /// dropped from the results.
    int? startIndex,

    /// The maximum number of records to return.
    int? limit,
  }) async {
    final currentUser = _finampUserHelper.currentUser;
    if (currentUser == null) {
      // When logging out, this request causes errors since currentUser is
      // required sometimes. We just return an empty list since this error
      // usually happens becuase the listeners on MusicScreenTabView update
      // milliseconds before the page is popped. This shouldn't happen in normal
      // use.
      return [];
    }

    var response;

    // We send a different request for playlists so that we get them back in the
    // right order. Doing this in the same function makes sense since they both
    // return the same thing. It also means we can easily share album widgets
    // with playlists.
    if (parentItem?.type == "Playlist") {
      response = await jellyfinApi.getPlaylistItems(
        playlistId: parentItem!.id,
        userId: currentUser.id,
        parentId: parentItem.id,
        includeItemTypes: includeItemTypes,
        recursive: true,
      );
    } else if (includeItemTypes == "MusicArtist") {
      // For artists, we need to use a different endpoint
      response = await jellyfinApi.getAlbumArtists(
        parentId: parentItem?.id,
        recursive: true,
        sortBy: sortBy,
        sortOrder: sortOrder,
        searchTerm: searchTerm,
        filters: filters,
        startIndex: startIndex,
        limit: limit,
        userId: currentUser.id,
      );
    } else if (parentItem?.type == "MusicArtist") {
      // For getting the children of artists, we need to use albumArtistIds
      // instead of parentId
      response = await jellyfinApi.getItems(
        userId: currentUser.id,
        albumArtistIds: parentItem?.id,
        includeItemTypes: includeItemTypes,
        recursive: true,
        sortBy: sortBy,
        sortOrder: sortOrder,
        searchTerm: searchTerm,
        filters: filters,
        startIndex: startIndex,
        limit: limit,
        mediaTypes: mediaTypes,
      );

    } else if (includeItemTypes == "MusicGenre") {
      response = await jellyfinApi.getGenres(
        parentId: parentItem?.id,
        // includeItemTypes: includeItemTypes,
        searchTerm: searchTerm,
        startIndex: startIndex,
        limit: limit,
      );
    } else if (parentItem?.type == "MusicGenre") {
      response = await jellyfinApi.getItems(
        userId: currentUser.id,
        genreIds: parentItem?.id,
        includeItemTypes: includeItemTypes,
        recursive: true,
        sortBy: sortBy,
        sortOrder: sortOrder,
        searchTerm: searchTerm,
        filters: filters,
        startIndex: startIndex,
        limit: limit,
        mediaTypes: mediaTypes,
      );
    } else if (parentItem?.type == "MusicAlbum" && includeItemTypes == "Audio") {
      // A folder can contain a mix of:
      //   - Properly tagged tracks whose albumId metadata points to this container
      //     → found via AlbumIds query
      //   - Untagged / YouTube-ripped tracks with no album metadata at all
      //     → only found via ParentId query (without IncludeItemTypes, which
      //       Jellyfin ignores for untagged items when combined with ParentId)
      // We always run BOTH queries and merge, so all tracks appear regardless
      // of how patchy the metadata is.

      // Query 1: AlbumIds — picks up tagged tracks
      final albumIdsResponse = await jellyfinApi.getItems(
        userId: currentUser.id,
        albumIds: parentItem!.id,
        includeItemTypes: includeItemTypes,
        recursive: true,
        sortBy: sortBy,
        sortOrder: sortOrder,
        searchTerm: searchTerm,
        filters: filters,
        mediaTypes: mediaTypes,
      );
      final albumIdsTracks =
          QueryResult_BaseItemDto.fromJson(albumIdsResponse).items ?? [];

      // Query 2: ParentId without type filter — picks up untagged tracks;
      // filter to Audio client-side.
      final parentIdResponse = await jellyfinApi.getItems(
        userId: currentUser.id,
        parentId: parentItem.id,
        recursive: true,
        sortBy: sortBy,
        sortOrder: sortOrder,
        searchTerm: searchTerm,
        filters: filters,
        mediaTypes: mediaTypes,
      );
      final parentIdTracks =
          (QueryResult_BaseItemDto.fromJson(parentIdResponse).items ?? [])
              .where((item) => item.type == "Audio")
              .toList();

      // Merge, deduplicating by id (AlbumIds results take precedence so their
      // richer metadata is kept when a track appears in both result sets).
      final seen = <String>{};
      final merged = <BaseItemDto>[];
      for (final track in [...albumIdsTracks, ...parentIdTracks]) {
        if (seen.add(track.id)) merged.add(track);
      }
      return merged;
    } else if (parentItem?.type == "Folder") {
      // Hierarchical directory browse: show sub-folders + audio files that
      // live directly inside this folder (not nested deeper).
      //
      // Both are derived from the full recursive audio list filtered by path,
      // because Jellyfin's virtual parentId for audio is unreliable for
      // untagged/YouTube tracks and sub-folder items may not surface correctly
      // via IncludeItemTypes=Folder when parentId is a synthetic item.
      final folderPath = parentItem!.path;
      final viewId = currentUser.currentViewId;

      if (folderPath == null || viewId == null) return [];

      final allAudioResponse = await jellyfinApi.getItems(
        userId: currentUser.id,
        parentId: viewId,
        includeItemTypes: "Audio",
        recursive: true,
        sortBy: sortBy,
        sortOrder: sortOrder,
        searchTerm: searchTerm,
        filters: filters,
        mediaTypes: mediaTypes,
      );
      final allAudio =
          QueryResult_BaseItemDto.fromJson(allAudioResponse).items ?? [];

      final pathPrefix =
          folderPath.endsWith("/") ? folderPath : "$folderPath/";

      // Group tracks by their immediate sub-directory to aggregate duration.
      final directAudio = <BaseItemDto>[];
      final dirTracksMap = <String, List<BaseItemDto>>{};

      for (final track in allAudio) {
        final p = track.path;
        if (p == null || !p.startsWith(pathPrefix)) continue;
        final relative = p.substring(pathPrefix.length);
        final slashIdx = relative.indexOf("/");
        if (slashIdx < 0) {
          directAudio.add(track);
        } else {
          final dirName = relative.substring(0, slashIdx);
          final dirPath = "$pathPrefix$dirName";
          dirTracksMap.putIfAbsent(dirPath, () => []).add(track);
        }
      }

      final subFolders = dirTracksMap.entries.map((entry) {
        final dirPath = entry.key;
        final dirName = dirPath.substring(pathPrefix.length);
        final totalTicks = entry.value
            .fold<int>(0, (sum, t) => sum + (t.runTimeTicks ?? 0));
        return BaseItemDto(
          id: "synthetic-folder-${dirPath.hashCode}",
          name: dirName,
          type: "Folder",
          path: dirPath,
          runTimeTicks: totalTicks,
        );
      }).toList();

      subFolders.sort((a, b) =>
          (a.name ?? "").toLowerCase().compareTo((b.name ?? "").toLowerCase()));
      return [...subFolders, ...directAudio];
    } else if (includeItemTypes == "Folder") {
      // Top-level Folders tab. Jellyfin's CollectionFolder (library view)
      // doesn't expose physical sub-folders as direct children via the Items
      // API. Derive the folder structure from audio item paths instead.
      final viewId = currentUser.currentViewId;
      if (viewId == null) return [];

      final allAudioResponse = await jellyfinApi.getItems(
        userId: currentUser.id,
        parentId: viewId,
        includeItemTypes: "Audio",
        recursive: true,
        sortBy: "SortName",
        searchTerm: searchTerm,
      );
      final allTracks =
          QueryResult_BaseItemDto.fromJson(allAudioResponse).items ?? [];
      if (allTracks.isEmpty) return [];

      final trackPaths =
          allTracks.map((t) => t.path).whereType<String>().toList();
      if (trackPaths.isEmpty) return [];
      final prefix = _commonPathPrefix(trackPaths);

      final seen = <String>{};
      // Use a map to accumulate runTimeTicks per directory.
      final dirTicksMap = <String, int>{};
      for (final track in allTracks) {
        final p = track.path;
        if (p == null || !p.startsWith(prefix)) continue;
        final relative = p.substring(prefix.length);
        final slashIdx = relative.indexOf("/");
        if (slashIdx < 0) continue; // track directly at library root
        final dirName = relative.substring(0, slashIdx);
        final dirPath = "$prefix$dirName";
        seen.add(dirPath);
        dirTicksMap[dirPath] =
            (dirTicksMap[dirPath] ?? 0) + (track.runTimeTicks ?? 0);
      }

      final folders = seen.map((dirPath) {
        final dirName = dirPath.substring(prefix.length);
        return BaseItemDto(
          id: "synthetic-folder-${dirPath.hashCode}",
          name: dirName,
          type: "Folder",
          path: dirPath,
          runTimeTicks: dirTicksMap[dirPath] ?? 0,
        );
      }).toList();

      folders.sort((a, b) =>
          (a.name ?? "").toLowerCase().compareTo((b.name ?? "").toLowerCase()));

      if (searchTerm != null && searchTerm.isNotEmpty) {
        final term = searchTerm.toLowerCase();
        return folders
            .where((f) => f.name?.toLowerCase().contains(term) ?? false)
            .toList();
      }
      return folders;
    } else {
      // This will be run when getting albums from a library view, and other
      // general item fetches where parentId is the correct filter.
      response = await jellyfinApi.getItems(
        userId: currentUser.id,
        parentId: parentItem?.id,
        includeItemTypes: includeItemTypes,
        recursive: true,
        sortBy: sortBy,
        sortOrder: sortOrder,
        searchTerm: searchTerm,
        filters: filters,
        startIndex: startIndex,
        limit: limit,
        mediaTypes: mediaTypes,
      );
    }

    return (QueryResult_BaseItemDto.fromJson(response).items);
  }

  /// Authenticates a user and saves the login details
  Future<void> authenticateViaName({
    required String username,
    String? password,
  }) async {
    var response;

    // Some users won't have a password.
    if (password == null) {
      response = await jellyfinApi.authenticateViaName({"Username": username});
    } else {
      response = await jellyfinApi
          .authenticateViaName({"Username": username, "Pw": password});
    }

    AuthenticationResult newUserAuthenticationResult =
        AuthenticationResult.fromJson(response);

    FinampUser newUser = FinampUser(
      id: newUserAuthenticationResult.user!.id,
      baseUrl: baseUrlTemp!.toString(),
      accessToken: newUserAuthenticationResult.accessToken!,
      serverId: newUserAuthenticationResult.serverId!,
      views: {},
    );

    await _finampUserHelper.saveUser(newUser);
  }

  /// Gets all the user's views.
  Future<List<BaseItemDto>> getViews() async {
    var response =
        await jellyfinApi.getViews(_finampUserHelper.currentUser!.id);

    return QueryResult_BaseItemDto.fromJson(response).items!;
  }

  /// Gets the playback info for an item, such as format and bitrate. Usually, I'd require a BaseItemDto as an argument
  /// but since this will be run inside of [MusicPlayerBackgroundTask], I've just set the raw id as an argument.
  Future<List<MediaSourceInfo>?> getPlaybackInfo(String itemId) async {
    var response = await jellyfinApi.getPlaybackInfo(
      id: itemId,
      userId: _finampUserHelper.currentUser!.id,
    );

    // getPlaybackInfo returns a PlaybackInfoResponse. We only need the List<MediaSourceInfo> in it so we convert it here and
    // return that List<MediaSourceInfo>.
    final PlaybackInfoResponse decodedResponse =
        PlaybackInfoResponse.fromJson(response);
    return decodedResponse.mediaSources;
  }

  /// Starts an instant mix using the data from the item provided.
  Future<List<BaseItemDto>?> getInstantMix(BaseItemDto? parentItem) async {
    var response = await jellyfinApi.getInstantMix(
        id: parentItem!.id,
        userId: _finampUserHelper.currentUser!.id,
        limit: 200);

    return (QueryResult_BaseItemDto.fromJson(response).items);
  }

  /// Tells the Jellyfin server that playback has started
  Future<void> reportPlaybackStart(
      PlaybackProgressInfo playbackProgressInfo) async {
    await jellyfinApi.startPlayback(playbackProgressInfo);
  }

  /// Updates player progress so that Jellyfin can track what we're listening to
  Future<void> updatePlaybackProgress(
      PlaybackProgressInfo playbackProgressInfo) async {
      await jellyfinApi.playbackStatusUpdate(playbackProgressInfo);
  }

  /// Tells Jellyfin that we've stopped listening to music (called when the audio service is stopped)
  Future<void> stopPlaybackProgress(
      PlaybackProgressInfo playbackProgressInfo) async {
      await jellyfinApi.playbackStatusStopped(playbackProgressInfo);
  }

  /// Gets an item from a user's library.
  Future<BaseItemDto> getItemById(String itemId) async {
    var response = await jellyfinApi.getItemById(
      userId: _finampUserHelper.currentUser!.id,
      itemId: itemId,
    );

    return (BaseItemDto.fromJson(response));
  }

  /// Creates a new playlist.
  Future<NewPlaylistResponse> createNewPlaylist(NewPlaylist newPlaylist) async {
    var response = await jellyfinApi.createNewPlaylist(
      newPlaylist: newPlaylist,
    );

    return NewPlaylistResponse.fromJson(response);
  }

  /// Adds items to a playlist.
  Future<void> addItemstoPlaylist({
    /// The playlist id.
    required String playlistId,

    /// Item ids to add.
    List<String>? ids,
  }) async {
    await jellyfinApi.addItemsToPlaylist(
      playlistId: playlistId,
      ids: ids?.join(","),
    );
  }

  /// Remove items to a playlist.
  Future<void> removeItemsFromPlaylist({
    /// The playlist id.
    required String playlistId,

    /// Item ids to add.
    List<String>? entryIds,
  }) async {
    await jellyfinApi.removeItemsFromPlaylist(
      playlistId: playlistId,
      entryIds: entryIds?.join(","),
    );
  }

  /// Updates an item.
  Future<void> updateItem({
    /// The item id.
    required String itemId,

    /// What to update the item with. You should give a BaseItemDto with only
    /// changed values.
    required BaseItemDto newItem,
  }) async {
    await jellyfinApi.updateItem(itemId: itemId, newItem: newItem);
  }

  /// Marks an item as a favorite.
  Future<UserItemDataDto> addFavourite(String itemId) async {
    var response = await jellyfinApi.addFavourite(
        userId: _finampUserHelper.currentUser!.id, itemId: itemId);

    return UserItemDataDto.fromJson(response);
  }

  /// Unmarks item as a favorite.
  Future<UserItemDataDto> removeFavourite(String itemId) async {
    var response = await jellyfinApi.removeFavourite(
        userId: _finampUserHelper.currentUser!.id, itemId: itemId);

    return UserItemDataDto.fromJson(response);
  }

  void addArtistToMixBuilderList(BaseItemDto item) {
    selectedMixArtistsIds.add(item.id);
  }

  void removeArtistFromBuilderList(BaseItemDto item) {
    selectedMixArtistsIds.remove(item.id);
  }

  void addAlbumToMixBuilderList(BaseItemDto item) {
    selectedMixAlbumIds.add(item.id);
  }

  void removeAlbumFromBuilderList(BaseItemDto item) {
    selectedMixAlbumIds.remove(item.id);
  }

  Future<List<BaseItemDto>?> getArtistMix(List<String> artistIds) async {
    var response = await jellyfinApi.getItems(
        userId: _finampUserHelper.currentUser!.id,
        artistIds: artistIds.join(","),
        filters: "IsNotFolder",
        recursive: true,
        sortBy: "Random",
        limit: 300,
        fields: "Chapters");

    return (QueryResult_BaseItemDto.fromJson(response).items);
  }

  Future<List<BaseItemDto>?> getAlbumMix(List<String> albumIds) async {
    var response = await jellyfinApi.getItems(
        userId: _finampUserHelper.currentUser!.id,
        albumIds: albumIds.join(","),
        filters: "IsNotFolder",
        recursive: true,
        sortBy: "Random",
        limit: 300,
        fields: "Chapters");

    return (QueryResult_BaseItemDto.fromJson(response).items);
  }

  /// Removes the current user from the DB and revokes the token on Jellyfin
  Future<void> logoutCurrentUser() async {
    // We put this in a try-catch loop that basically ignores errors so that the
    // user can still log out during scenarios like wrong IP, no internet etc.

    try {
      await jellyfinApi.logout().timeout(
            const Duration(seconds: 3),
            onTimeout: () => _jellyfinApiHelperLogger.warning(
                "Logout request timed out. Logging out anyway, but be aware that Jellyfin may have not got the signal."),
          );
    } catch (e) {
      _jellyfinApiHelperLogger.warning(
          "Jellyfin logout failed. Logging out anyway, but be aware that Jellyfin may have not got the signal.",
          e);
    } finally {
      // If we're unauthorised, the logout command will fail but we're already
      // basically logged out so we shouldn't fail.
      _finampUserHelper.removeUser(_finampUserHelper.currentUser!.id);
    }
  }

  /// Returns the correct image URL for the given item, or null if there is no
  /// image. Uses [getImageId] to get the actual id. [maxWidth] and [maxHeight]
  /// can be specified to return a smaller image. [quality] can be modified to
  /// get a higher/lower quality image.
  Uri? getImageUrl({
    required BaseItemDto item,
    int? maxWidth,
    int? maxHeight,
    int? quality = 90,
    String? format = "jpg",
  }) {
    if (item.imageId == null) {
      return null;
    }

    final parsedBaseUrl = Uri.parse(_finampUserHelper.currentUser!.baseUrl);
    List<String> builtPath = List<String>.from(parsedBaseUrl.pathSegments);
    builtPath.addAll([
      "Items",
      item.imageId!,
      "Images",
      "Primary",
    ]);
    return Uri(
        host: parsedBaseUrl.host,
        port: parsedBaseUrl.port,
        scheme: parsedBaseUrl.scheme,
        userInfo: parsedBaseUrl.userInfo,
        pathSegments: builtPath,
        queryParameters: {
          if (format != null) "format": format,
          if (quality != null) "quality": quality.toString(),
          if (maxWidth != null) "MaxWidth": maxWidth.toString(),
          if (maxHeight != null) "MaxHeight": maxHeight.toString(),
        });
  }
}

/// Returns the longest common directory prefix shared by all [paths], always
/// ending with "/" so it can be used as a directory prefix directly.
String _commonPathPrefix(List<String> paths) {
  if (paths.isEmpty) return "";
  // Start with the directory of the first path (trim the filename part).
  final firstSep = paths[0].lastIndexOf("/");
  String prefix = firstSep >= 0 ? paths[0].substring(0, firstSep + 1) : "";

  for (final p in paths.skip(1)) {
    while (prefix.isNotEmpty && !p.startsWith(prefix)) {
      // Strip the trailing "/" before looking for the *parent* separator —
      // without this, lastIndexOf("/") returns prefix.length-1 and
      // substring(0, lastSep+1) produces the same string, looping forever.
      final noTrail =
          prefix.endsWith("/") ? prefix.substring(0, prefix.length - 1) : prefix;
      final lastSep = noTrail.lastIndexOf("/");
      prefix = lastSep > 0 ? noTrail.substring(0, lastSep + 1) : "";
    }
    if (prefix.isEmpty) return "";
  }
  return prefix;
}
