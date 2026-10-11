import '../../infrastructure/supabase/supabase_support_adapter.dart';
import 'support_adapter.dart';

/// One support destination for the whole app.
class SupportRepository {
  SupportRepository([SupportAdapter? adapter])
      : _adapter = adapter ?? SupabaseSupportAdapter();

  final SupportAdapter _adapter;

  Future<String?> fetchWhatsAppPhone() => _adapter.fetchWhatsAppPhone();

  /// The database RPC authorizes only the System Admin.
  Future<void> setWhatsAppPhone(String? phone) =>
      _adapter.setWhatsAppPhone(phone);
}
