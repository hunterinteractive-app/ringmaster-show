/// Request and problem flags are independent of receiving a sanction number.
/// They must be removed through the directory's explicit flag action.
bool preserveSanctionWithoutNumber(String? requestStatus) {
  final status = requestStatus?.trim().toLowerCase() ?? '';
  return status.isNotEmpty && status != 'received';
}
