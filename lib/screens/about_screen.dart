import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:finamp/l10n/app_localizations.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  static const routeName = "/settings/about";

  static const _finampGithubUrl = "https://github.com/jmshrv/finamp";

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.about),
      ),
      body: Scrollbar(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          children: [
            // Logo
            Center(
              child: SvgPicture.asset(
                'assets/icon/angleramp_icon.svg',
                width: 120,
                height: 120,
              ),
            ),
            const SizedBox(height: 20),
            // App name
            Center(
              child: Text(
                "AnglerAmp",
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Credit heading
            Text(
              "Built on the shoulders of giants",
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "AnglerAmp is a personal fork of the far superior app Finamp, "
              "created by jmshrv and their contributors. All the real work "
              "was done by them — this app only adds a handful of small "
              "improvements that I find personally useful. Every credit goes "
              "to the Finamp team.",
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            // Finamp link tile
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.open_in_new, color: colorScheme.secondary),
              title: const Text("Finamp on GitHub"),
              subtitle: Text(
                _finampGithubUrl,
                style: TextStyle(color: colorScheme.secondary),
              ),
              onTap: () => launchUrl(
                Uri.parse(_finampGithubUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const Divider(height: 40),
            // What's different
            Text(
              "What's different in AnglerAmp",
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _DiffTile(
              icon: Icons.book,
              title: "Basic audiobook support",
              description:
                  "Browse and play audiobooks stored in your Jellyfin library.",
            ),
            _DiffTile(
              icon: Icons.directions_car,
              title: "Basic CarPlay support",
              description:
                  "Control playback from your car's screen via CarPlay.",
            ),
            _DiffTile(
              icon: Icons.folder_open,
              title: "Browse audio by directory",
              description:
                  "Navigate your music collection by folder path — useful "
                  "when metadata tags are missing or poorly managed.",
            ),
            _DiffTile(
              icon: Icons.palette,
              title: "Different theme",
              description:
                  "A dark navy colour scheme with emerald-green accents, "
                  "easier on sensitive eyes.",
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                "This fork is not affiliated with or endorsed by the Finamp project - In fact nobody but me even knows it exists or should be using it. If you're interested in contributing to the original Finamp codebase, check out the GitHub repo linked above!",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffTile extends StatelessWidget {
  const _DiffTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
