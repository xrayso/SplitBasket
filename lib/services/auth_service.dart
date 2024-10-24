import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import '../models/user.dart' as user_dart;
import 'dart:math';


class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final DatabaseService _dbService = DatabaseService();
  // Sign in with email and password


  Future<String> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return "Success";
    }catch (e){
      return cleanErrorMessage(e.toString());
    }
  }
  Future<String> _generateFriendCode(String username) async {
    const int codeLength = 4;
    String code = "";
    bool exists = true;

    while (exists) {
      code = Random().nextInt(9999).toString().padLeft(codeLength, '0');
      final result = await _db
          .collection('users')
          .where('userName', isEqualTo: username)
          .where('friendCode', isEqualTo: code)
          .get();
      exists = result.docs.isNotEmpty;
    }
    return code;
  }
  Future<String> register(String email, String password, String userName) async {
    RegExp validUsername = RegExp(r'^[a-zA-Z0-9._-]+$');
    if (!validUsername.hasMatch(userName)) return " Username cannot contain special characters or spaces";
    try {
      // Create the user in Firebase Authentication
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Get the created Firebase user
      String friendCode = await _generateFriendCode(userName);
      User firebaseUser = userCredential.user!;

      // Update the custom user object with the correct Firebase uid
      user_dart.User user = user_dart.User(
        id: firebaseUser.uid,
        email: email,
        userName: userName,
        lowerCaseUserName: userName.toLowerCase(),
        friendCode: friendCode,
      );

      // Set user in Firestore
      await _dbService.setUser(user);
      return "Success";
    } catch (e) {
      return cleanErrorMessage(e.toString());
    }
  }
  String cleanErrorMessage(String errorMessage) {
    // Find the index of the closing bracket ']'
    int bracketIndex = errorMessage.indexOf(']');

    // Find the index of the first letter after the space after ']'
    int firstLetterIndex = errorMessage.indexOf(RegExp(r'[a-zA-Z]'), bracketIndex + 2);

    // Return the cleaned error message
    return firstLetterIndex != -1 ? errorMessage.substring(firstLetterIndex) : errorMessage;
  }

  // Sign out
  Future<void> signOut() {
    return _auth.signOut();
  }

  // Get current user
  User? get currentUser => _auth.currentUser;
}
