import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutHistoryPage extends StatelessWidget {
  const WorkoutHistoryPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Workout History"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('usersData')
                .doc(user?.uid)
                .collection('workouts')
                .orderBy('start_time', descending: true)
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fitness_center, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text(
                    "No workout history yet",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Complete your first workout to see it here",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final workout =
                  snapshot.data!.docs[index].data() as Map<String, dynamic>;
              final timestamp = workout['start_time'] as Timestamp?;
              final String dateStr =
                  timestamp != null
                      ? "${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}"
                      : "No date";

              final stats = workout['stats'] as Map<String, dynamic>? ?? {};

              // Calculate total reps based on workout mode
              int totalReps = 0;
              String repType = "";

              if (workout['mode'] == 'normal') {
                totalReps =
                    (stats['left_count'] ?? 0) + (stats['right_count'] ?? 0);
                repType = "Bicep Curls";
              } else if (workout['mode'] == 'combine') {
                totalReps = stats['combined_count'] ?? 0;
                repType = "Combined Curls";
              } else if (workout['mode'] == 'triceps') {
                totalReps =
                    (stats['left_tricep_count'] ?? 0) +
                    (stats['right_tricep_count'] ?? 0);
                repType = "Tricep Extensions";
              }

              final double duration = stats['duration'] ?? 0;
              final String durationStr =
                  duration > 0
                      ? "${(duration / 60).floor()} min ${(duration % 60).floor()} sec"
                      : "N/A";

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              workout['mode'] == 'triceps'
                                  ? Icons.fitness_center
                                  : Icons.accessibility_new,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  repType,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              workout['status'] ?? "completed",
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem("Total Reps", totalReps.toString()),
                          _buildStatItem("Duration", durationStr),
                          _buildStatItem("Mode", workout['mode'] ?? "normal"),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}
