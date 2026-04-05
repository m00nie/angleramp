import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../models/jellyfin_models.dart';
import '../../services/music_player_background_task.dart';
import '../../services/progress_state_stream.dart';
import '../print_duration.dart';

// Brand green — matches trading-game palette
const _kTrackActive   = Color(0xFF34D399);
const _kTrackInactive = Color(0xFF17243E);
const _kTrackBuffer   = Color(0xFF1E3054);

class ProgressSlider extends StatefulWidget {
  const ProgressSlider({
    Key? key,
    this.allowSeeking = true,
    this.showBuffer = true,
    this.showDuration = true,
    this.showPlaceholder = true,
  }) : super(key: key);

  final bool allowSeeking;
  final bool showBuffer;
  final bool showDuration;
  final bool showPlaceholder;

  @override
  State<ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends State<ProgressSlider>
    with SingleTickerProviderStateMixin {
  /// Value used to hold the slider's value when dragging.
  double? _dragValue;

  late SliderThemeData _sliderThemeData;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final _audioHandler = GetIt.instance<MusicPlayerBackgroundTask>();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _sliderThemeData = SliderTheme.of(context).copyWith(
      trackHeight: 3.0,
      activeTrackColor: _kTrackActive,
      inactiveTrackColor: _kTrackInactive,
      secondaryActiveTrackColor: _kTrackBuffer,
      thumbColor: _kTrackActive,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The slider always needs to be LTR, so we use Directionality to save
    // putting TextDirection.ltr all over the place
    return Directionality(
      textDirection: TextDirection.ltr,
      // The slider can refresh up to 60 times per second, so we wrap it in a
      // RepaintBoundary to avoid more areas being repainted than necessary
      child: RepaintBoundary(
        child: StreamBuilder<ProgressState>(
          stream: progressStateStream,
          builder: (context, snapshot) {
            if (snapshot.data?.mediaItem == null) {
              // If nothing is playing or the AudioService isn't connected, return a
              // greyed out slider with some fake numbers. We also do this if
              // currentPosition is null, which sometimes happens when the app is
              // closed and reopened.
              return widget.showPlaceholder
                  ? Column(
                      children: [
                        SliderTheme(
                          data: _sliderThemeData.copyWith(
                            trackShape: CustomTrackShape(),
                          ),
                          child: const Slider(
                            value: 0,
                            max: 1,
                            onChanged: null,
                          ),
                        ),
                        if (widget.showDuration)
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "00:00",
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.color),
                              ),
                              Text(
                                "00:00",
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.color),
                              ),
                            ],
                          ),
                      ],
                    )
                  : const SizedBox.shrink();
            } else if (snapshot.hasData) {
              final chapters = snapshot.data!.mediaItem?.extras?["itemJson"] != null
                  ? BaseItemDto.fromJson(
                          snapshot.data!.mediaItem!.extras!["itemJson"])
                      .chapters
                  : null;
              final hasChapters = chapters != null && chapters.isNotEmpty;

              // When chapters are present and the full player is shown, scope
              // the slider and time labels to the current chapter only.
              final int positionMicros =
                  _dragValue?.toInt() ?? snapshot.data!.position.inMicroseconds;
              final int sliderMinUs;
              final int sliderMaxUs;
              if (hasChapters && widget.allowSeeking) {
                final bounds = _chapterBoundsForPosition(
                  positionMicros: positionMicros,
                  chapters: chapters,
                  totalDurationUs:
                      snapshot.data!.mediaItem?.duration?.inMicroseconds ?? 0,
                );
                sliderMinUs = bounds.$1;
                sliderMaxUs = bounds.$2;
              } else {
                sliderMinUs = 0;
                sliderMaxUs = snapshot.data!.mediaItem?.duration?.inMicroseconds ??
                    snapshot.data!.playbackState.bufferedPosition.inMicroseconds;
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Slider displaying playback and buffering progress.
                  // For the full player we wrap in AnimatedBuilder so the
                  // glowing dot thumb repaints on every pulse animation tick.
                  if (widget.allowSeeking)
                    Stack(
                      children: [
                        AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, _) => SliderTheme(
                        data: _sliderThemeData.copyWith(
                          trackShape: CustomTrackShape(),
                          thumbShape: _GlowingDotThumbShape(
                            pulse: _pulseAnimation.value,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                        ),
                        child: Slider(
                      min: sliderMinUs.toDouble(),
                      max: sliderMaxUs.toDouble(),
                      value: (positionMicros)
                          .clamp(sliderMinUs, sliderMaxUs)
                          .toDouble(),
                      secondaryTrackValue: widget.showBuffer &&
                              snapshot.data!.mediaItem
                                      ?.extras?["downloadedSongJson"] ==
                                  null
                          ? snapshot.data!.playbackState.bufferedPosition
                              .inMicroseconds
                              .clamp(
                                sliderMinUs.toDouble(),
                                sliderMaxUs.toDouble(),
                              )
                              .toDouble()
                          : 0,
                      onChanged: widget.allowSeeking
                          ? (newValue) async {
                              // We don't actually tell audio_service to seek here
                              // because it would get flooded with seek requests
                              setState(() {
                                _dragValue = newValue;
                              });
                            }
                          : (_) {},
                      onChangeStart: widget.allowSeeking
                          ? (value) {
                              setState(() {
                                _dragValue = value;
                              });
                            }
                          : (_) {},
                      onChangeEnd: widget.allowSeeking
                          ? (newValue) async {
                              // Seek to the new position
                              await _audioHandler.seek(
                                  Duration(microseconds: newValue.toInt()));

                              // Clear drag value so that the slider uses the play
                              // duration again.
                              setState(() {
                                _dragValue = null;
                              });
                            }
                          : (_) {},
                    ),
                  ),
                    ),
                        // Chapter tick marks are only shown when the slider spans
                        // the full book (no chapter scoping), i.e. never in the
                        // current full-player chapter mode.
                      ],
                    )
                  else
                    // Mini now-playing bar: custom-painted track + full-size
                    // glowing dot in exactly 28 px, so it sits cleanly above
                    // the album art without overlap.
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, _) {
                        final duration = snapshot.data!.mediaItem?.duration
                                ?.inMicroseconds
                                .toDouble() ??
                            0.0;
                        final position = snapshot.data!.position.inMicroseconds
                            .toDouble()
                            .clamp(0.0, duration > 0 ? duration : 1.0);
                        return SizedBox(
                          height: 28.0,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _MiniProgressPainter(
                              value: duration > 0 ? position / duration : 0.0,
                              pulse: _pulseAnimation.value,
                            ),
                          ),
                        );
                      },
                    ),
                  if (widget.showDuration)
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          // Elapsed: time from chapter start (or track start)
                          printDuration(Duration(
                              microseconds: positionMicros - sliderMinUs)),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color),
                        ),
                        Text(
                          // Remaining: time to chapter end (or track end)
                          printDuration(Duration(
                              microseconds:
                                  (sliderMaxUs - positionMicros).clamp(0, sliderMaxUs))),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color),
                        ),
                      ],
                    ),
                ],
              );
            } else {
              return const Text(
                  "Snapshot doesn't have data and MediaItem isn't null and AudioService is connected?");
            }
          },
        ),
      ),
    );
  }

  /// Returns (chapterStartUs, chapterEndUs) for the chapter covering [positionMicros].
  (int, int) _chapterBoundsForPosition({
    required int positionMicros,
    required List<ChapterInfo> chapters,
    required int totalDurationUs,
  }) {
    final positionTicks = positionMicros * 10;
    int currentIdx = 0;
    for (int i = 0; i < chapters.length; i++) {
      if (chapters[i].startPositionTicks <= positionTicks) {
        currentIdx = i;
      } else {
        break;
      }
    }
    final startUs = chapters[currentIdx].startPositionTicks ~/ 10;
    final endUs = currentIdx < chapters.length - 1
        ? chapters[currentIdx + 1].startPositionTicks ~/ 10
        : totalDurationUs;
    return (startUs, endUs > startUs ? endUs : totalDurationUs);
  }
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;

  PositionData(this.position, this.bufferedPosition);
}

