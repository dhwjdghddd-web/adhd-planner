import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../data/models/routine_preset.dart';
import '../../data/providers.dart';
import '../settings/settings_controller.dart';

const _uuid = Uuid();

/// Modal sheet to view, add, rename, and delete routine presets.
class PresetManagementSheet extends ConsumerStatefulWidget {
  const PresetManagementSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const PresetManagementSheet(),
    );
  }

  @override
  ConsumerState<PresetManagementSheet> createState() =>
      _PresetManagementSheetState();
}

class _PresetManagementSheetState extends ConsumerState<PresetManagementSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider).value;
    final presets = settings?.presets ?? RoutinePreset.defaultPresets;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '루틴 프리셋 관리',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '생활 패턴별로 프리셋을 생성하고, 캘린더나 구간 관리에서 적용할 수 있어요.',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: presets.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final preset = presets[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Color(preset.colorValue),
                      radius: 14,
                      child: Icon(
                        preset.id == 'rest'
                            ? Icons.beach_access
                            : Icons.work_outline,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      preset.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      preset.isDefault ? '기본 프리셋' : '사용자 정의 프리셋',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: '이름 변경',
                          onPressed: () => _editPresetName(preset, presets),
                        ),
                        if (!preset.isDefault)
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.redAccent,
                            ),
                            tooltip: '삭제',
                            onPressed: () => _deletePreset(preset, presets),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _addNewPreset(presets),
              icon: const Icon(Icons.add),
              label: const Text('새 프리셋 만들기'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _editPresetName(
    RoutinePreset preset,
    List<RoutinePreset> currentPresets,
  ) async {
    final controller = TextEditingController(text: preset.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('프리셋 이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '프리셋 이름'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('변경'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == preset.name) return;

    final updated = currentPresets.map((p) {
      if (p.id == preset.id) {
        return p.copyWith(name: newName);
      }
      return p;
    }).toList();

    _savePresets(updated);
  }

  Future<void> _deletePreset(
    RoutinePreset preset,
    List<RoutinePreset> currentPresets,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('프리셋 삭제'),
        content: Text('\'\' 프리셋을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final updated = currentPresets.where((p) => p.id != preset.id).toList();
    _savePresets(updated);
  }

  Future<void> _addNewPreset(List<RoutinePreset> currentPresets) async {
    final nameController = TextEditingController();
    int selectedColor = kSegmentPalette.first.toARGB32();

    final result = await showDialog<RoutinePreset>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('새 프리셋 만들기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '프리셋 이름',
                  hintText: '예: 야간 당직, 연차/휴가',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '대표 색상',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kSegmentPalette)
                    InkWell(
                      onTap: () {
                        setDlgState(() => selectedColor = c.toARGB32());
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: selectedColor == c.toARGB32()
                              ? Border.all(color: Colors.white, width: 2.5)
                              : null,
                          boxShadow: selectedColor == c.toARGB32()
                              ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final newPreset = RoutinePreset(
                  id: _uuid.v4(),
                  name: name,
                  colorValue: selectedColor,
                  isDefault: false,
                );
                Navigator.pop(ctx, newPreset);
              },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final updated = [...currentPresets, result];
    _savePresets(updated);
  }

  void _savePresets(List<RoutinePreset> presets) {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    ref
        .read(settingsControllerProvider)
        .save(settings.copyWith(presets: presets));
  }
}
