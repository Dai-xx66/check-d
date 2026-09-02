import 'package:flutter/material.dart';

import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/page_header.dart';

class ReviewsPage extends StatelessWidget {
  const ReviewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(title: '复盘', subtitle: '把客观数据和主观感受放在一起'),
            SizedBox(height: 22),
            EmptyState(
              icon: Icons.edit_note_rounded,
              title: '今天还没有复盘',
              message: '日、周、月和年度复盘将在 Phase 7 开放。',
            ),
          ],
        ),
      ),
    );
  }
}
