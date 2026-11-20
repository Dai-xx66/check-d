import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/appearance_controller.dart';
import '../../core/theme/appearance_preferences.dart';

class AppBrandIcon extends ConsumerWidget {
  const AppBrandIcon({this.size = 40, super.key});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style =
        ref.watch(appearanceControllerProvider).value?.icon ??
        AppIconStyle.lamb;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .26),
      child: Image.asset(style.previewAsset, width: size, height: size),
    );
  }
}
