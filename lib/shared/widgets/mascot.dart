import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum MascotState {
  idle,
  encouraging,
  happy,
  celebrating,
  resting,
  writing,
  working,
}

/// A single presentation entry point for the app's original pink lamb asset.
/// State-specific assets can replace this treatment without changing pages.
class MascotWidget extends StatelessWidget {
  const MascotWidget({
    required this.state,
    this.size = 88,
    this.compact = false,
    super.key,
  });

  final MascotState state;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final celebration = state == MascotState.celebrating;
    final tint = switch (state) {
      MascotState.resting => AppColors.lavender,
      MascotState.working || MascotState.writing => AppColors.blueMist,
      MascotState.happy || MascotState.celebrating => AppColors.blush,
      _ => AppColors.cream,
    };
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: tint,
              shape: BoxShape.circle,
              boxShadow: const [AppShadows.soft],
            ),
            child: Padding(
              padding: EdgeInsets.all(compact ? 7 : 5),
              child: Image.asset(
                'assets/images/pink_lamb_piano.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          if (celebration) ...[
            const Positioned(
              top: -4,
              left: 0,
              child: Icon(
                Icons.star_rounded,
                size: 17,
                color: AppColors.creamYellow,
              ),
            ),
            const Positioned(
              right: -2,
              top: 10,
              child: Icon(
                Icons.music_note_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ),
          ],
          if (state == MascotState.encouraging)
            const Positioned(
              right: 1,
              bottom: 2,
              child: Icon(
                Icons.favorite_rounded,
                size: 15,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }
}

class MascotEmptyState extends StatelessWidget {
  const MascotEmptyState({
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
    child: Row(
      children: [
        const MascotWidget(state: MascotState.resting, size: 46, compact: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                message,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}
