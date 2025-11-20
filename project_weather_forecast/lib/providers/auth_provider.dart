import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart' show Value;
import '../database/app_database.dart';
import 'database_provider.dart';

class AuthProvider with ChangeNotifier {
  final AppDatabase database;
  final DatabaseProvider databaseProvider;

  static const String _sessionTokenKey = 'user_session_token';

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  AuthProvider({required this.database, required this.databaseProvider});

  /// Hash password using SHA256
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Generate random session token
  String _generateSessionToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  /// Save session token to SharedPreferences
  Future<void> _saveSessionToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionTokenKey, token);
  }

  /// Get session token from SharedPreferences
  Future<String?> _getSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionTokenKey);
  }

  /// Clear session token from SharedPreferences
  Future<void> _clearSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTokenKey);
  }

  /// Check if user has valid session
  Future<bool> checkSession() async {
    try {
      final token = await _getSessionToken();
      if (token == null) return false;

      final user = await database.getUserBySession(token);
      if (user != null) {
        _isAuthenticated = true;
        await databaseProvider.initialize(userEmail: user.email);
        notifyListeners();
        return true;
      }

      // Session expired or invalid
      await _clearSessionToken();
      return false;
    } catch (e) {
      debugPrint('Error checking session: $e');
      return false;
    }
  }

  /// Login with email and password
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      // Get user by email
      final user = await database.getUserByEmail(email);

      if (user == null) {
        return {'success': false, 'message': 'Email không tồn tại'};
      }

      // Verify password
      final hashedPassword = _hashPassword(password);
      if (user.password != hashedPassword) {
        return {'success': false, 'message': 'Mật khẩu không đúng'};
      }

      // Generate session token
      final sessionToken = _generateSessionToken();

      // Create session in database
      await database.createSession(user.id, sessionToken);

      // Save token to SharedPreferences
      await _saveSessionToken(sessionToken);

      // Initialize database provider with user data
      await databaseProvider.initialize(userEmail: email);

      _isAuthenticated = true;
      notifyListeners();

      return {'success': true, 'message': 'Đăng nhập thành công', 'user': user};
    } catch (e) {
      debugPrint('Login error: $e');
      return {'success': false, 'message': 'Lỗi đăng nhập: ${e.toString()}'};
    }
  }

  /// Register new user
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      // Check if email already exists
      final exists = await database.emailExists(email);
      if (exists) {
        return {'success': false, 'message': 'Email đã được sử dụng'};
      }

      // Hash password
      final hashedPassword = _hashPassword(password);

      // Create user
      final userId = await database.insertUser(
        UsersCompanion.insert(
          email: email,
          password: hashedPassword,
          displayName: Value(displayName),
          uid: _generateSessionToken(), // Use as unique user ID
          createdAt: Value(DateTime.now()),
        ),
      );

      // Generate session token
      final sessionToken = _generateSessionToken();

      // Create session
      await database.createSession(userId, sessionToken);

      // Save token to SharedPreferences
      await _saveSessionToken(sessionToken);

      // Initialize database provider
      await databaseProvider.initialize(userEmail: email);

      _isAuthenticated = true;
      notifyListeners();

      return {'success': true, 'message': 'Đăng ký thành công'};
    } catch (e) {
      debugPrint('Register error: $e');
      return {'success': false, 'message': 'Lỗi đăng ký: ${e.toString()}'};
    }
  }

  /// Logout user
  Future<void> logout() async {
    try {
      final user = databaseProvider.currentUser;
      if (user != null) {
        await database.clearSession(user.id);
      }

      await _clearSessionToken();

      _isAuthenticated = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  /// Change password
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = databaseProvider.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'Chưa đăng nhập'};
      }

      // Verify current password
      final hashedCurrentPassword = _hashPassword(currentPassword);
      if (user.password != hashedCurrentPassword) {
        return {'success': false, 'message': 'Mật khẩu hiện tại không đúng'};
      }

      // Update password
      final hashedNewPassword = _hashPassword(newPassword);
      await database.updateUser(
        UsersCompanion(id: Value(user.id), password: Value(hashedNewPassword)),
      );

      return {'success': true, 'message': 'Đổi mật khẩu thành công'};
    } catch (e) {
      debugPrint('Change password error: $e');
      return {'success': false, 'message': 'Lỗi đổi mật khẩu: ${e.toString()}'};
    }
  }
}
