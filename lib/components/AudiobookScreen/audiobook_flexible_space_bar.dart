import 'package:flutter/material.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:get_it/get_it.dart';

import '../../models/jellyfin_models.dart';
import '../../services/audio_service_helper.dart';
import '../../services/jellyfin_api_helper.dart';
import '../../services/music_player_background_task.dart';
import '../album_image.dart';
import '../print_duration.dart';

/// The flexible space bar header shown on the audiobook screen. Displays the
/// book cover image alongside key metadata (narrator, chapter count, runtime)
/// and play controls (Resume / Play from Beginning).
class AudiobookFlexibleSpaceBar extends StatelessWidget {
  const AudiobookFlexibleSpaceBar({
    Key? key,
    required this.audiobook,
    required this.chapters,
    required this.totalDuration,
  }) : super(key: key);

  final BaseItemDto audiobook;
  final List<BaseItemDto> chapters;
  final Duration totalDuration;

  @override
  Widget build(BuildContext context) {
    final audioServiceHelper = GetIt.instance<AudioServiceHelper>();
    final audioHandler = GetIt.instance<MusicPlayerBackgroundTask>();

    return FlexibleSpaceBar(
      background: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Book cover art
                    SizedBox(
                      height: 125,
                      child: AlbumImage(item: audiobook),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AudiobookInfo(
                        audiobook: audiobook,
                        totalDuration: totalDuration,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      // "Resume" — starts at the last known playback position
                      // if the book has been partially listened to, otherwise
                      // behaves like "Play from Beginning".
                      Expanded(
                        child: _ResumeButton(
                          chapters: chapters,
                          audiobook: audiobook,
                          audioServiceHelper: audioServiceHelper,
                          audioHandler: audioHandler,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // "Play from beginning" always starts at chapter 0.
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: chapters.isEmpty
                              ? null
                              : () => audioServiceHelper.replaceQueueWithItem(
                                    itemList: chapters,
                                    initialIndex: 0,
                                  ),
                          icon: const Icon(Icons.replay),
                          label: Text(
                              AppLocalizations.of(context)!.playFromBeginning),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Metadata column shown alongside the book cover: narrator, runtime, and publication year.
class _AudiobookInfo extends StatelessWidget {
  const _AudiobookInfo({
    Key? key,
    required this.audiobook,
    required this.totalDuration,
  }) : super(key: key);

  final BaseItemDto audiobook;
  final Duration totalDuration;

  @override
  Widget build(BuildContext context) {
    // Jellyfin stores the narrator/reader in the artists field for Book items.
    final narrator = audiobook.artists?.join(", ") ??
        audiobook.albumArtist;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (narrator != null && narrator.isNotEmpty)
          _MetadataRow(
            icon: Icons.person,
            label: "${AppLocalizations.of(context)!.audiobookNarrator}: $narrator",
          ),
        _MetadataRow(
          icon: Icons.timer,
          label: printDuration(totalDuration),
        ),
        if (audiobook.productionYearString != null)
          _MetadataRow(
            icon: Icons.event,
            label: audiobook.productionYearString!,
          ),
      ],
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({Key? key, required this.icon, required this.label})
      : super(key: key);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A "Resume" button that starts playback from the chapter the user was last
/// listening to (using Jellyfin's playback position data), or from chapter 0
/// if no position is tracked. Falls back gracefully when [audioHandler] has
/// no active queue data for this book.
class _ResumeButton extends StatelessWidget {
  const _ResumeButton({
    Key? key,
    required this.chapters,
    required this.audiobook,
    required this.audioServiceHelper,
    required this.audioHandler,
  }) : super(key: key);

  final List<BaseItemDto> chapters;
  final BaseItemDto audiobook;
  final AudioServiceHelper audioServiceHelper;
  final MusicPlayerBackgroundTask audioHandler;

  /// Determines which chapter (track) index to resume from.
  /// Returns the first track that is partially played, or the first unplayed
  /// track after a run of fully-played ones.
  int _resumeIndex() {
    for (int i = 0; i < chapters.length; i++) {
      final userData = chapters[i].userData;
      if (userData == null) continue;
      final played = userData.playedPercentage ?? 0;
      if (played > 0 && played < 99) return i;
    }
    for (int i = 0; i < chapters.length; i++) {
      final userData = chapters[i].userData;
      if (userData == null || !userData.played) return i;
    }
    return 0;
  }

  /// Returns the exact seek position within the resume track using Jellyfin's
  /// stored [UserItemDataDto.playbackPositionTicks].  Returns null (start of
  /// track) when there is no saved position.
  Duration? _resumePosition() {
    final idx = _resumeIndex();
    final ticks = chapters[idx].userData?.playbackPositionTicks ?? 0;
    if (ticks <= 0) return null;
    return Duration(microseconds: ticks ~/ 10);
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: chapters.isEmpty
          ? null
          : () async {
              final idx = _resumeIndex();
              Duration? position;
              try {
                final jellyfinApiHelper =
                    GetIt.instance<JellyfinApiHelper>();
                final freshItem =
                    await jellyfinApiHelper.getItemById(chapters[idx].id);
                final ticks =
                    freshItem.userData?.playbackPositionTicks ?? 0;
                if (ticks > 0) {
                  position = Duration(microseconds: ticks ~/ 10);
                }
              } catch (_) {
                // Fall back to stale in-memory data if the network call fails.
                position = _resumePosition();
              }
              await audioServiceHelper.replaceQueueWithItem(
                itemList: chapters,
                initialIndex: idx,
                initialPosition: position,
              );
            },
      icon: const Icon(Icons.play_arrow),
      label: Text(AppLocalizations.of(context)!.resumeAudiobook),
    );
  }
}
