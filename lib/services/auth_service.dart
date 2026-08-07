import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class UserModel {
  UserModel({
    required this.id,
    required this.email,
    required this.passwordHash,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      email: json['email'] as String,
      passwordHash: json['passwordHash'] as String,
    );
  }

  final int id;
  final String email;
  final String passwordHash;

  Map<String, dynamic> toJson() {
    return {'id': id, 'email': email, 'passwordHash': passwordHash};
  }
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal();

  final List<UserModel> _users = [];
  int _nextId = 1;

  Future<String?> _readStoredPayload() async {
    if (kIsWeb) {
      return null;
    }

    final directory = Directory.current;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File('${directory.path}/users.json');
    if (!await file.exists()) {
      return null;
    }
    return await file.readAsString();
  }

  Future<void> _writeStoredPayload(String payload) async {
    if (kIsWeb) {
      return;
    }

    final directory = Directory.current;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File('${directory.path}/users.json');
    await file.writeAsString(payload);
  }

  Future<void> _loadUsers() async {
    if (_users.isNotEmpty) {
      return;
    }

    final contents = await _readStoredPayload();
    if (contents == null || contents.trim().isEmpty) {
      return;
    }

    final decoded = jsonDecode(contents) as List<dynamic>;
    _users.addAll(
      decoded
          .map((item) => UserModel.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
    _nextId =
        (_users
            .map((user) => user.id)
            .fold<int>(0, (value, id) => value > id ? value : id) +
        1);
  }

  Future<void> _saveUsers() async {
    final payload = jsonEncode(_users.map((user) => user.toJson()).toList());
    await _writeStoredPayload(payload);
  }

  Future<void> resetDatabaseForTesting() async {
    _users.clear();
    _nextId = 1;
    await _saveUsers();
  }

  Future<UserModel?> signUp(String email, String password) async {
    await _loadUsers();

    final normalizedEmail = email.toLowerCase().trim();
    if (_users.any((user) => user.email == normalizedEmail)) {
      return null;
    }

    final user = UserModel(
      id: _nextId++,
      email: normalizedEmail,
      passwordHash: _hashPassword(password),
    );

    _users.add(user);
    await _saveUsers();
    return user;
  }

  Future<UserModel?> signIn(String email, String password) async {
    await _loadUsers();

    final normalizedEmail = email.toLowerCase().trim();
    final user = _users.firstWhere(
      (candidate) => candidate.email == normalizedEmail,
      orElse: () => UserModel(id: -1, email: '', passwordHash: ''),
    );

    if (user.id == -1) {
      return null;
    }

    if (_hashPassword(password) != user.passwordHash) {
      return null;
    }

    return user;
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return base64Encode(bytes);
  }
}