/// Track shape used to remove horizontal padding.
/// https://github.com/flutter/flutter/issues/37057
class CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight!;
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  /// Disable additionalActiveTrackHeight
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
  }
}

/// A custom slider thumb that renders the 4-layer glowing dot from the
/// trading-game-mobile app. The [pulse] value (0.0–1.0) drives the outer
/// halo's expanding radius and opacity, producing a live heartbeat effect.
class _GlowingDotThumbShape extends SliderComponentShape {
  const _GlowingDotThumbShape({required this.pulse, this.scale = 1.0});

  /// Animated value in [0.0, 1.0] driven by a CurvedAnimation.
  final double pulse;

  /// Scale factor: 1.0 = full-size player, <1.0 = mini bar.
  final double scale;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size(28.0 * scale, 28.0 * scale);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final color = sliderTheme.activeTrackColor ?? _kTrackActive;
    final s = scale;

    // Layer 1: Outer expanding glow ring (pulses radius 10→14 px, opacity 7→15%)
    canvas.drawCircle(
      center,
      (10.0 + 4.0 * pulse) * s,
      Paint()
        ..color = color.withOpacity(0.07 + 0.08 * pulse)
        ..style = PaintingStyle.fill,
    );

    // Layer 2: Inner static halo
    canvas.drawCircle(
      center,
      6.5 * s,
      Paint()
        ..color = color.withOpacity(0.22)
        ..style = PaintingStyle.fill,
    );

    // Layer 3: Solid filled dot
    canvas.drawCircle(
      center,
      4.0 * s,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    // Layer 4: White centre highlight for depth
    canvas.drawCircle(
      center,
      1.5 * s,
      Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.fill,
    );
  }
}

/// Draws the mini now-playing-bar progress track + full-size glowing dot
/// inside a fixed 28 px height. Avoids the Flutter Slider's 48 px minimum
/// touch-target height so the bar sits cleanly above the ListTile.
class _MiniProgressPainter extends CustomPainter {
  const _MiniProgressPainter({required this.value, required this.pulse});

  final double value; // 0.0 – 1.0
  final double pulse; // CurvedAnimation value

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final cy = size.height / 2;
    final dotX = (value.clamp(0.0, 1.0) * size.width).clamp(0.0, size.width);

    // Inactive (full-width) track
    canvas.drawRRect(
      RRect.fromLTRBR(
          0, cy - 1.5, size.width, cy + 1.5, const Radius.circular(1.5)),
      Paint()..color = _kTrackInactive,
    );
    // Active portion
    if (dotX > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
            0, cy - 1.5, dotX, cy + 1.5, const Radius.circular(1.5)),
        Paint()..color = _kTrackActive,
      );
    }
    // Glowing dot — same 4-layer design as _GlowingDotThumbShape
    final center = Offset(dotX, cy);
    canvas.drawCircle(
        center, 10.0 + 4.0 * pulse,
        Paint()
          ..color = _kTrackActive.withOpacity(0.07 + 0.08 * pulse)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        center, 6.5,
        Paint()
          ..color = _kTrackActive.withOpacity(0.22)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        center, 4.0,
        Paint()
          ..color = _kTrackActive
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        center, 1.5,
        Paint()
          ..color = Colors.white.withOpacity(0.9)
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_MiniProgressPainter old) =>
      old.value != value || old.pulse != pulse;
}

