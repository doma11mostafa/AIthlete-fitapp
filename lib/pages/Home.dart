import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aithelete/firestore-upload.dart';
import '../pages/login_screen.dart';
import '../pages/chatbot.dart';
import '../pages/workout_history_page.dart';
import '../pages/motion_tracking_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final User? user = FirebaseAuth.instance.currentUser;
  bool _isRailOpen = false;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeMockData();
  }

  Future<void> _initializeMockData() async {
    final doc =
        await FirebaseFirestore.instance
            .collection('usersData')
            .doc(user?.uid)
            .get();

    if (!doc.exists) {
      uploadMockData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomeContent(),
      const ChatbotPage(),
      const MotionTrackingPage(),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          /// ✅ معالجة الخطأ هنا
          Positioned.fill(
            child: pages[_selectedIndex.clamp(0, pages.length - 1)],
          ),

          /// Rail Overlay
          if (_isRailOpen)
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: 220,
              child: Container(
                color: Colors.black.withOpacity(0.0),
                child: Row(
                  children: [
                    Material(
                      elevation: 8,
                      color: Colors.white,
                      child: SizedBox(
                        width: 200,
                        child: Column(
                          children: [
                            const SizedBox(height: 100),
                            ListTile(
                              leading: const Icon(Icons.logout),
                              title: const Text('Logout'),
                              onTap: () => _showLogoutDialog(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          /// Toggle Button
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: Icon(_isRailOpen ? Icons.close : Icons.menu),
              onPressed: () {
                setState(() {
                  _isRailOpen = !_isRailOpen;
                });
              },
            ),
          ),
        ],
      ),

      /// Bottom Navigation
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chatbot'),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_run),
            label: 'Motion Tracking',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    String? userName = user?.displayName ?? 'User';
    String? userPhoto = user?.photoURL;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Welcome Header
            Row(
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Text(
                    'Welcome, $userName',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                CircleAvatar(
                  radius: 24,
                  backgroundImage:
                      userPhoto != null
                          ? NetworkImage(userPhoto)
                          : const AssetImage('lib/assets/AIThlete.png')
                              as ImageProvider,
                ),
              ],
            ),
            const SizedBox(height: 40),

            /// Real Data from Firestore
            StreamBuilder<DocumentSnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('usersData')
                      .doc(user?.uid)
                      .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data!.data() as Map<String, dynamic>;

                final sleep = data['sleep'] ?? {};
                final steps = data['steps'] ?? {};
                final heart = data['heartRate'] ?? {};
                final calories = data['calories'] ?? {};

                return Column(
                  children: [
                    DashboardCard(
                      iconPath: 'lib/assets/sleeptime.png',
                      title: '${sleep['hours'] ?? '--'} h',
                      subtitle: 'Sleep Duration',
                      info: '${sleep['qualityScore'] ?? '--'} Sleep Quality',
                      backgroundColor: Colors.purple.shade50,
                    ),
                    DashboardCard(
                      iconPath: 'lib/assets/steps.png',
                      title: '${steps['count'] ?? '--'} Steps',
                      subtitle: "Today's Walk",
                      info: '${steps['percent'] ?? '--'} Activity',
                      backgroundColor: Colors.green.shade50,
                    ),
                    DashboardCard(
                      iconPath: 'lib/assets/heart-tracking.png',
                      title: '${heart['bpm'] ?? '--'} bpm',
                      subtitle: 'Heart Rate',
                      info: 'Resting Average',
                      backgroundColor: Colors.red.shade50,
                    ),
                    DashboardCard(
                      iconPath: 'lib/assets/calories-1.png',
                      title: '${calories['burned'] ?? '--'} kcal',
                      subtitle: 'Calories Burned',
                      info: "Today's Total",
                      backgroundColor: Colors.orange.shade50,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Confirm Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (ctx) => const LoginScreen()),
                    (route) => false,
                  );
                },
                child: const Text('Yes'),
              ),
            ],
          ),
    );
  }
}

class DashboardCard extends StatelessWidget {
  final String iconPath;
  final String title;
  final String subtitle;
  final String info;
  final Color backgroundColor;

  const DashboardCard({
    super.key,
    required this.iconPath,
    required this.title,
    required this.subtitle,
    required this.info,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Image.asset(iconPath, width: 40),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Text(
                info,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
