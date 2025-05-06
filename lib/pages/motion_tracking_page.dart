import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'workout_history_page.dart';

class MotionTrackingPage extends StatefulWidget {
  const MotionTrackingPage({Key? key}) : super(key: key);

  @override
  State<MotionTrackingPage> createState() => _MotionTrackingPageState();
}

class _MotionTrackingPageState extends State<MotionTrackingPage>
    with WidgetsBindingObserver {
  final User? user = FirebaseAuth.instance.currentUser;
  bool isTracking = false;
  String mode = "normal"; // normal, combine, triceps
  String currentStatus = "Ready to start";
  bool isConnecting = false;
  bool useVoiceCommands = false;

  // Camera variables
  List<CameraDescription>? cameras;
  CameraController? cameraController;
  bool isCameraInitialized = false;
  int selectedCameraIndex = 0;

  // Frame processing rate control
  int _frameCount = 0;
  static const int _processEveryNFrames =
      5; // Process every 5th frame to reduce load
  Timer? _frameProcessingTimer;

  // Counters
  Map<String, int> counters = {
    "left_hand": 0,
    "right_hand": 0,
    "combine": 0,
    "left_tricep": 0,
    "right_tricep": 0,
  };

  // Angles data from API
  Map<String, int> angles = {"left": 0, "right": 0};

  // Connection timers and controllers
  Timer? statusCheckTimer;
  StreamSubscription? counterUpdateStream;

  // Flask API URL - Update this with your actual URL
  final String apiUrl = "http://localhost:5050"; // Local Flask server

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize Firebase Emulator configuration if not already done
    FirebaseFirestore.instance.settings = const Settings(
      host: 'localhost:8080',
      sslEnabled: false,
      persistenceEnabled: false,
    );

    // Request camera permission and initialize camera
    _requestCameraPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      // Free up resources when app is inactive
      cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // Reinitialize camera when app is resumed
      _initCamera(selectedCameraIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    statusCheckTimer?.cancel();
    counterUpdateStream?.cancel();
    _frameProcessingTimer?.cancel();
    cameraController?.dispose();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      _initCameras();
    } else {
      setState(() {
        currentStatus = "Camera permission denied";
      });
    }
  }

  Future<void> _initCameras() async {
    try {
      cameras = await availableCameras();
      if (cameras != null && cameras!.isNotEmpty) {
        // Default to front camera for better tracking of exercise
        selectedCameraIndex = cameras!.indexWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
        );
        if (selectedCameraIndex < 0) selectedCameraIndex = 0;

        await _initCamera(selectedCameraIndex);
      } else {
        setState(() {
          currentStatus = "No cameras found";
        });
      }
    } catch (e) {
      setState(() {
        currentStatus = "Camera initialization error: $e";
      });
    }
  }

  Future<void> _initCamera(int index) async {
    if (cameras == null || cameras!.isEmpty) {
      return;
    }

    // Dispose previous controller if exists
    if (cameraController != null) {
      await cameraController!.dispose();
    }

    // Create new controller
    cameraController = CameraController(
      cameras![index],
      ResolutionPreset.medium, // Use medium resolution for better performance
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid
              ? ImageFormatGroup.yuv420
              : ImageFormatGroup.bgra8888,
    );

    try {
      await cameraController!.initialize();
      setState(() {
        isCameraInitialized = true;
      });
    } catch (e) {
      setState(() {
        isCameraInitialized = false;
        currentStatus = "Error initializing camera: $e";
      });
    }
  }

  void _toggleCamera() async {
    if (cameras == null || cameras!.length <= 1) return;

    selectedCameraIndex = (selectedCameraIndex + 1) % cameras!.length;
    await _initCamera(selectedCameraIndex);
  }

  // Process camera frame and send to backend
  Future<void> _processFrame() async {
    if (!isTracking ||
        cameraController == null ||
        !cameraController!.value.isInitialized) {
      return;
    }

    _frameCount++;
    if (_frameCount % _processEveryNFrames != 0) {
      return; // Only process every Nth frame
    }

    try {
      // Take a picture
      final XFile imageFile = await cameraController!.takePicture();
      final bytes = await imageFile.readAsBytes();
      final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      // Send to backend
      final response = await http.post(
        Uri.parse('$apiUrl/process_frame'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'image': base64Image}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          setState(() {
            counters = {
              "left_hand": data['counters']['left_hand'] ?? 0,
              "right_hand": data['counters']['right_hand'] ?? 0,
              "combine": data['counters']['combine'] ?? 0,
              "left_tricep": data['counters']['left_tricep'] ?? 0,
              "right_tricep": data['counters']['right_tricep'] ?? 0,
            };

            angles = {
              "left": data['angles']['left'] ?? 0,
              "right": data['angles']['right'] ?? 0,
            };

            // Update mode if it was changed server-side (e.g., by voice command)
            if (data['mode'] != mode) {
              mode = data['mode'];
              currentStatus = "Mode changed to $mode";
            }
          });
        }
      }
    } catch (e) {
      print("Error processing frame: $e");
    }
  }

  Future<void> startTracking() async {
    if (!isCameraInitialized) {
      setState(() {
        currentStatus = "Camera not initialized";
      });
      return;
    }

    setState(() {
      isConnecting = true;
      currentStatus = "Connecting to tracking system...";
    });

    try {
      // Reset counters
      counters = {
        "left_hand": 0,
        "right_hand": 0,
        "combine": 0,
        "left_tricep": 0,
        "right_tricep": 0,
      };

      // Start the tracking session
      final response = await http.post(
        Uri.parse('$apiUrl/start_tracking'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'uid': user?.uid,
          'mode': mode,
          'use_voice': useVoiceCommands,
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          isTracking = true;
          isConnecting = false;
          currentStatus = "Tracking started - $mode mode";
        });

        // Start frame processing timer
        _frameProcessingTimer = Timer.periodic(
          const Duration(milliseconds: 200), // Process frames at 5 FPS (200ms)
          (timer) async {
            await _processFrame();
          },
        );
      } else {
        setState(() {
          isConnecting = false;
          currentStatus = "Failed to connect: ${response.body}";
        });
      }
    } catch (e) {
      setState(() {
        isConnecting = false;
        currentStatus = "Connection error: $e";
      });
    }
  }

  Future<void> stopTracking() async {
    try {
      await http.post(
        Uri.parse('$apiUrl/stop_tracking'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'uid': user?.uid}),
      );

      setState(() {
        isTracking = false;
        currentStatus = "Tracking stopped";
      });

      _frameProcessingTimer?.cancel();
      _frameProcessingTimer = null;

      // Show workout summary
      _showWorkoutSummary();
    } catch (e) {
      setState(() {
        currentStatus = "Error stopping tracking: $e";
      });
    }
  }

  Future<void> changeMode(String newMode) async {
    if (isTracking) {
      try {
        final response = await http.post(
          Uri.parse('$apiUrl/change_mode'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'mode': newMode, 'uid': user?.uid}),
        );

        if (response.statusCode == 200) {
          setState(() {
            mode = newMode;
            currentStatus = "Changed to $newMode mode";
          });
        }
      } catch (e) {
        print("Error changing mode: $e");
      }
    } else {
      setState(() {
        mode = newMode;
      });
    }
  }

  void _showWorkoutSummary() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Workout Summary",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              // Display the counters based on the mode
              if (mode == "normal") ...[
                _buildSummaryItem(
                  "Left Arm Curls",
                  counters["left_hand"] ?? 0,
                  Colors.blue,
                ),
                _buildSummaryItem(
                  "Right Arm Curls",
                  counters["right_hand"] ?? 0,
                  Colors.green,
                ),
                _buildSummaryItem(
                  "Total Curls",
                  (counters["left_hand"] ?? 0) + (counters["right_hand"] ?? 0),
                  Colors.purple,
                ),
              ] else if (mode == "combine") ...[
                _buildSummaryItem(
                  "Combined Curls",
                  counters["combine"] ?? 0,
                  Colors.purple,
                ),
              ] else if (mode == "triceps") ...[
                _buildSummaryItem(
                  "Left Tricep Extensions",
                  counters["left_tricep"] ?? 0,
                  Colors.orange,
                ),
                _buildSummaryItem(
                  "Right Tricep Extensions",
                  counters["right_tricep"] ?? 0,
                  Colors.red,
                ),
                _buildSummaryItem(
                  "Total Extensions",
                  (counters["left_tricep"] ?? 0) +
                      (counters["right_tricep"] ?? 0),
                  Colors.deepOrange,
                ),
              ],

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),

              // Recent workouts heading
              const Text(
                "Recent Workouts",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // Recent workouts from Firestore
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('usersData')
                          .doc(user?.uid)
                          .collection('workouts')
                          .orderBy('start_time', descending: true)
                          .limit(5)
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text('No workout history yet.'),
                      );
                    }

                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final workout =
                            snapshot.data!.docs[index].data()
                                as Map<String, dynamic>;
                        final timestamp = workout['start_time'] as Timestamp?;
                        final String dateStr =
                            timestamp != null
                                ? "${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}"
                                : "No date";

                        final stats =
                            workout['stats'] as Map<String, dynamic>? ?? {};
                        final int totalCount =
                            (stats['left_count'] ?? 0) +
                            (stats['right_count'] ?? 0) +
                            (stats['combined_count'] ?? 0) +
                            (stats['left_tricep_count'] ?? 0) +
                            (stats['right_tricep_count'] ?? 0);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              workout['mode'] == 'triceps'
                                  ? 'Tricep Workout'
                                  : 'Bicep Workout',
                            ),
                            subtitle: Text('$dateStr • $totalCount reps'),
                            trailing: Icon(
                              workout['mode'] == 'triceps'
                                  ? Icons.fitness_center
                                  : Icons.directions_run,
                              color: Colors.orange,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                // Back button and title
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        "Motion Tracking",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios),
                      onPressed: isCameraInitialized ? _toggleCamera : null,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Camera Preview
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        // Camera preview
                        if (isCameraInitialized)
                          Center(child: CameraPreview(cameraController!))
                        else
                          const Center(child: Text("Initializing camera...")),

                        // Angle indicators (overlay on camera)
                        if (isTracking && isCameraInitialized)
                          Positioned(
                            bottom: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Left: ${angles["left"]}°",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "Right: ${angles["right"]}°",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Status indicators
                        if (isTracking)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.fiber_manual_record,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    "LIVE",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Status display
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color:
                        isTracking
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isTracking ? Icons.check_circle : Icons.info_outline,
                        color: isTracking ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          currentStatus,
                          style: TextStyle(
                            color: isTracking ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isConnecting)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Counters section
                if (isTracking) ...[
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Current Counts",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Show different counters based on mode
                        if (mode == "normal") ...[
                          _buildCounterRow(
                            "Left Arm",
                            counters["left_hand"] ?? 0,
                            Icons.fitness_center,
                          ),
                          _buildCounterRow(
                            "Right Arm",
                            counters["right_hand"] ?? 0,
                            Icons.fitness_center,
                          ),
                        ] else if (mode == "combine") ...[
                          _buildCounterRow(
                            "Combined",
                            counters["combine"] ?? 0,
                            Icons.sync,
                          ),
                        ] else if (mode == "triceps") ...[
                          _buildCounterRow(
                            "Left Tricep",
                            counters["left_tricep"] ?? 0,
                            Icons.fitness_center,
                          ),
                          _buildCounterRow(
                            "Right Tricep",
                            counters["right_tricep"] ?? 0,
                            Icons.fitness_center,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Mode selection
                const Text(
                  "Exercise Mode",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildModeButton(
                        "Normal",
                        Icons.accessibility_new,
                        mode == "normal",
                        () => changeMode("normal"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildModeButton(
                        "Combined",
                        Icons.sync,
                        mode == "combine",
                        () => changeMode("combine"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildModeButton(
                        "Triceps",
                        Icons.fitness_center,
                        mode == "triceps",
                        () => changeMode("triceps"),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Voice command toggle
                SwitchListTile(
                  title: const Text(
                    "Voice Commands",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text(
                    "Enable voice recognition for hands-free control",
                  ),
                  value: useVoiceCommands,
                  activeColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  ),
                  onChanged:
                      !isTracking
                          ? (value) {
                            setState(() {
                              useVoiceCommands = value;
                            });
                          }
                          : null,
                ),

                const SizedBox(height: 20),

                // Start/Stop button
                ElevatedButton(
                  onPressed:
                      isConnecting || !isCameraInitialized
                          ? null
                          : (isTracking ? stopTracking : startTracking),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isTracking ? Colors.red : Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isTracking ? "STOP TRACKING" : "START TRACKING",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Workout history button
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WorkoutHistoryPage(),
                      ),
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        "View Workout History",
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCounterRow(String label, int count, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.orange),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: !isTracking ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey.withOpacity(0.3),
          ),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.2),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ]
                  : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey,
              size: 24,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
