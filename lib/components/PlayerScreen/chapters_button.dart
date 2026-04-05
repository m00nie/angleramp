import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../models/jellyfin_models.dart';
import '../../services/music_player_background_task.dart';
import 'chapters_sheet.dart';

/// A button that opens the [ChaptersSheet]. Only renders when the current
/// media item has at least one chapter, so it is completely invisible for
/// regular music tracks.
class ChaptersButton extends StatelessWidget {
  const ChaptersButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final audioHandler = GetIt.instance<MusicPlayerBackgroundTask>();

    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, snapshot) {
        if (snapshot.data?.extras?["itemJson"] == null) {
          return const SizedBox.shrink();
        }

        final item =
            BaseItemDto.fromJson(snapshot.data!.extras!["itemJson"]);
        final chapters = item.chapters;

        if (chapters == null || chapters.isEmpty) {
          return const SizedBox.shrink();
        }

        return IconButton(
          icon: const Icon(Icons.format_list_numbered),
          tooltip: 'Chapters',
          onPressed: () => showModalBottomSheet(
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24.0)),
            ),
            context: context,
            builder: (context) => DraggableScrollableSheet(
              expand: false,
              builder: (context, scrollController) => ChaptersSheet(
                scrollController: scrollController,
              ),
            ),
          ),
        );
      },
    );
  }
}
