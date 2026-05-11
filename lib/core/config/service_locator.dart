import 'package:get_it/get_it.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../services/chat_service.dart';
import '../../services/chat_access_service.dart';
import '../../services/storage_service.dart';
import '../../services/interactions_service.dart';
import '../../services/fcm_service.dart';
import '../../services/mock_payment_service.dart';
import '../../services/network_status_service.dart';
import '../../services/stripe_service.dart';
import '../../services/premium_service.dart';
import '../../bloc/discover_profile_bloc.dart';
import '../../bloc/edit_profile_bloc.dart';

final getIt = GetIt.instance;

/// Setup and register all services and blocs
Future<void> setupServiceLocator() async {
  if (getIt.isRegistered<AuthService>()) {
    return;
  }

  // Register services
  getIt.registerSingleton<AuthService>(AuthService());
  getIt.registerSingleton<UserService>(UserService());
  getIt.registerSingleton<ChatService>(ChatService());
  getIt.registerSingleton<ChatAccessService>(
    ChatAccessService(
      authService: getIt<AuthService>(),
      userService: getIt<UserService>(),
    ),
  );
  getIt.registerSingleton<StorageService>(StorageService());
  getIt.registerSingleton<InteractionsService>(InteractionsService());
  getIt.registerSingleton<FcmService>(FcmService());
  getIt.registerSingleton<NetworkStatusService>(NetworkStatusService());
  getIt.registerSingleton<MockPaymentService>(MockPaymentService());
  getIt.registerSingleton<StripeService>(StripeService());
  getIt.registerSingleton<PremiumService>(PremiumService());

  // Register blocs (use factory for new instances each time)
  getIt.registerSingleton<DiscoverProfileBloc>(
    DiscoverProfileBloc(
      userService: getIt<UserService>(),
      interactionsService: getIt<InteractionsService>(),
      authService: getIt<AuthService>(),
    ),
  );

  getIt.registerSingleton<EditProfileBloc>(
    EditProfileBloc(
      userService: getIt<UserService>(),
      storageService: getIt<StorageService>(),
      authService: getIt<AuthService>(),
    ),
  );
}

/// Cleanup when app is being closed
Future<void> cleanupServiceLocator() async {
  await getIt<DiscoverProfileBloc>().close();
  await getIt<EditProfileBloc>().close();
}
