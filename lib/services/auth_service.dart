import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import '../models/user.dart' as user_dart;

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseService _dbService = DatabaseService();
  // Sign in with email and password
  Future<UserCredential> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> register(String email, String password, String userName) async {
    try {
      // Create the user in Firebase Authentication
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Get the created Firebase user
      User firebaseUser = userCredential.user!;

      // Update the custom user object with the correct Firebase uid
      user_dart.User user = user_dart.User(
        id: firebaseUser.uid,
        email: email,
        userName: userName,
      );

      // Set user in Firestore
      await _dbService.setUser(user);

    } catch (e) {
      // Handle error
    }
  }


  // Sign out
  Future<void> signOut() {
    return _auth.signOut();
  }

  // Get current user
  User? get currentUser => _auth.currentUser;
}
