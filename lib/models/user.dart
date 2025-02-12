class User{

  final String id;
  final String userName;
  final String lowerCaseUserName;
  final String friendCode;
  final String email;
  final String token;
  final List<String> friendIds;
  final List<String> incomingFriendRequests;
  final List<String> outgoingFriendRequests;

  User({
    required this.id,
    required this.userName,
    required this.lowerCaseUserName,
    required this.friendCode,
    required this.email,
    required this.token,
    this.friendIds = const [],
    this.incomingFriendRequests = const [],
    this.outgoingFriendRequests = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userName': userName,
      'lowerCaseUserName': lowerCaseUserName,
      'friendCode': friendCode,
      'email': email,
      'token': token,
      'friendIds': friendIds,
      'incomingFriendRequests': incomingFriendRequests,
      'outgoingFriendRequests': outgoingFriendRequests,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] ?? '',
      userName: map['userName'] ?? '',
      lowerCaseUserName: map['lowerCaseUserName'],
      friendCode: map['friendCode'] ?? '',
      email: map['email'] ?? '',
      token: map['token'] ?? '',
      friendIds: List<String>.from(map['friendIds'] ?? []),
      incomingFriendRequests: List<String>.from(map['incomingFriendRequests'] ?? []),
      outgoingFriendRequests: List<String>.from(map['outgoingFriendRequests'] ?? []),
    );
  }
}