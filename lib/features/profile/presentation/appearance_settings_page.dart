import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/appearance_controller.dart';
import '../../../core/theme/appearance_preferences.dart';

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({this.showIcons = false, super.key});

  final bool showIcons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs =
        ref.watch(appearanceControllerProvider).value ??
        const AppearancePreferences();
    final controller = ref.read(appearanceControllerProvider.notifier);
    return DefaultTabController(
      length: 2,
      initialIndex: showIcons ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(title: const Text('外观设置')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '找到舒服的日常。',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '换一种色彩，继续自己的节奏。',
                        style: TextStyle(color: AppColors.muted, fontSize: 14),
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: 280,
                        child: TabBar(
                          labelColor: AppColors.ink,
                          unselectedLabelColor: AppColors.muted,
                          indicatorColor: AppColors.primary,
                          dividerColor: AppColors.border,
                          tabs: const [
                            Tab(text: '换皮肤'),
                            Tab(text: '更换图标'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                        child: LayoutBuilder(
                          builder: (context, constraints) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 18,
                                runSpacing: 18,
                                children: [
                                  for (final skin in AppSkin.all)
                                    SizedBox(
                                      width: constraints.maxWidth >= 760
                                          ? (constraints.maxWidth - 36) / 3
                                          : constraints.maxWidth,
                                      child: _SkinCard(
                                        skin: skin,
                                        selected: prefs.skin == skin.id,
                                        onTap: () => _save(
                                          context,
                                          () => controller.selectSkin(skin.id),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              Text(
                                '选择后即时应用，偏好保存在这台设备上。',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ListView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                        children: [
                          Text(
                            '桌面上的一点个性',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '图标可以与任意皮肤搭配。',
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 24),
                          LayoutBuilder(
                            builder: (context, constraints) => Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                for (final style in AppIconStyle.values)
                                  SizedBox(
                                    width: constraints.maxWidth >= 760
                                        ? 220
                                        : (constraints.maxWidth - 16) / 2,
                                    child: _IconCard(
                                      style: style,
                                      selected: prefs.icon == style,
                                      onTap: () => _save(
                                        context,
                                        () => controller.selectIcon(style),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 19,
                              ),
                              label: const Text('下载配套桌面图标'),
                              onPressed: () =>
                                  _downloadIcon(context, prefs.icon),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '应用内标识即时更新。PNG 可用于桌面自定义，Windows 可选 ICO，macOS 可选 ICNS。系统启动图标需由对应平台安装包配置。',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                              height: 1.65,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('外观保存失败，请重试。')));
      }
    }
  }

  Future<void> _downloadIcon(BuildContext context, AppIconStyle style) async {
    final format = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择图标格式'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'png'),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('PNG · 通用图片'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'ico'),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('ICO · Windows 桌面'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'icns'),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('ICNS · macOS 桌面'),
            ),
          ),
        ],
      ),
    );
    if (format == null) return;
    try {
      final path = style.previewAsset.replaceAll('.png', '.$format');
      final data = await rootBundle.load(path);
      await FilePicker.platform.saveFile(
        dialogTitle: '保存桌面图标',
        fileName: 'check-d-${style.storageKey}.$format',
        type: FileType.custom,
        allowedExtensions: [format],
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('图标下载失败，请重试。')));
      }
    }
  }
}

class _SkinCard extends StatelessWidget {
  const _SkinCard({
    required this.skin,
    required this.selected,
    required this.onTap,
  });
  final AppSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${skin.label}，${skin.tagline}',
    child: Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkinPreview(skin: skin),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            skin.label,
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            skin.tagline,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      color: selected ? AppColors.primary : AppColors.muted,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SkinPreview extends StatelessWidget {
  const _SkinPreview({required this.skin});
  final AppSkin skin;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      height: 228,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: skin.background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '今天',
                style: TextStyle(
                  color: skin.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Icon(Icons.wb_sunny_outlined, color: skin.primary, size: 19),
            ],
          ),
          const SizedBox(height: 6),
          Text('把时间留给重要的事', style: TextStyle(color: skin.muted, fontSize: 11)),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: skin.border),
            ),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 19, color: skin.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '阅读半小时',
                    style: TextStyle(
                      color: skin.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.play_circle_fill_rounded,
                  size: 24,
                  color: skin.primary,
                ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              for (final color in [
                skin.primary,
                skin.accentLavender,
                skin.accentBlue,
                skin.accentMint,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 10),
                  ),
                ),
              const Spacer(),
              Text(
                '专注 30 分钟',
                style: TextStyle(color: skin.muted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _IconCard extends StatelessWidget {
  const _IconCard({
    required this.style,
    required this.selected,
    required this.onTap,
  });
  final AppIconStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${style.label}图标',
    child: Material(
      color: selected ? AppColors.blush : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(style.previewAsset, width: 88, height: 88),
              ),
              const SizedBox(height: 18),
              Text(
                style.label,
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
