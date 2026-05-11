/// Validation and utility functions for the app
class ValidationService {
  // Email validation
  static String? validateEmail(String email) {
    if (email.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(email)) return 'Invalid email format';
    return null;
  }

  static bool isValidEmail(String email) => validateEmail(email) == null;

  // Password validation
  static String? validatePassword(String password) {
    if (password.isEmpty) return 'Password is required';
    if (password.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain at least one digit';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      return 'Password must contain at least one special character';
    }
    return null;
  }

  static bool isValidPassword(String password) => validatePassword(password) == null;

  // Phone number normalization and validation
  static String? normalizePhoneNumber(String phoneNumber) {
    if (phoneNumber.isEmpty) return null;

    // Remove all non-digit characters except leading +
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    // Remove leading + if present for processing
    final hasPlus = cleaned.startsWith('+');
    if (hasPlus) cleaned = cleaned.substring(1);

    // Extract only digits
    cleaned = cleaned.replaceAll(RegExp(r'\D'), '');

    if (cleaned.isEmpty) return null;

    // If no country code provided, default to +1 (US/Canada)
    if (!hasPlus && cleaned.length == 10) {
      return '+1$cleaned';
    }

    // If starts with country code but no +
    if (!hasPlus && cleaned.length >= 11) {
      return '+$cleaned';
    }

    // Already has + from original
    if (hasPlus && cleaned.length >= 10) {
      return '+$cleaned';
    }

    return null;
  }

  static String? validatePhoneNumber(String phoneNumber) {
    if (phoneNumber.isEmpty) return 'Phone number is required';
    final normalized = normalizePhoneNumber(phoneNumber);
    if (normalized == null) return 'Invalid phone number format';
    if (normalized.length < 12) return 'Phone number is too short';
    if (normalized.length > 15) return 'Phone number is too long';
    return null;
  }

  static bool isValidPhoneNumber(String phoneNumber) =>
      validatePhoneNumber(phoneNumber) == null;

  // Name validation
  static String? validateName(String name) {
    if (name.isEmpty) return 'Name is required';
    if (name.length < 2) return 'Name must be at least 2 characters';
    if (name.length > 50) return 'Name must be less than 50 characters';
    if (!RegExp(r"^[a-zA-Z\s'-]+$").hasMatch(name)) {
      return 'Name can only contain letters, spaces, hyphens, and apostrophes';
    }
    return null;
  }

  static bool isValidName(String name) => validateName(name) == null;

  // Age calculation
  static int calculateAge(DateTime dateOfBirth) {
    final today = DateTime.now();
    int age = today.year - dateOfBirth.year;
    if (today.month < dateOfBirth.month ||
        (today.month == dateOfBirth.month && today.day < dateOfBirth.day)) {
      age--;
    }
    return age;
  }

  static String? validateAge(DateTime dateOfBirth, {int minAge = 18, int maxAge = 65}) {
    final age = calculateAge(dateOfBirth);
    if (age < minAge) return 'You must be at least $minAge years old';
    if (age > maxAge) return 'Invalid date of birth';
    return null;
  }

  // URL validation
  static bool isValidUrl(String url) {
    try {
      Uri.parse(url);
      return url.startsWith('http://') || url.startsWith('https://');
    } catch (_) {
      return false;
    }
  }

  // Bio/About validation
  static String? validateBio(String bio, {int maxLength = 500}) {
    if (bio.isEmpty) return null; // Optional field
    if (bio.length > maxLength) return 'Bio must be less than $maxLength characters';
    return null;
  }

  // Image file validation
  static String? validateImageFile(String fileName, int fileSizeBytes,
      {int maxSizeMB = 10}) {
    const allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    final extension = fileName.split('.').last.toLowerCase();

    if (!allowedExtensions.contains(extension)) {
      return 'Invalid image format. Allowed: ${allowedExtensions.join(', ')}';
    }

    final maxSizeBytes = maxSizeMB * 1024 * 1024;
    if (fileSizeBytes > maxSizeBytes) {
      return 'Image size must be less than ${maxSizeMB}MB';
    }

    return null;
  }

  // Sanitize string input (remove potential injection attacks)
  static String sanitizeInput(String input) {
    return input
        .replaceAll(RegExp("[<>\"']"), '') // Remove HTML special chars
        .trim();
  }
}
