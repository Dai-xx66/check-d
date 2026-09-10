import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/check_d_design.dart';
import '../../../shared/widgets/mascot.dart';
import '../../courses/presentation/schedule_template_page.dart';
import '../../courses/presentation/semester_settings_page.dart';
import '../../tags/presentation/tags_page.dart';
import 'reminder_settings_page.dart';

class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              desktop ? 28 : 16,
              desktop ? 18 : 8,
              desktop ? 28 : 16,
              32,
            ),
            children: [
              const _MyProfileHero(),
              SizedBox(height: desktop ? 24 : 20),
              desktop
                  ? _MyDesktopSettings(onOpen: _open)
                  : _MyMobileSettings(onOpen: _open),
            ],
          );
        },
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(
      context,
    ).push<void>(checkDPageRoute<void>(builder: (_) => page));
  }
}

class _MyProfileHero extends StatelessWidget {
  const _MyProfileHero();

  @override
  Widget build(BuildContext context) => CheckDSurface(
    level: CheckDSurfaceLevel.glassSoft,
    radius: BorderRadius.circular(24),
    color: const Color(0xD9FFF8F5),
    padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        return Row(
          children: [
            const CheckDSheep(
              state: SheepState.idle,
              size: MascotSize.hero,
              framed: false,
              compact: true,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我的小羊',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: wide ? 22 : 20),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '把每一天过成自己的节奏',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  if (wide) ...[
                    const SizedBox(height: 9),
                    const Text(
                      '记录每一步，也给自己留一点温柔。',
                      style: TextStyle(
                        color: AppColors.primaryStrong,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const CheckDIcon(CheckDIconType.forward, color: AppColors.muted),
          ],
        );
      },
    ),
  );
}

class _MyMobileSettings extends StatelessWidget {
  const _MyMobileSettings({required this.onOpen});

  final void Function(BuildContext, Widget) onOpen;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _MySection(
        title: '时间与课程',
        tone: AppColors.blueMist,
        children: [
          _MyTile(
            icon: CheckDIconType.schedule,
            color: AppColors.accentBlue,
            title: '作息模板',
            subtitle: '管理每日课程时间段',
            onTap: () => onOpen(context, const ScheduleTemplatePage()),
          ),
          _MyTile(
            icon: CheckDIconType.semester,
            color: AppColors.accentBlue,
            title: '学期与课程设置',
            subtitle: '管理课程安排与学期计划',
            onTap: () => onOpen(context, const SemesterSettingsPage()),
          ),
        ],
      ),
      _MySection(
        title: '事项与分类',
        tone: AppColors.lavender,
        children: [
          _MyTile(
            icon: CheckDIconType.tag,
            color: AppColors.accentLavender,
            title: '标签管理',
            subtitle: '编辑事项颜色与分类',
            onTap: () => onOpen(context, const TagsPage()),
          ),
          const _MyTile(
            icon: CheckDIconType.defaultItem,
            color: AppColors.accentLavender,
            title: '默认事项设置',
            subtitle: '预留默认目标与行为设置',
          ),
        ],
      ),
      _myReminderSection(onOpen, context),
      _MySection(
        title: '外观与小羊',
        tone: AppColors.lavender,
        children: const [
          _MyTile(
            icon: CheckDIconType.appearance,
            color: AppColors.accentLavender,
            title: '外观设置',
            subtitle: '主题、背景与显示偏好',
          ),
          _MyTile(
            icon: CheckDIconType.mascot,
            color: AppColors.accentLavender,
            title: '小羊 / IP 设置',
            subtitle: '管理小羊的显示与状态表现',
          ),
        ],
      ),
      _MySection(
        title: '数据',
        tone: AppColors.mint,
        children: const [
          _MyTile(
            icon: CheckDIconType.backup,
            color: AppColors.accentMint,
            title: '数据备份',
            subtitle: '查看备份与同步状态',
          ),
          _MyTile(
            icon: CheckDIconType.privacy,
            color: AppColors.accentMint,
            title: '数据与隐私',
            subtitle: '导出、清理与隐私说明',
          ),
        ],
      ),
      _MySection(
        title: '其他',
        tone: AppColors.cream,
        children: const [
          _MyTile(
            icon: CheckDIconType.help,
            color: AppColors.orange,
            title: '帮助与反馈',
            subtitle: '常见问题与意见反馈',
          ),
          _MyTile(
            icon: CheckDIconType.about,
            color: AppColors.orange,
            title: '关于 App',
            subtitle: '版本信息与项目说明',
          ),
        ],
      ),
    ],
  );
}

