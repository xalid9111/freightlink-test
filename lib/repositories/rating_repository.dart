import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../models/rating_model.dart';

class RatingRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<RatingModel> submit(RatingModel rating) async {
    // RLS (migration 0002) only allows this once the shipment status is
    // 'completed' and the reviewer was a real participant in it.
    final row = await _client.from('ratings').insert(rating.toInsertJson()).select().single();
    return RatingModel.fromJson(row);
  }

  Future<List<RatingModel>> fetchForUser(String userId) async {
    final rows = await _client.from('ratings').select().eq('reviewed_user_id', userId);
    return (rows as List).map((r) => RatingModel.fromJson(r)).toList();
  }
}
