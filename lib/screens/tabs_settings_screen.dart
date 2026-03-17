import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:flutter/material.dart';
import 'package:finamp/l10n/app_localizations.dart';

import '../components/TabsSettingsScreen/hide_tab_toggle.dart';
import '../models/finamp_models.dart';

class TabsSettingsScreen extends StatefulWidget {
  const TabsSettingsScreen({Key? key}) : super(key: key);

  static const routeName = "/settings/tabs";

  @override
  State<TabsSettingsScreen> createState() => _TabsSettingsScreenState();
}

class _TabsSettingsScreenState extends State<TabsSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.tabs),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                FinampSettingsHelper.resetTabs();
              });
            },
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context)!.resetTabs,
          )
        ],
      ),
      body: Scrollbar(
        child: Builder(
          builder: (context) {
            // Audiobooks tab visibility is now controlled by library selection,
            // not a manual toggle, so hide it from this settings screen.
            final tabOrder = FinampSettingsHelper.finampSettings.tabOrder
                .where((t) => t != TabContentType.audiobooks)
                .toList();
            return ReorderableListView.builder(
              itemCount: tabOrder.length,
              itemBuilder: (context, index) {
                return HideTabToggle(
                  tabContentType: tabOrder[index],
                  key: ValueKey(tabOrder[index]),
                );
              },
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) newIndex -= 1;
                  final allTabs = FinampSettingsHelper.finampSettings.tabOrder;
                  final oldValue = tabOrder[oldIndex];
                  final newValue = tabOrder[newIndex];
                  final actualOld = allTabs.indexOf(oldValue);
                  final actualNew = allTabs.indexOf(newValue);
                  FinampSettingsHelper.setTabOrder(actualOld, newValue);
                  FinampSettingsHelper.setTabOrder(actualNew, oldValue);
                });
              },
            );
          },
        ),
      ),
    );
  }
}
