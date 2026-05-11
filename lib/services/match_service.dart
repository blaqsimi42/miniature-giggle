import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/config/api_base.dart';

class MatchService {
  final String baseUrl;
  MatchService({String? baseUrl}) : baseUrl = baseUrl ?? kApiBaseUrl;

  Future<Map<String, dynamic>> getMatches({
    required Map<String, dynamic> filters,
    int pageSize = 20,
    String? pageToken,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final idToken = await user.getIdToken();

    final body = {'filters': filters, 'pageSize': pageSize, 'pageToken': pageToken};
    final resp = await http.post(
      Uri.parse('$baseUrl/matches'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) throw Exception('Matches request failed: ${resp.body}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}
