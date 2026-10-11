/// Storage boundary for Go Play's single platform-managed support phone.
/// A community administrator has no special access to update it.
abstract interface class SupportAdapter {
  Future<String?> fetchWhatsAppPhone();
  Future<void> setWhatsAppPhone(String? phone);
}