Widget _myReminderSection(
  void Function(BuildContext, Widget) onOpen,
  BuildContext context,
) => _MySection(
  title: '提醒与闹钟',
  tone: AppColors.blush,
  children: [
    _MyTile(
      icon: CheckDIconType.reminder,
      color: AppColors.primaryStrong,
      title: '提醒设置',
      subtitle: '管理事项与课程提醒',
      onTap: () => onOpen(context, const ReminderSettingsPage()),
    ),
    const _MyTile(
      icon: CheckDIconType.alarm,
      color: AppColors.primaryStrong,
      title: '闹钟设置',
      subtitle: '管理响铃与稍后提醒',
    ),
    _MyTile(
      icon: CheckDIconType.permission,
      color: AppColors.primaryStrong,
      title: '通知权限',
      subtitle: '查看系统通知权限状态',
      onTap: () => onOpen(context, const ReminderSettingsPage()),
    ),
  ],
);

class _MyDesktopSettings extends StatelessWidget {
  const _MyDesktopSettings({required this.onOpen});

  final void Function(BuildContext, Widget) onOpen;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _courseSection(context)),
          const SizedBox(width: 18),
          Expanded(child: _categorySection(context)),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _myReminderSection(onOpen, context)),
          const SizedBox(width: 18),
          Expanded(child: _appearanceSection()),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _dataSection()),
          const SizedBox(width: 18),
          Expanded(child: _otherSection()),
        ],
      ),
    ],
  );

  Widget _courseSection(BuildContext context) => _MySection(
    title: '时间与课程',
    tone: AppColors.blueMist,
    children: [
      _MyTile(
        icon: CheckDIconType.schedule,
        color: AppColors.accentBlue,
        title: '作息模板',
        subtitle: '管理每日课程时间段',
        onTap: () => onOpen(context, const ScheduleTemplatePage()),
      ),
      _MyTile(
        icon: CheckDIconType.semester,
        color: AppColors.accentBlue,
        title: '学期与课程设置',
        subtitle: '管理课程安排与学期计划',
        onTap: () => onOpen(context, const SemesterSettingsPage()),
      ),
    ],
  );

  Widget _categorySection(BuildContext context) => _MySection(
    title: '事项与分类',
    tone: AppColors.lavender,
    children: [
      _MyTile(
        icon: CheckDIconType.tag,
        color: AppColors.accentLavender,
        title: '标签管理',
        subtitle: '编辑事项颜色与分类',
        onTap: () => onOpen(context, const TagsPage()),
      ),
      const _MyTile(
        icon: CheckDIconType.defaultItem,
        color: AppColors.accentLavender,
        title: '默认事项设置',
        subtitle: '预留默认目标与行为设置',
      ),
    ],
  );

  Widget _appearanceSection() => _MySection(
    title: '外观与小羊',
    tone: AppColors.lavender,
    children: const [
      _MyTile(
        icon: CheckDIconType.appearance,
        color: AppColors.accentLavender,
        title: '外观设置',
        subtitle: '主题、背景与显示偏好',
      ),
      _MyTile(
        icon: CheckDIconType.mascot,
        color: AppColors.accentLavender,
        title: '小羊 / IP 设置',
        subtitle: '管理小羊的显示与状态表现',
      ),
    ],
  );

  Widget _dataSection() => _MySection(
    title: '数据',
    tone: AppColors.mint,
    children: const [
      _MyTile(
        icon: CheckDIconType.backup,
        color: AppColors.accentMint,
        title: '数据备份',
        subtitle: '查看备份与同步状态',
      ),
      _MyTile(
        icon: CheckDIconType.privacy,
        color: AppColors.accentMint,
        title: '数据与隐私',
        subtitle: '导出、清理与隐私说明',
      ),
    ],
  );

  Widget _otherSection() => _MySection(
    title: '其他',
    tone: AppColors.cream,
    children: const [
      _MyTile(
        icon: CheckDIconType.help,
        color: AppColors.orange,
        title: '帮助与反馈',
        subtitle: '常见问题与意见反馈',
      ),
      _MyTile(
        icon: CheckDIconType.about,
        color: AppColors.orange,
        title: '关于 App',
        subtitle: '版本信息与项目说明',
      ),
    ],
  );
}

class _MySection extends StatelessWidget {
  const _MySection({
    required this.title,
    required this.tone,
    required this.children,
  });

  final String title;
  final Color tone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 16),
          ),
        ),
        CheckDSurface(
          level: CheckDSurfaceLevel.raised,
          radius: BorderRadius.circular(20),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(children: _separatedChildren()),
        ),
      ],
    ),
  );

  List<Widget> _separatedChildren() {
    final result = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        result.add(
          Padding(
            padding: const EdgeInsets.only(left: 64),
            child: Divider(
              height: 1,
              thickness: .5,
              color: tone.withValues(alpha: .5),
            ),
          ),
        );
      }
      result.add(children[index]);
    }
    return result;
  }
}

class _MyTile extends StatelessWidget {
  const _MyTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final CheckDIconType icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => CheckDHoverLift(
    radius: BorderRadius.circular(16),
    child: CheckDPressable(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            CheckDIcon(icon, size: 19, color: color, backing: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const CheckDIcon(
              CheckDIconType.forward,
              size: 19,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}
