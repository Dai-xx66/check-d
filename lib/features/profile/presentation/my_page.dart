import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/mascot.dart';
import '../../courses/presentation/schedule_template_page.dart';
import '../../courses/presentation/semester_settings_page.dart';
import '../../tags/presentation/tags_page.dart';

class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const _ProfileHeader(),
          const SizedBox(height: 20),
          _SettingsSection(
            title: '时间与课程',
            children: [
              _SettingsTile(
                icon: Icons.schedule_rounded,
                color: AppColors.blueMist,
                title: '作息模板',
                subtitle: '管理每日课程时间段',
                onTap: () => _open(context, const ScheduleTemplatePage()),
              ),
              _SettingsTile(
                icon: Icons.school_rounded,
                color: AppColors.blueMist,
                title: '学期与课程设置',
                subtitle: '管理课程安排与学期计划',
                onTap: () => _open(context, const SemesterSettingsPage()),
              ),
            ],
          ),
          _SettingsSection(
            title: '事项与分类',
            children: [
              _SettingsTile(
                icon: Icons.sell_rounded,
                color: AppColors.lavender,
                title: '标签管理',
                subtitle: '编辑事项颜色与分类',
                onTap: () => _open(context, const TagsPage()),
              ),
              _SettingsTile(
                icon: Icons.tune_rounded,
                color: AppColors.lavender,
                title: '默认事项设置',
                subtitle: '预留默认目标与行为设置',
              ),
            ],
          ),
          _SettingsSection(
            title: '提醒与闹钟',
            children: [
              _SettingsTile(
                icon: Icons.notifications_active_rounded,
                color: AppColors.primary,
                title: '提醒设置',
                subtitle: '管理事项与课程提醒',
              ),
              _SettingsTile(
                icon: Icons.alarm_rounded,
                color: AppColors.primary,
                title: '闹钟设置',
                subtitle: '管理响铃与稍后提醒',
              ),
              _SettingsTile(
                icon: Icons.verified_user_rounded,
                color: AppColors.primary,
                title: '通知权限',
                subtitle: '查看系统通知权限状态',
              ),
            ],
          ),
          _SettingsSection(
            title: '外观与小羊',
            children: [
              _SettingsTile(
                icon: Icons.palette_rounded,
                color: AppColors.blush,
                title: '外观设置',
                subtitle: '主题、背景与显示偏好',
              ),
              _SettingsTile(
                icon: Icons.pets_rounded,
                color: AppColors.blush,
                title: '小羊 / IP 设置',
                subtitle: '管理小羊的显示与状态表现',
              ),
            ],
          ),
          _SettingsSection(
            title: '数据',
            children: [
              _SettingsTile(
                icon: Icons.cloud_upload_rounded,
                color: AppColors.mint,
                title: '数据备份',
                subtitle: '查看备份与同步状态',
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_rounded,
                color: AppColors.mint,
                title: '数据与隐私',
                subtitle: '导出、清理与隐私说明',
              ),
            ],
          ),
          _SettingsSection(
            title: '其他',
            children: [
              _SettingsTile(
                icon: Icons.help_rounded,
                color: AppColors.cream,
                title: '帮助与反馈',
                subtitle: '常见问题与意见反馈',
              ),
              _SettingsTile(
                icon: Icons.info_rounded,
                color: AppColors.cream,
                title: '关于 App',
                subtitle: '版本信息与项目说明',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const MascotWidget(state: MascotState.happy, size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('我的小羊', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text(
                    '把每一天过成自己的节奏',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: _withDividers(children)),
          ),
        ],
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    final result = <Widget>[];
    for (var index = 0; index < items.length; index++) {
      if (index > 0) result.add(const Divider(height: 1, indent: 72));
      result.add(items[index]);
    }
    return result;
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.24),
        foregroundColor: AppColors.ink,
        child: Icon(icon, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
      onTap: onTap,
    );
  }
}
