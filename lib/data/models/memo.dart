import 'package:flutter/foundation.dart';

enum MemoSource { text, voice }

/// A brain-dump entry — captured the instant a stray thought occurs, then
/// reviewed/triaged later from the inbox (STEP 11).
@immutable
class Memo {
  final String id;
  final String text;
  final MemoSource source;
  final String createdAtIso;
  final bool reviewed;
  final String? category;

  const Memo({
    required this.id,
    required this.text,
    required this.source,
    required this.createdAtIso,
    this.reviewed = false,
    this.category,
  });

  DateTime get createdAt => DateTime.parse(createdAtIso);

  Memo copyWith({String? text, bool? reviewed, String? category}) {
    return Memo(
      id: id,
      text: text ?? this.text,
      source: source,
      createdAtIso: createdAtIso,
      reviewed: reviewed ?? this.reviewed,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'source': source.name,
        'createdAtIso': createdAtIso,
        'reviewed': reviewed,
        'category': category,
      };

  factory Memo.fromMap(Map<String, dynamic> map) => Memo(
        id: map['id'] as String,
        text: map['text'] as String,
        source: MemoSource.values.firstWhere(
          (s) => s.name == map['source'],
          orElse: () => MemoSource.text,
        ),
        createdAtIso: map['createdAtIso'] as String,
        reviewed: (map['reviewed'] as bool?) ?? false,
        category: map['category'] as String?,
      );
}
