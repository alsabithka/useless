import '../challenge/challenge_state.dart';
import '../models/score_record.dart';
import 'local_score_store.dart';
import 'supabase_service.dart';

enum ScoreSyncState { savedLocally, synced, pending }

class ScorePersistenceService {
  final LocalScoreStore localStore;
  final SupabaseService supabase;

  ScorePersistenceService({LocalScoreStore? localStore, SupabaseService? supabase})
      : localStore = localStore ?? LocalScoreStore(),
        supabase = supabase ?? SupabaseService();

  Future<ScoreSyncState> saveChallenge({
    required ChallengeResult result,
    required String seed,
    required String mode,
  }) async {
    final record = ScoreRecord.fromChallenge(
      result: result,
      seed: seed,
      mode: mode,
    );
    await localStore.save(record);
    try {
      await supabase.submit(record);
      await localStore.markSynced(record.id);
      return ScoreSyncState.synced;
    } catch (_) {
      return supabase.isConfigured
          ? ScoreSyncState.pending
          : ScoreSyncState.savedLocally;
    }
  }

  Future<void> syncPending() async {
    for (final record in await localStore.pending()) {
      try {
        await supabase.submit(record);
        await localStore.markSynced(record.id);
      } catch (_) {
        return;
      }
    }
  }
}