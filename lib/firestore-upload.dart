import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void uploadMockData() async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    print("No user signed in");
    return;
  }

  final mockData = {
    "username": user.displayName ?? "Unknown",
    "sleep": {"hours": 7.5, "qualityScore": "80/100"},
    "steps": {"count": 3567, "percent": "13%"},
    "heartRate": {"bpm": 80, "note": "Resting"},
    "calories": {"burned": 560},
  };

  await FirebaseFirestore.instance
      .collection('usersData')
      .doc(user.uid)
      .set(mockData);

  print("✅ Mock data uploaded successfully for ${user.uid}");
}
