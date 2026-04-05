import 'package:flutter/material.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:get_it/get_it.dart';

import '../components/ViewSelector/no_music_libraries_message.dart';
import '../models/finamp_models.dart';
import '../services/finamp_settings_helper.dart';
import '../services/finamp_user_helper.dart';
import 'music_screen.dart';
import '../services/jellyfin_api_helper.dart';
import '../models/jellyfin_models.dart';
import '../components/error_snackbar.dart';

class ViewSelector extends StatefulWidget {
  const ViewSelector({Key? key}) : super(key: key);

  static const routeName = "/settings/views";

  @override
  State<ViewSelector> createState() => _ViewSelectorState();
}

class _ViewSelectorState extends State<ViewSelector> {
  final _jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
  final _finampUserHelper = GetIt.instance<FinampUserHelper>();
  late Future<List<BaseItemDto>> viewListFuture;
  final Map<BaseItemDto, bool> _views = {};
  bool isSubmitButtonEnabled = false;

  @override
  void initState() {
    super.initState();
    viewListFuture = _jellyfinApiHelper.getViews();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BaseItemDto>>(
      future: viewListFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          // Finamp supports music and audiobook (books) libraries.
          // Show the no-libraries message only if neither type is available.
          if (snapshot.data!.isEmpty ||
              !snapshot.data!.any((element) =>
                  element.collectionType == "music" ||
                  element.collectionType == "books")) {
            return NoMusicLibrariesMessage(
              onRefresh: () {
                setState(() {
                  _views.clear();
                  viewListFuture = _jellyfinApiHelper.getViews();
                });
              },
            );
          }

          if (_views.isEmpty) {
            // Only show music and books libraries; other types (movies, TV, etc.)
            // are not supported by Finamp.
            final savedViews = _finampUserHelper.currentUser?.views ?? {};
            _views.addEntries(snapshot.data!
                .where((element) =>
                    element.collectionType == "music" ||
                    element.collectionType == "books")
                .map((e) => MapEntry(
                    e,
                    savedViews.isNotEmpty
                        // Restore previously-saved selection (e.g. books library
                        // that was checked last time the dialog was opened).
                        ? savedViews.containsKey(e.id)
                        // First-time setup: default to music=on, books=off.
                        : e.collectionType == "music")));

            // If only one music library is available and user doesn't have a
            // view saved (assuming setup is in progress), skip the selector.
            if (_views.values.where((element) => element == true).length == 1 &&
                _finampUserHelper.currentUser!.currentView == null) {
              _submitChoice();
            } else {
              if (mounted) {
                isSubmitButtonEnabled = _views.values.contains(true);
              }
            }
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(AppLocalizations.of(context)!.selectMusicLibraries),
            ),
            floatingActionButton: isSubmitButtonEnabled
                ? FloatingActionButton(
                    onPressed: _submitChoice,
                    child: const Icon(Icons.check),
                  )
                : null,
            body: Scrollbar(
              child: ListView.builder(
                itemCount: _views.length,
                itemBuilder: (context, index) {
                  final isSelected = _views.values.elementAt(index);
                  final view = _views.keys.elementAt(index);

                  return CheckboxListTile(
                    value: isSelected,
                    // Music and books libraries are both selectable;
                    // music for the main library, books for audiobooks.
                    enabled: view.collectionType == "music" ||
                        view.collectionType == "books",
                    title: Text(_views.keys.elementAt(index).name ??
                        AppLocalizations.of(context)!.unknownName),
                    subtitle: view.collectionType == "books"
                        ? Text(AppLocalizations.of(context)!.audiobooks)
                        : null,
                    onChanged: (value) {
                      setState(() {
                        _views[_views.keys.elementAt(index)] = value!;
                        isSubmitButtonEnabled = _views.values.contains(true);
                      });
                    },
                  );
                },
              ),
            ),
          );
        } else if (snapshot.hasError) {
          errorSnackbar(snapshot.error, context);
          // TODO: Let the user refresh the page
          return Center(
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error),
              Text(snapshot.error.toString()),
            ],
          ));
        } else {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
      },
    );
  }

  void _submitChoice() {
    if (_views.values.where((element) => element == true).isEmpty) {
      // This should no longer be possible since the submit button only shows
      // when views are selected, but we return just in case
      return;
    } else {
      try {
        final selectedViews = _views.entries
            .where((element) => element.value == true)
            .map((e) => e.key)
            .toList();

        _finampUserHelper.setCurrentUserViews(selectedViews);

        // Auto-enable the audiobooks tab when a books library is selected,
        // and disable it when none are selected. This keeps audiobook
        // visibility in sync with the user's library choice.
        final hasBooksLibrary =
            selectedViews.any((v) => v.collectionType == "books");
        FinampSettingsHelper.setShowTab(
            TabContentType.audiobooks, hasBooksLibrary);

        // allow navigation to music screen while selector is being built
        Future.microtask(() => Navigator.of(context)
            .pushNamedAndRemoveUntil(MusicScreen.routeName, (route) => false));
      } catch (e) {
        errorSnackbar(e, context);
      }
    }
  }
}
