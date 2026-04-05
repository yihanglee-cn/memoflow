import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/local_memo.dart';
import 'memo_mutation_service.dart';
import 'memo_timeline_provider.dart';

final memoDeleteServiceProvider = Provider<MemoDeleteService>((ref) {
  return MemoDeleteService(ref);
});

class MemoDeleteService {
  MemoDeleteService(this._ref);

  final Ref _ref;

  Future<void> deleteMemo(
    LocalMemo memo, {
    void Function()? onMovedToRecycleBin,
  }) async {
    final timelineService = _ref.read(memoTimelineServiceProvider);
    await timelineService.moveMemoToRecycleBin(memo);
    onMovedToRecycleBin?.call();
    await _ref
        .read(memoMutationServiceProvider)
        .deleteMemoAfterRecycleBinMove(memo);
  }
}
