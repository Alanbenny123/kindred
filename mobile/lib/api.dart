import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_api.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Api {
  Api._();
  static final Api instance = Api._();

  static const configuredUrl = String.fromEnvironment('API_BASE_URL');
  static const appwriteEndpoint = String.fromEnvironment('APPWRITE_ENDPOINT');
  static const appwriteProjectId = String.fromEnvironment(
    'APPWRITE_PROJECT_ID',
  );
  static const appwriteFunctionId = String.fromEnvironment(
    'APPWRITE_FUNCTION_ID',
  );
  bool get isCloud => appwriteEndpoint.isNotEmpty;
  CloudApi? _cloud;
  String? _overrideUrl;
  String get baseUrl =>
      _overrideUrl ??
      (configuredUrl.isNotEmpty
          ? configuredUrl
          : Platform.isAndroid
          ? 'http://10.0.2.2:3000'
          : 'http://127.0.0.1:3000');

  String? _cookie;
  final Map<String, Uint8List> _photoCache = {};

  Future<void> init() async {
    if (isCloud) {
      if (appwriteProjectId.isEmpty || appwriteFunctionId.isEmpty) {
        throw const ApiException(
          'Cloud build needs APPWRITE_PROJECT_ID and APPWRITE_FUNCTION_ID.',
        );
      }
      _cloud = CloudApi(
        endpoint: appwriteEndpoint,
        projectId: appwriteProjectId,
        functionId: appwriteFunctionId,
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _cookie = prefs.getString('session');
    _overrideUrl = prefs.getString('server_url');
  }

  Future<void> configureUrl(String value) async {
    if (isCloud) throw const ApiException('This cloud build uses Appwrite.');
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ApiException(
        'Enter a full server address, such as http://192.168.1.10:3000.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    if (normalized != baseUrl) {
      _cookie = null;
      _photoCache.clear();
      await prefs.remove('session');
    }
    _overrideUrl = normalized;
    await prefs.setString('server_url', normalized);
  }

  Future<void> _saveCookie(http.Response response) async {
    final raw = response.headers['set-cookie'];
    if (raw == null) return;
    final token = raw.split(';').first;
    final prefs = await SharedPreferences.getInstance();
    if (token.endsWith('=')) {
      _cookie = null;
      await prefs.remove('session');
    } else {
      _cookie = token;
      await prefs.setString('session', token);
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (_cloud != null) return _cloud!.request(method, path, body);
    try {
      final uri = Uri.parse('$baseUrl$path');
      final headers = <String, String>{'Accept': 'application/json'};
      if (body != null) headers['Content-Type'] = 'application/json';
      if (_cookie != null) headers['Cookie'] = _cookie!;
      late http.Response response;
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
        case 'PATCH':
          response = await http.patch(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
        case 'DELETE':
          response = await http.delete(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
        default:
          throw const ApiException('Unsupported request.');
      }
      await _saveCookie(response);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw ApiException(json['error']?.toString() ?? 'Request failed.');
      }
      return json;
    } on SocketException {
      throw ApiException(
        'Cannot reach the server at $baseUrl. Start it with npm start.',
      );
    } on http.ClientException {
      throw ApiException('Cannot reach the server at $baseUrl.');
    }
  }

  Future<Map<String, dynamic>> me() => request('GET', '/api/me');
  Future<Map<String, dynamic>> login(String email, String password) =>
      _cloud != null
      ? _cloud!.login(email, password)
      : request('POST', '/api/login', {'email': email, 'password': password});
  Future<Map<String, dynamic>> signup(Map<String, dynamic> data) =>
      _cloud != null
      ? _cloud!.signup(data)
      : request('POST', '/api/signup', data);
  Future<void> logout() async {
    if (_cloud != null) {
      await _cloud!.logout();
    } else {
      await request('POST', '/api/logout');
    }
    _photoCache.clear();
  }

  Future<Uint8List?> photo(String id) async {
    if (_photoCache.containsKey(id)) return _photoCache[id];
    if (_cloud != null) {
      final bytes = await _cloud!.photo(id);
      if (bytes != null) _photoCache[id] = bytes;
      return bytes;
    }
    try {
      final headers = <String, String>{};
      if (_cookie != null) headers['Cookie'] = _cookie!;
      final response = await http.get(
        Uri.parse('$baseUrl/api/photo/$id'),
        headers: headers,
      );
      if (response.statusCode != 200) return null;
      _photoCache[id] = response.bodyBytes;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> uploadPhoto(Uint8List bytes, String mime) async {
    if (_cloud != null) {
      final result = await _cloud!.uploadPhoto(bytes, mime);
      _photoCache.clear();
      return result;
    }
    try {
      final headers = <String, String>{'Content-Type': mime};
      if (_cookie != null) headers['Cookie'] = _cookie!;
      final response = await http.post(
        Uri.parse('$baseUrl/api/photo'),
        headers: headers,
        body: bytes,
      );
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw ApiException(json['error']?.toString() ?? 'Upload failed.');
      }
      _photoCache.clear();
      return json;
    } on SocketException {
      throw ApiException('Cannot reach the server at $baseUrl.');
    }
  }
}
