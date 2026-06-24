import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/memo.dart';
import '../../data/providers.dart';

const _uuid = Uuid();

final memosControllerProvider = Provider<MemosController>(
  (ref) => MemosController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for the memo inbox
/// and the quick-add sheet, mirroring `RoutinesController`/
/// `SegmentsController`.
class MemosController {
  MemosController(this._ref);

  final Ref _ref;

  Future<void> add(String text, {required MemoSource source}) {
    final memo = Memo(
      id: _uuid.v4(),
      text: text,
      source: source,
      createdAtIso: DateTime.now().toIso8601String(),
    );
    return _ref.read(plannerRepositoryProvider)!.addMemo(memo);
  }

  Future<void> setReviewed(Memo memo, bool reviewed) {
    return _ref.read(plannerRepositoryProvider)!.updateMemo(memo.copyWith(reviewed: reviewed));
  }

  /// Edits an existing memo's text (keeping its id/created time/reviewed state).
  Future<void> edit(Memo memo, String text) {
    return _ref.read(plannerRepositoryProvider)!.updateMemo(memo.copyWith(text: text));
  }

  Future<void> delete(String id) => _ref.read(plannerRepositoryProvider)!.deleteMemo(id);
}
