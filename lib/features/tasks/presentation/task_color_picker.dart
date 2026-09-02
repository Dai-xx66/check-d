import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const taskColorValues = [
  0xFF3D73E8,
  0xFF45A77A,
  0xFFE69545,
  0xFF8267D9,
  0xFFD96060,
  0xFF3BA3AC,
];

class TaskColorPicker extends StatelessWidget {
  const TaskColorPicker({
    required this.selectedValue,
    required this.onSelected,
    super.key,
  });

  final int selectedValue;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('任务颜色', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final value in taskColorValues)
              Semantics(
                label: '选择任务颜色',
                button: true,
                selected: selectedValue == value,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => onSelected(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selectedValue == value
                            ? AppColors.ink
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: selectedValue == value
                        ? const Icon(Icons.check_rounded, color: Colors.white)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
