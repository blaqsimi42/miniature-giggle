class GuardianService {
  Future<void> sendInvitation({
    required String guardianName,
    required String relationship,
    required String phone,
  }) async {
    // TODO: integrate SmsService and Firestore write
    // Write guardian sub-document to Firestore under:
    // /users/{uid}/guardians/{guardianPhone}
    // Then call SmsService().sendSms(toPhone: phone, message: '...')
    await Future.delayed(const Duration(seconds: 2));
  }
}
