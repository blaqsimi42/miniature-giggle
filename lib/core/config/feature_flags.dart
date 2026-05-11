class FeatureFlags {
  static const bool enableGoogleSignIn = true;
  static const bool enableFacebookSignIn = true;
  static const bool enableTikTokSignIn = false;
  static const bool enablePremiumChat = true;

  static bool get hasAnySocialSignIn =>
      enableGoogleSignIn || enableFacebookSignIn || enableTikTokSignIn;
}
