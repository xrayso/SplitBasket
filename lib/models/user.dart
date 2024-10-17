class User{

  final String id;
  final String userName;
  final String email;
  final List<String> friendIds;
  final List<String> incomingFriendRequests;
  final List<String> outgoingFriendRequests;

  User({
    required this.id,
    required this.userName,
    required this.email,
    this.friendIds = const [],
    this.incomingFriendRequests = const [],
    this.outgoingFriendRequests = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userName': userName,
      'email': email,
      'friendIds': friendIds,
      'incomingFriendRequests': incomingFriendRequests,
      'outgoingFriendRequests': outgoingFriendRequests,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] ?? '',
      userName: map['userName'] ?? '',
      email: map['email'] ?? '',
      friendIds: List<String>.from(map['friendIds'] ?? []),
      incomingFriendRequests: List<String>.from(map['incomingFriendRequests'] ?? []),
      outgoingFriendRequests: List<String>.from(map['outgoingFriendRequests'] ?? []),
    );
  }
}