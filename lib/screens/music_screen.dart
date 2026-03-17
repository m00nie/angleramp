import 'package:flutter/material.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:logging/logging.dart';

import '../models/finamp_models.dart';
import '../services/finamp_settings_helper.dart';
import '../services/audio_service_helper.dart';
import '../services/finamp_user_helper.dart';
import '../components/MusicScreen/music_screen_tab_view.dart';
import '../components/MusicScreen/music_screen_drawer.dart';
import '../components/MusicScreen/sort_by_menu_button.dart';
import '../components/MusicScreen/sort_order_button.dart';
import '../components/now_playing_bar.dart';
import '../components/error_snackbar.dart';
import '../services/jellyfin_api_helper.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({Key? key}) : super(key: key);

  static const routeName = "/music";

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen>
    with TickerProviderStateMixin {
  bool isSearching = false;
  bool _showShuffleFab = false;
  TextEditingController textEditingController = TextEditingController();
  String? searchQuery;
  final _musicScreenLogger = Logger("MusicScreen");

  TabController? _tabController;
  bool _wasBookMode = false;

  final _audioServiceHelper = GetIt.instance<AudioServiceHelper>();
  final _finampUserHelper = GetIt.instance<FinampUserHelper>();
  final _jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();

  bool get _isBookMode =>
      _finampUserHelper.currentUser?.currentView?.collectionType == "books";

  /// Returns the tabs to display, depending on whether a books library is
  /// currently selected.
  List<TabContentType> _getVisibleTabs() {
    if (_isBookMode) {
      return const [
        TabContentType.artists,
        TabContentType.audiobooks,
        TabContentType.playlists,
        TabContentType.genres,
      ];
    }
    return FinampSettingsHelper.finampSettings.tabOrder
        .where((e) =>
            (FinampSettingsHelper.finampSettings.showTabs[e] ?? false) &&
            e != TabContentType.audiobooks)
        .toList();
  }

  /// Returns a display label for a tab, using audiobook-specific names when
  /// a books library is currently selected.
  String _tabLabel(TabContentType tabType, BuildContext context) {
    if (_isBookMode) {
      if (tabType == TabContentType.artists) return "Authors".toUpperCase();
      if (tabType == TabContentType.audiobooks) return "Titles".toUpperCase();
    }
    return tabType.toLocalisedString(context).toUpperCase();
  }

  void _stopSearching() {
    setState(() {
      textEditingController.clear();
      searchQuery = null;
      isSearching = false;
    });
  }

  void _tabIndexCallback() {
    // In book mode never show a FAB
    if (_isBookMode) {
      if (_showShuffleFab) setState(() => _showShuffleFab = false);
      return;
    }
    final visibleTabs = _getVisibleTabs();
    if (_tabController == null || _tabController!.index >= visibleTabs.length) {
      return;
    }
    final tabKey = visibleTabs[_tabController!.index];
    if (tabKey == TabContentType.songs ||
        tabKey == TabContentType.artists ||
        tabKey == TabContentType.albums) {
      setState(() {
        _showShuffleFab = true;
      });
    } else {
      if (_showShuffleFab) {
        setState(() {
          _showShuffleFab = false;
        });
      }
    }
  }

  void _buildTabController([int? length]) {
    _tabController?.removeListener(_tabIndexCallback);

    _tabController = TabController(
      length: length ?? _getVisibleTabs().length,
      // Default to the Titles tab (index 1) when in books mode so that the
      // book list is immediately visible instead of the Authors list.
      initialIndex: _isBookMode ? 1 : 0,
      vsync: this,
    );

    _tabController!.addListener(_tabIndexCallback);
  }

  @override
  void initState() {
    super.initState();
    _wasBookMode = _isBookMode;
    _buildTabController();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  FloatingActionButton? getFloatingActionButton() {
    // No FAB for books libraries
    if (_isBookMode) return null;

    final tabList = _getVisibleTabs();

    // Show the floating action button only on the albums, artists and songs tab.
    if (_tabController!.index == tabList.indexOf(TabContentType.songs)) {
      return FloatingActionButton(
        tooltip: AppLocalizations.of(context)!.shuffleAll,
        onPressed: () async {
          try {
            await _audioServiceHelper
                .shuffleAll(FinampSettingsHelper.finampSettings.isFavourite);
          } catch (e) {
            errorSnackbar(e, context);
          }
        },
        child: const Icon(Icons.shuffle),
      );
    } else if (_tabController!.index ==
        tabList.indexOf(TabContentType.artists)) {
      return FloatingActionButton(
          tooltip: AppLocalizations.of(context)!.startMix,
          onPressed: () async {
            try {
              if (_jellyfinApiHelper.selectedMixArtistsIds.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.startMixNoSongsArtist)));
              } else {
                await _audioServiceHelper.startInstantMixForArtists(
                    _jellyfinApiHelper.selectedMixArtistsIds);
              }
            } catch (e) {
              errorSnackbar(e, context);
            }
          },
          child: const Icon(Icons.explore));
    } else if (_tabController!.index ==
        tabList.indexOf(TabContentType.albums)) {
      return FloatingActionButton(
          tooltip: AppLocalizations.of(context)!.startMix,
          onPressed: () async {
            try {
              if (_jellyfinApiHelper.selectedMixAlbumIds.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.startMixNoSongsAlbum)));
              } else {
                await _audioServiceHelper.startInstantMixForAlbums(
                    _jellyfinApiHelper.selectedMixAlbumIds);
              }
            } catch (e) {
              errorSnackbar(e, context);
            }
          },
          child: const Icon(Icons.explore));
    } else {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<FinampUser>>(
      valueListenable: _finampUserHelper.finampUsersListenable,
      builder: (context, value, _) {
        return ValueListenableBuilder<Box<FinampSettings>>(
          valueListenable: FinampSettingsHelper.finampSettingsListener,
          builder: (context, value, _) {
            final finampSettings = value.get("FinampSettings");

            // Get the effective tabs depending on whether a books library is
            // selected.  For books libraries, use a fixed audiobook tab set.
            // For music libraries, use the user's configured tab order,
            // excluding the audiobooks tab (which is managed automatically).
            final isBookMode = _isBookMode;
            final tabs = _getVisibleTabs();

            if (tabs.length != _tabController?.length ||
                isBookMode != _wasBookMode) {
              _musicScreenLogger.info(
                  "Rebuilding MusicScreen tab controller (${tabs.length} tabs, bookMode=$isBookMode)");
              _wasBookMode = isBookMode;
              _buildTabController(tabs.length);
            }

            return WillPopScope(
              onWillPop: () async {
                if (isSearching) {
                  _stopSearching();
                  return false;
                }
                return true;
              },
              child: Scaffold(
                appBar: AppBar(
                  title: isSearching
                      ? TextField(
                          controller: textEditingController,
                          autofocus: true,
                          onChanged: (value) => setState(() {
                            searchQuery = value;
                          }),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: MaterialLocalizations.of(context)
                                .searchFieldLabel,
                          ),
                        )
                      : Text(_finampUserHelper.currentUser?.currentView?.name ??
                          AppLocalizations.of(context)!.music),
                  bottom: TabBar(
                    controller: _tabController,
                    tabs: tabs
                        .map((tabType) => Tab(
                              text: _tabLabel(tabType, context),
                            ))
                        .toList(),
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                  ),
                  leading: isSearching
                      ? BackButton(
                          onPressed: () => _stopSearching(),
                        )
                      : null,
                  actions: isSearching
                      ? [
                          IconButton(
                            icon: Icon(
                              Icons.cancel,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            onPressed: () => setState(() {
                              textEditingController.clear();
                              searchQuery = null;
                            }),
                            tooltip: AppLocalizations.of(context)!.clear,
                          )
                        ]
                      : [
                          if (!isBookMode) ...[
                            SortOrderButton(
                              tabs.elementAt(_tabController!.index),
                            ),
                            SortByMenuButton(
                              tabs.elementAt(_tabController!.index),
                            ),
                          ],
                          IconButton(
                            icon: finampSettings!.isFavourite
                                ? const Icon(Icons.favorite)
                                : const Icon(Icons.favorite_outline),
                            onPressed: finampSettings.isOffline
                                ? null
                                : () => FinampSettingsHelper.setIsFavourite(
                                    !finampSettings.isFavourite),
                            tooltip: AppLocalizations.of(context)!.favourites,
                          ),
                          IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () => setState(() {
                              isSearching = true;
                            }),
                            tooltip: MaterialLocalizations.of(context)
                                .searchFieldLabel,
                          ),
                        ],
                ),
                bottomNavigationBar: const NowPlayingBar(),
                drawer: const MusicScreenDrawer(),
                floatingActionButton: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: getFloatingActionButton(),
                ),
                body: TabBarView(
                  controller: _tabController,
                  children: tabs
                      .map((tabType) => MusicScreenTabView(
                            tabContentType: tabType,
                            searchTerm: searchQuery,
                            isFavourite: finampSettings!.isFavourite,
                            sortBy: finampSettings.getTabSortBy(tabType),
                            sortOrder: finampSettings.getSortOrder(tabType),
                            view: _finampUserHelper.currentUser?.currentView,
                          ))
                      .toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}