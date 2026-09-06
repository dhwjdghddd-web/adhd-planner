import 'package:flutter/foundation.dart';

/// User-definable routine preset (e.g. "근무일", "쉬는 날", "야간 당직", "휴가").
/// Each block ([Segment]) belongs to one preset. Calendar days map to a preset.
@immutable
class RoutinePreset {
  final String id;
  final String name;
  final int colorValue;
  final String iconKey;
  final bool isDefault;

  const RoutinePreset({
    required this.id,
    required this.name,
    this.colorValue = 0xFF1E88E5,
    this.iconKey = 'work',
    this.isDefault = false,
  });

  static const work = RoutinePreset(
    id: 'work',
    name: '근무일',
    colorValue: 0xFF1E88E5,
    iconKey: 'work',
    isDefault: true,
  );

  static const rest = RoutinePreset(
    id: 'rest',
    name: '쉬는 날',
    colorValue: 0xFFFB8C00,
    iconKey: 'beach_access',
    isDefault: true,
  );

  static const List<RoutinePreset> defaultPresets = [work, rest];

  RoutinePreset copyWith({
    String? name,
    int? colorValue,
    String? iconKey,
    bool? isDefault,
  }) {
    return RoutinePreset(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'iconKey': iconKey,
        'isDefault': isDefault,
      };

  factory RoutinePreset.fromMap(Map<String, dynamic> map) {
    return RoutinePreset(
      id: (map['id'] as String?) ?? 'work',
      name: (map['name'] as String?) ?? '근무일',
      colorValue: (map['colorValue'] as num?)?.toInt() ?? 0xFF1E88E5,
      iconKey: (map['iconKey'] as String?) ?? 'work',
      isDefault: (map['isDefault'] as bool?) ?? false,
    );
  }
}
