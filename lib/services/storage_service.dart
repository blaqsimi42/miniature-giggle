import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_base.dart';
import '../widgets/beautiful_loader.dart';

class StorageService {
  static const String _cloudName = 'drduah4pi';
  static const String _uploadPreset = 'Matrimonial_app';

  Uri get _uploadUri =>
      Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

  /// Uploads profile image bytes to Cloudinary and returns the hosted image URL.
  Future<String> uploadProfileImage({
    required List<int> bytes,
    required String uid,
    required String filename,
    BuildContext? context,
  }) async {
    Future<String> uploadInner() async {
      final folder = 'matrimonial_app/profile_images/$uid';

      // Try to get signed params from signer service
      try {
        final signResp = await http.post(
          Uri.parse('$kApiBaseUrl/sign'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'folder': folder}),
        );

        if (signResp.statusCode == 200) {
          final signed = jsonDecode(signResp.body) as Map<String, dynamic>;
          final cloudName = signed['cloud_name'] as String? ?? _cloudName;
          final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

          final request = http.MultipartRequest('POST', uri)
            ..fields['api_key'] = signed['api_key'].toString()
            ..fields['timestamp'] = signed['timestamp'].toString()
            ..fields['signature'] = signed['signature'].toString()
            ..fields['folder'] = folder;

          request.files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );

          final streamedResponse = await request.send();
          final response = await http.Response.fromStream(streamedResponse);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception('Cloudinary signed upload failed (${response.statusCode}): ${response.body}');
          }
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          final secureUrl = payload['secure_url'] as String?;
          if (secureUrl == null || secureUrl.isEmpty) {
            throw Exception('Cloudinary upload succeeded without a secure_url.');
          }
          return secureUrl;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[StorageService] signer request failed, falling back to unsigned: $e');
        // fall through to unsigned approach
      }

      // Unsigned fallback
      final request = http.MultipartRequest('POST', _uploadUri)
        ..fields['upload_preset'] = _uploadPreset
        ..fields['folder'] = folder;
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Cloudinary upload failed (${response.statusCode}): ${response.body}',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final secureUrl = payload['secure_url'] as String?;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('Cloudinary upload succeeded without a secure_url.');
      }
      return secureUrl;
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, uploadInner);
    }

    return await uploadInner();
  }

  Future<String> uploadChatImage({
    required List<int> bytes,
    required String uid,
    required String filename,
    BuildContext? context,
  }) async {
    Future<String> uploadInner() async {
      final folder = 'matrimonial_app/chat_images/$uid';

      // Try signed upload via signer
      try {
        final signResp = await http.post(
          Uri.parse('$kApiBaseUrl/sign'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'folder': folder}),
        );

        if (signResp.statusCode == 200) {
          final signed = jsonDecode(signResp.body) as Map<String, dynamic>;
          final cloudName = signed['cloud_name'] as String? ?? _cloudName;
          final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

          final request = http.MultipartRequest('POST', uri)
            ..fields['api_key'] = signed['api_key'].toString()
            ..fields['timestamp'] = signed['timestamp'].toString()
            ..fields['signature'] = signed['signature'].toString()
            ..fields['folder'] = folder;

          request.files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );

          final streamedResponse = await request.send();
          final response = await http.Response.fromStream(streamedResponse);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception('Cloudinary signed upload failed (${response.statusCode}): ${response.body}');
          }
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          final secureUrl = payload['secure_url'] as String?;
          if (secureUrl == null || secureUrl.isEmpty) {
            throw Exception('Cloudinary upload succeeded without a secure_url.');
          }
          return secureUrl;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[StorageService] signer request failed, falling back to unsigned: $e');
      }

      // Unsigned fallback
      final request = http.MultipartRequest('POST', _uploadUri)
        ..fields['upload_preset'] = _uploadPreset
        ..fields['folder'] = folder;
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Cloudinary upload failed (${response.statusCode}): ${response.body}',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final secureUrl = payload['secure_url'] as String?;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('Cloudinary upload succeeded without a secure_url.');
      }
      return secureUrl;
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, uploadInner);
    }

    return await uploadInner();
  }

  /// Unsigned client-side Cloudinary uploads cannot securely delete assets.
  /// We remove the stored URL from Firestore and leave asset cleanup for a
  /// future signed/backend flow.
  Future<void> deleteFileByUrl(String url, {BuildContext? context}) async {
    Future<void> deleteInner() async {
      try {
        final publicId = _extractPublicIdFromUrl(url);
        if (publicId == null) {
          if (kDebugMode) debugPrint('[StorageService] could not extract public_id from url: $url');
          return;
        }

        final resp = await http.post(
          Uri.parse('$kApiBaseUrl/delete'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'public_id': publicId}),
        );

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          if (kDebugMode) debugPrint('[StorageService] delete requested for $publicId');
        } else {
          if (kDebugMode) debugPrint('[StorageService] delete request failed: ${resp.statusCode} ${resp.body}');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[StorageService] deleteFileByUrl error: $e');
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, deleteInner);
    }

    return await deleteInner();
  }

  String? _extractPublicIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final uploadIndex = segments.indexWhere((s) => s == 'upload');
      if (uploadIndex == -1 || uploadIndex + 1 >= segments.length) return null;
      final postUpload = segments.sublist(uploadIndex + 1);
      // Remove version segment if present (e.g., v1623456789)
      if (postUpload.isNotEmpty && postUpload.first.startsWith('v')) {
        postUpload.removeAt(0);
      }
      // Join remaining segments and strip file extension
      final joined = postUpload.join('/');
      final lastDot = joined.lastIndexOf('.');
      final publicId = lastDot > 0 ? joined.substring(0, lastDot) : joined;
      return publicId;
    } catch (_) {
      return null;
    }
  }
}
