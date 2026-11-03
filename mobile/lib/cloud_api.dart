import 'dart:convert';
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:http/http.dart' as http;

class CloudApiException implements Exception {
  const CloudApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Appwrite Auth + one authenticated Kindred Function + private R2 photo URLs.
/// Project IDs and endpoints are public configuration; no server secret is here.
class CloudApi {
  CloudApi({
    required String endpoint,
    required String projectId,
    required this.functionId,
  }) : client = Client().setEndpoint(endpoint).setProject(projectId) {
    account = Account(client);
    functions = Functions(client);
  }

  final String functionId;
  final Client client;
  late final Account account;
  late final Functions functions;

  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    try {
      final execution = await functions.createExecution(
        functionId: functionId,
        xasync: false,
        path: path,
        method: switch (method) {
          'GET' => enums.ExecutionMethod.gET,
          'POST' => enums.ExecutionMethod.pOST,
          'PATCH' => enums.ExecutionMethod.pATCH,
          'DELETE' => enums.ExecutionMethod.dELETE,
          _ => throw const CloudApiException('Unsupported request.'),
        },
        body: jsonEncode(body ?? <String, dynamic>{}),
        headers: {'content-type': 'application/json'},
      );
      final result = jsonDecode(execution.responseBody) as Map<String, dynamic>;
      if (execution.responseStatusCode >= 400) {
        throw CloudApiException(
          result['error']?.toString() ?? 'Request failed.',
        );
      }
      return result;
    } on AppwriteException catch (error) {
      throw CloudApiException(error.message ?? 'Cloud service is unavailable.');
    } on FormatException {
      throw const CloudApiException(
        'The cloud service returned an invalid response.',
      );
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      await account.createEmailPasswordSession(
        email: email.trim(),
        password: password,
      );
      return await request('GET', '/api/me');
    } on AppwriteException catch (error) {
      throw CloudApiException(error.message ?? 'Sign-in failed.');
    }
  }

  Future<Map<String, dynamic>> signup(Map<String, dynamic> data) async {
    try {
      try {
        await account.create(
          userId: ID.unique(),
          email: data['email'].toString().trim(),
          password: data['password'].toString(),
          name: data['name'].toString().trim(),
        );
      } on AppwriteException catch (error) {
        // A previous profile request may have failed after Auth was created.
        // Sign-in below still requires that account's correct password.
        if (error.code != 409) rethrow;
      }
      await account.createEmailPasswordSession(
        email: data['email'].toString().trim(),
        password: data['password'].toString(),
      );
      // The profile endpoint is idempotent, so a transient failure can be retried.
      try {
        return await request('POST', '/api/profile', data);
      } catch (_) {
        return await request('POST', '/api/profile', data);
      }
    } on AppwriteException catch (error) {
      throw CloudApiException(error.message ?? 'Sign-up failed.');
    }
  }

  Future<void> logout() async {
    try {
      await account.deleteSession(sessionId: 'current');
    } on AppwriteException catch (error) {
      throw CloudApiException(error.message ?? 'Sign-out failed.');
    }
  }

  Future<Uint8List?> photo(String id) async {
    try {
      final data = await request('GET', '/api/photo/$id');
      final url = data['url']?.toString();
      if (url == null) return null;
      final response = await http.get(Uri.parse(url));
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> uploadPhoto(Uint8List bytes, String mime) async {
    if (bytes.length > 350 * 1024) {
      throw const CloudApiException(
        'Photo is too large. Choose a smaller image (under 350 KB).',
      );
    }
    final prepared = await request('POST', '/api/photo/prepare', {
      'mime': mime,
      'bytes': bytes.length,
    });
    final response = await http.put(
      Uri.parse(prepared['url'].toString()),
      headers: {'Content-Type': mime},
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const CloudApiException('Photo upload failed. Please try again.');
    }
    return request('POST', '/api/photo/complete', {
      'uploadId': prepared['uploadId'],
    });
  }
}
