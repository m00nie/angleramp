import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../models/jellyfin_models.dart';
import '../../services/music_player_background_task.dart';
import '../../services/progress_state_stream.dart';
import '../print_duration.dart';

class ChaptersSheet extends StatelessWidget {
  const ChaptersSheet({Key? key, required this.scrollController})
      : super(key: key);

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final audioHandler = GetIt.instance<MusicPlayerBackgroundTask>();

    return StreamBuilder<ProgressState>(
      stream: progressStateStream,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data?.mediaItem;
        if (mediaItem == null || mediaItem.extras?["itemJson"] == null) {
          return const SizedBox.shrink();
        }

        final item = BaseItemDto.fromJson(mediaItem.extras!["itemJson"]);
        final chapters = item.chapters;

        if (chapters == null || chapters.isEmpty) {
          return const SizedBox.shrink();
        }

        final position = snapshot.data!.position;
        final totalDuration = mediaItem.duration ?? Duration.zero;

        // Determine which chapter is currently playing
        final posTicks = position.inMicroseconds * 10;
        int currentIndex = 0;
        for (int i = 0; i < chapters.length; i++) {
          if (chapters[i].startPositionTicks <= posTicks) {
            currentIndex = i;
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Chapters',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: chapters.length,
                itemBuilder: (context, index) {
                  final chapter = chapters[index];
                  final isCurrentChapter = index == currentIndex;
                  final chapterStart = Duration(
                      microseconds: chapter.startPositionTicks ~/ 10);

                  // Calculate this chapter's duration
                  final Duration chapterDuration;
                  if (index < chapters.length - 1) {
                    final nextStart = Duration(
                        microseconds:
                            chapters[index + 1].startPositionTicks ~/ 10);
                    chapterDuration = nextStart - chapterStart;
                  } else {
                    chapterDuration = totalDuration > chapterStart
                        ? totalDuration - chapterStart
                        : Duration.zero;
                  }

                  return ListTile(
                    leading: isCurrentChapter
                        ? const Icon(Icons.play_arrow,
                            color: Color(0xFF34D399))
                        : SizedBox(
                            width: 24,
                            child: Text(
                              '${index + 1}',
                              style:
                                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.45),
                                      ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                    title: Text(
                      chapter.name ?? 'Chapter ${index + 1}',
                      style: TextStyle(
                        color: isCurrentChapter
                            ? const Color(0xFF34D399)
                            : null,
                        fontWeight: isCurrentChapter
                            ? FontWeight.w600
                            : null,
                      ),
                    ),
                    subtitle: Text(
                      printDuration(chapterStart),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Text(
                      chapterDuration > Duration.zero
                          ? printDuration(chapterDuration)
                          : '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () {
                      audioHandler.seek(chapterStart);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
