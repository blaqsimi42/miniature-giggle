import '../core/config/feature_flags.dart';
import 'auth_service.dart';
import 'user_service.dart';

class ChatAccessService {
  final AuthService _authService;
  final UserService _userService;

  ChatAccessService({
    AuthService? authService,
    UserService? userService,
  }) : _authService = authService ?? AuthService(),
       _userService = userService ?? UserService();

  Future<bool> canCurrentUserChat() async {
    if (!FeatureFlags.enablePremiumChat) {
      return true;
    }

    final currentUser = _authService.getCurrentUser();
    if (currentUser == null) {
      return false;
    }

    final profile = await _userService.getUser(currentUser.uid);
    return profile?.isPremium == true;
  }
}
