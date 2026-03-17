import 'package:flutter/material.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:get_it/get_it.dart';

import '../../models/jellyfin_models.dart';
import '../../services/audio_service_helper.dart';
import '../../services/downloads_helper.dart';
import '../../services/finamp_settings_helper.dart';
import '../../services/jellyfin_api_helper.dart';
import '../album_image.dart';
import '../AlbumScreen/delete_button.dart';
import '../AlbumScreen/song_list_tile.dart';
import '../AlbumScreen/sync_album_or_playlist_button.dart';
import '../favourite_button.dart';
import '../print_duration.dart';
import 'audiobook_flexible_space_bar.dart';

/// The main content widget for an audiobook screen. Displays the book cover,
/// metadata, and a list of chapters (which are Audio items in Jellyfin).
class AudiobookScreenContent extends StatefulWidget {
  const AudiobookScreenContent({
    Key? key,
    required this.parent,
    required this.chapters,
  }) : super(key: key);

  /// The audiobook (Book item) being displayed.
  final BaseItemDto parent;

  /// The list of Audio items (chapters/tracks) belonging to this book.
  final List<BaseItemDto> chapters;

  @override
  State<AudiobookScreenContent> createState() => _AudiobookScreenContentState();
}

class _AudiobookScreenContentState extends State<AudiobookScreenContent> {
  /// Called when a chapter is deleted from the device, removes it from the
  /// local list so the UI updates without needing a full refresh.
  void _onChapterDeleted(BaseItemDto chapter) {
    setState(() {
      widget.chapters.remove(chapter);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Total runtime of all chapters combined.
    final totalDuration = Duration(
      microseconds: widget.chapters.fold<int>(
        0,
        (sum, chapter) =>
            sum + (chapter.runTimeTicks == null ? 0 : chapter.runTimeTicks! ~/ 10),
      ),
    );

    return Scrollbar(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(
                widget.parent.name ?? AppLocalizations.of(context)!.unknownName),
            // Height matches the flexible space bar content
            expandedHeight: kToolbarHeight + 125 + 64,
            pinned: true,
            flexibleSpace: AudiobookFlexibleSpaceBar(
              audiobook: widget.parent,
              chapters: widget.chapters,
              totalDuration: totalDuration,
            ),
            actions: [
              FavoriteButton(item: widget.parent),
              if (GetIt.instance<DownloadsHelper>()
                  .isAlbumDownloaded(widget.parent.id))
                DeleteButton(
                    parent: widget.parent, items: widget.chapters),
              if (!FinampSettingsHelper.finampSettings.isOffline)
                SyncAlbumOrPlaylistButton(
                    parent: widget.parent, items: widget.chapters),
            ],
          ),
          // Chapter list
          if (widget.chapters.isNotEmpty)
            _ChapterSliverList(
              chapters: widget.chapters,
              parent: widget.parent,
              onDelete: _onChapterDeleted,
            )
          else
            SliverFillRemaining(
              child: Center(
                child: Text(
                  AppLocalizations.of(context)!.audiobookChapters,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The scrollable chapter list displayed inside a SliverList.
class _ChapterSliverList extends StatefulWidget {
  const _ChapterSliverList({
    Key? key,
    required this.chapters,
    required this.parent,
    required this.onDelete,
  }) : super(key: key);

  final List<BaseItemDto> chapters;
  final BaseItemDto parent;
  final void Function(BaseItemDto) onDelete;

  @override
  State<_ChapterSliverList> createState() => _ChapterSliverListState();
}

class _ChapterSliverListState extends State<_ChapterSliverList> {
  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final chapter = widget.chapters[index];

          return SongListTile(
            item: chapter,
            // Pass all chapters so tapping one starts from that position
            // with the full book queue loaded.
            children: widget.chapters,
            index: index,
            parentId: widget.parent.id,
            onDelete: () => widget.onDelete(chapter),
            // Audiobooks don't have separate artists per chapter in most cases;
            // showing the narrator on every line would be repetitive.
            showArtists: false,
          );
        },
        childCount: widget.chapters.length,
      ),
    );
  }
}
