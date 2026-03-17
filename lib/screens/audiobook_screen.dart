import 'package:flutter/material.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';

import '../models/jellyfin_models.dart';
import '../models/finamp_models.dart';
import '../services/jellyfin_api_helper.dart';
import '../services/finamp_settings_helper.dart';
import '../services/downloads_helper.dart';
import '../components/now_playing_bar.dart';
import '../components/AudiobookScreen/audiobook_screen_content.dart';

class AudiobookScreen extends StatefulWidget {
  const AudiobookScreen({
    Key? key,
    this.parent,
  }) : super(key: key);

  static const routeName = "/audiobook";

  /// The audiobook to show. Can also be provided as an argument in a named route.
  final BaseItemDto? parent;

  @override
  State<AudiobookScreen> createState() => _AudiobookScreenState();
}

class _AudiobookScreenState extends State<AudiobookScreen> {
  Future<List<BaseItemDto>?>? _chaptersFuture;
  final _jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();

  @override
  Widget build(BuildContext context) {
    final BaseItemDto parent = widget.parent ??
        ModalRoute.of(context)!.settings.arguments as BaseItemDto;

    return Scaffold(
      body: ValueListenableBuilder<Box<FinampSettings>>(
        valueListenable: FinampSettingsHelper.finampSettingsListener,
        builder: (context, box, _) {
          final isOffline = box.get("FinampSettings")?.isOffline ?? false;

          if (isOffline) {
            final downloadsHelper = GetIt.instance<DownloadsHelper>();

            // In offline mode, look up the downloaded parent (the audiobook)
            // and show its downloaded child tracks.
            final downloadedParent =
                downloadsHelper.getDownloadedParent(parent.id);

            if (downloadedParent == null) {
              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    title: Text(parent.name ??
                        AppLocalizations.of(context)!.unknownName),
                  ),
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                          AppLocalizations.of(context)!.notAvailableInOfflineMode),
                    ),
                  ),
                ],
              );
            }

            return AudiobookScreenContent(
              parent: downloadedParent.item,
              chapters: downloadedParent.downloadedChildren.values.toList(),
            );
          } else {
            // Jellyfin's AudioBook items are leaf audio files — they extend
            // Audio.Audio on the server side and are always a single playable
            // file. The /Items endpoint treats non-Folder parentIds by falling
            // back to the library root, so querying for children is wrong.
            //
            // The AudioBook item itself IS the chapter. No network request
            // needed — pass it directly to the content widget.
            if (parent.type == "AudioBook") {
              return AudiobookScreenContent(
                parent: parent,
                chapters: [parent],
              );
            }

            // Fallback path for any other container types (e.g. legacy
            // folder-based books) — fetch child Audio tracks from the server.
            _chaptersFuture ??= _jellyfinApiHelper.getItems(
              parentItem: parent,
              sortBy: "ParentIndexNumber,IndexNumber,SortName",
              includeItemTypes: "Audio",
              isGenres: false,
            );

            return FutureBuilder<List<BaseItemDto>?>(
              future: _chaptersFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final chapters = snapshot.data!.isEmpty
                      ? [parent]
                      : snapshot.data!;
                  return AudiobookScreenContent(
                    parent: parent,
                    chapters: chapters,
                  );
                } else if (snapshot.hasError) {
                  return CustomScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    slivers: [
                      SliverAppBar(
                        title: Text(AppLocalizations.of(context)!.error),
                      ),
                      SliverFillRemaining(
                        child: Center(
                            child: Text(snapshot.error.toString())),
                      ),
                    ],
                  );
                } else {
                  return CustomScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    slivers: [
                      SliverAppBar(
                        title: Text(parent.name ??
                            AppLocalizations.of(context)!.unknownName),
                      ),
                      const SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      ),
                    ],
                  );
                }
              },
            );
          }
        },
      ),
      bottomNavigationBar: const NowPlayingBar(),
    );
  }
}
