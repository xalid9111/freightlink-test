import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../models/ai_match_model.dart';

class AiMatchRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Reads persisted matches (written by the ai-match Edge Function,
  /// see supabase/functions/ai-match). The client never calls OpenAI
  /// directly — see docs/reports/PHASE2_REPORT.md item 7.
  Future<List<AiMatchModel>> fetchForCarrier(String carrierId) async {
    final rows = await _client
        .from('ai_matches')
        .select()
        .eq('carrier_id', carrierId)
        .order('match_score', ascending: false);
    return (rows as List).map((r) => AiMatchModel.fromJson(r)).toList();
  }

  /// Triggers a fresh matching run for this carrier (implemented in
  /// Phase 11 — invokes the Edge Function, which writes back to
  /// ai_matches with the service-role key).
  Future<void> requestMatchRefresh(String carrierId) async {
    await _client.functions.invoke('ai-match', body: {'carrierId': carrierId});
  }
}
