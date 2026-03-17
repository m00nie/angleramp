import 'package:finamp/components/AlbumScreen/sync_album_or_playlist_button.dart';
import 'package:finamp/services/downloads_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:get_it/get_it.dart';

import '../../models/jellyfin_models.dart';
import '../../services/finamp_settings_helper.dart';
import '../../components/favourite_button.dart';
import '../../components/MusicScreen/album_item.dart';
import 'album_screen_content_flexible_space_bar.dart';
import 'delete_button.dart';
import 'song_list_tile.dart';
import 'playlist_name_edit_button.dart';

typedef BaseItemDtoCallback = void Function(BaseItemDto item);

class AlbumScreenContent extends StatefulWidget {
  const AlbumScreenContent({
    Key? key,
    required this.parent,
    required this.children,
  }) : super(key: key);

  final BaseItemDto parent;
  final List<BaseItemDto> children;

  @override
  State<AlbumScreenContent> createState() => _AlbumScreenContentState();
}

class _AlbumScreenContentState extends State<AlbumScreenContent> {
  @override
  Widget build(BuildContext context) {
    void onDelete(BaseItemDto item) {
      // This is pretty inefficient (has to search through whole list) but
      // SongsSliverList gets passed some weird split version of children to
      // handle multi-disc albums and it's 00:35 so I can't be bothered to get
      // it to return an index
      setState(() {
        widget.children.remove(item);
      });
    }

    List<List<BaseItemDto>> childrenPerDisc = [];

    // Separate audio-only children for the playback queue (Folder items must
    // not appear in the queue).
    final audioChildren =
        widget.children.where((c) => c.type != "Folder").toList();

    // Split into per-disc groups for multi-disc albums (skip for Folder/Playlist parents).
    if (widget.parent.type != "Playlist" &&
        widget.parent.type != "Folder" &&
        widget.children.isNotEmpty &&
        audioChildren.isNotEmpty &&
        audioChildren[0].parentIndexNumber != null) {
      int? lastDiscNumber;
      for (var child in widget.children) {
        if (child.parentIndexNumber != null &&
            child.parentIndexNumber != lastDiscNumber) {
          lastDiscNumber = child.parentIndexNumber;
          childrenPerDisc.add([]);
        }
        childrenPerDisc.last.add(child);
      }
    }

    return Scrollbar(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(widget.parent.name ??
                AppLocalizations.of(context)!.unknownName),
            // 125 + 64 is the total height of the widget we use as a
            // FlexibleSpaceBar. We add the toolbar height since the widget
            // should appear below the appbar.
            // TODO: This height is affected by platform density.
            expandedHeight: kToolbarHeight + 125 + 64,
            pinned: true,
            flexibleSpace: AlbumScreenContentFlexibleSpaceBar(
              album: widget.parent,
              items: audioChildren,
            ),
            actions: [
              if (widget.parent.type == "Playlist" &&
                  !FinampSettingsHelper.finampSettings.isOffline)
                PlaylistNameEditButton(playlist: widget.parent),
              if (widget.parent.type != "Folder")
                FavoriteButton(item: widget.parent),
              if (widget.parent.type != "Folder" &&
                  GetIt.instance<DownloadsHelper>().isAlbumDownloaded(widget.parent.id))
                DeleteButton(parent: widget.parent, items: widget.children),
              if (widget.parent.type != "Folder" &&
                  !FinampSettingsHelper.finampSettings.isOffline)
                SyncAlbumOrPlaylistButton(parent: widget.parent, items: widget.children)
            ],
          ),
          if (widget.children.length > 1 &&
              childrenPerDisc.length >
                  1) // show headers only for multi disc albums
            for (var childrenOfThisDisc in childrenPerDisc)
              SliverStickyHeader(
                header: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 16.0,
                  ),
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: Text(
                    AppLocalizations.of(context)!
                        .discNumber(childrenOfThisDisc[0].parentIndexNumber!),
                    style: const TextStyle(fontSize: 20.0),
                  ),
                ),
                sliver: SongsSliverList(
                  childrenForList: childrenOfThisDisc,
                  childrenForQueue: audioChildren,
                  parent: widget.parent,
                  onDelete: onDelete,
                ),
              )
          else if (widget.children.isNotEmpty)
            SongsSliverList(
              childrenForList: widget.children,
              childrenForQueue: audioChildren,
              parent: widget.parent,
              onDelete: onDelete,
            ),
        ],
      ),
    );
  }
}

class SongsSliverList extends StatefulWidget {
  const SongsSliverList({
    Key? key,
    required this.childrenForList,
    required this.childrenForQueue,
    required this.parent,
    this.onDelete,
  }) : super(key: key);

  final List<BaseItemDto> childrenForList;
  final List<BaseItemDto> childrenForQueue;
  final BaseItemDto parent;
  final BaseItemDtoCallback? onDelete;

  @override
  State<SongsSliverList> createState() => _SongsSliverListState();
}

class _SongsSliverListState extends State<SongsSliverList> {
  final GlobalKey<SliverAnimatedListState> sliverListKey =
      GlobalKey<SliverAnimatedListState>();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          final BaseItemDto item = widget.childrenForList[index];

          // Folder items drill deeper into the directory hierarchy.
          if (item.type == "Folder") {
            return AlbumItem(album: item, isGrid: false);
          }

          BaseItemDto removeItem() {
            late BaseItemDto item;

            setState(() {
              item = widget.childrenForList.removeAt(index);
            });

            return item;
          }

          // Audio item: find its position in the queue for correct playback.
          final queueIndex = widget.childrenForQueue.indexOf(item);

          return SongListTile(
            item: item,
            children: widget.childrenForQueue,
            index: queueIndex >= 0 ? queueIndex : 0,
            parentId: widget.parent.id,
            onDelete: () {
              final item = removeItem();
              if (widget.onDelete != null) {
                widget.onDelete!(item);
              }
            },
            isInPlaylist: widget.parent.type == "Playlist",
            // show artists except for this one scenario
            showArtists: !(
                // we're on album screen
                widget.parent.type == "MusicAlbum"
                    // "hide song artists if they're the same as album artists" == true
                    &&
                    FinampSettingsHelper
                        .finampSettings.hideSongArtistsIfSameAsAlbumArtists
                    // song artists == album artists
                    &&
                    setEquals(
                        widget.parent.albumArtists?.map((e) => e.name).toSet(),
                        item.artists?.toSet())),
          );
        },
        childCount: widget.childrenForList.length,
      ),
    );
  }
}