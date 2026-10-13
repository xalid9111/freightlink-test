import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../domain/carrier_repository.dart';

class CarrierRepositoryImpl implements CarrierRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  @override
  Future<String?> fetchMyCarrierId() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client.from('carriers').select('id').eq('user_id', uid).maybeSingle();
    return row?['id'] as String?;
  }

  @override
  Future<String?> fetchUserIdForCarrier(String carrierId) async {
    final row = await _client.from('carriers').select('user_id').eq('id', carrierId).maybeSingle();
    return row?['user_id'] as String?;
  }
}
