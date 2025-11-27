import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';

// A placeholder class for target locations
class TargetLocation {
  final double latitude;
  final double longitude;
  final String name;

  const TargetLocation({
    required this.latitude,
    required this.longitude,
    required this.name,
  });
}

// Our target location (Qibla Al Kaaba)
const TargetLocation _targetLocation = TargetLocation(
  latitude: 21.422652678125257,
  longitude: 39.82618098932749,
  name: "(Qibla) Al Kaaba",
);


class ARQiblaScreen extends StatefulWidget {
  const ARQiblaScreen({super.key});

  @override
  State<ARQiblaScreen> createState() => _ARQiblaScreenState();
}

class _ARQiblaScreenState extends State<ARQiblaScreen> {
  // Camera Control Variables
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  // UX State variables
  String _statusMessage = "Starting...";
  bool _isPermissionDenied = false;

  // Sensor Data Variables
  double _currentHeading = 0.0; // Current North-relative heading of the phone
  Position? _currentPosition; // Current GPS Location

  // Calculated AR Variables
  double _targetBearing = 0.0; // Heading jo target location ki taraf jaati hai
  double _directionAngle = 0.0; // Screen par arrow ki position (kitna shift karna hai)
  bool _isPointingToTarget = false; // Check agar arrow center mein hai

  @override
  void initState() {
    super.initState();
    _initializeSensorsAndCamera();
  }

  // --- INITIALIZATION ---
  Future<void> _initializeSensorsAndCamera() async {
    setState(() => _statusMessage = "Checking permissions...");

    // 1. Permissions Check
    if (!await _checkPermissions()) {
      setState(() {
        _isPermissionDenied = true;
        _statusMessage = "Permissions not granted. Camera & Location access is must.";
      });
      return;
    }

    // 2. Camera Setup
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception("No camera is available.");
      }
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      setState(() => _statusMessage = "Camera is initializing...");
      await _cameraController!.initialize();

      // 3. Location Listener (for GPS)
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen((Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
            _calculateBearing();
          });
        }
      });

      // 4. Compass Listener (for Phone Heading)
      FlutterCompass.events?.listen((CompassEvent event) {
        if (mounted) {
          setState(() {
            _currentHeading = event.heading ?? 0.0;
            _calculateBearing();
          });
        }
      });

      setState(() {
        _isCameraInitialized = true;
        _statusMessage = "AR Ready. Try finding Qibla by turning around.";
      });

    } catch (e) {
      setState(() {
        _statusMessage = "Error: Camera didn't get initialize. ${e.toString()}";
      });
    }
  }

  // --- PERMISSION HANDLER ---
  Future<bool> _checkPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final locationStatus = await Permission.locationWhenInUse.request();

    if (cameraStatus.isGranted && locationStatus.isGranted) {
      return true;
    }

    if (cameraStatus.isPermanentlyDenied || locationStatus.isPermanentlyDenied) {
      openAppSettings();
    }

    return false;
  }

  // --- DISTANCE UTILITY ---
  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters >= 1000) {
      return "${(distanceInMeters / 1000).toStringAsFixed(0)} KM"; // Round off to nearest KM
    }
    return "${distanceInMeters.toStringAsFixed(0)} m";
  }

  // --- CORE AR MATH LOGIC ---
  void _calculateBearing() {
    if (_currentPosition == null) return;

    // 1. Target Bearing Calculation
    _targetBearing = Geolocator.bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _targetLocation.latitude,
      _targetLocation.longitude,
    );

    if (_targetBearing < 0) {
      _targetBearing += 360;
    }

    // 2. Relative Angle Calculation
    double rawAngle = _targetBearing - _currentHeading;

    // Angle ko -180 aur 180 ke beech mein normalize karein (ye screen ke center se kitna door hai)
    if (rawAngle > 180) {
      rawAngle -= 360;
    } else if (rawAngle < -180) {
      rawAngle += 360;
    }

    // 3. Final Angle Assignment
    _directionAngle = rawAngle;

    // 4. Pointing Check
    _isPointingToTarget = (rawAngle.abs() < 10);
  }

  // --- UTILITY WIDGETS ---
  Widget _buildDirectionIndicator(Size size) {
    double screenWidth = size.width;
    double sensitivityFactor = screenWidth / 90.0;

    if (_directionAngle.abs() > 45) {

      final bool turnRight = _directionAngle > 0;
      final String instructionText = turnRight ? "Turn Right" : "Turn Left";
      final String angleText = _directionAngle.abs().toStringAsFixed(0);

      double positionX = turnRight ? screenWidth - 120 : 20;

      return Positioned(
        top: size.height / 2 - 100,
        left: positionX,
        child: Container(
          width: 100,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.95),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                instructionText,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 5),
              Icon(
                turnRight ? Icons.arrow_right_rounded : Icons.arrow_left_rounded,
                color: Colors.white,
                size: 30,
              ),
              const SizedBox(height: 5),
              // Angle to Turn
              Text(
                "$angleText°",
                style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else {
      // --- ON-SCREEN TARGET INDICATOR (Blue/Green Card) ---

      // Calculate position relative to the center
      double positionX = (screenWidth / 2) + (_directionAngle * sensitivityFactor);

      double cardWidthEstimate = 200;
      positionX = positionX - (cardWidthEstimate / 2);

      // Ensure the card doesn't go off-screen
      positionX = positionX.clamp(10, screenWidth - cardWidthEstimate - 10);


      // Target information card
      double distance = Geolocator.distanceBetween(
          _currentPosition!.latitude, _currentPosition!.longitude,
          _targetLocation.latitude, _targetLocation.longitude
      );

      return Positioned(
        top: size.height / 2 - 180,
        left: positionX,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 600),
          builder: (context, value, child) {

            final bool facing = _isPointingToTarget;
            final double lineHeight = MediaQuery.of(context).size.height * 0.65;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSlide(
                  offset: Offset(0, facing ? 0 : 0.2),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 400),
                    opacity: value,
                    child: Container(
                      width: 180,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24, width: 1),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black38,
                              blurRadius: 10,
                              offset: Offset(0, 4))
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            _targetLocation.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Distance: ${_formatDistance(distance)}",
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),

                          const SizedBox(height: 12),

                          /// ✔ Message appears only when user is aligned
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: facing ? 1 : 0,
                            child: const Text(
                              "You are facing Qibla ✓",
                              style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                facing ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: facing ? 1.2 : 1),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, _) {
                    return Transform.scale(
                      scale: scale,
                      child: Image.asset(
                        'assets/qibla.png',
                        width: 50,
                        height: 50,
                      ),
                    );
                  },
                ) : SizedBox(),
                const SizedBox(height: 10),
                facing ? AnimatedContainer(
                  duration: const Duration(milliseconds: 1000),
                  width: 15,
                  height: lineHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: facing
                          ? [
                        Colors.greenAccent.withOpacity(0.9),
                        Colors.green.shade700
                      ]
                          : [
                        Colors.blueAccent.withOpacity(0.9),
                        Colors.blue.shade900
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: facing
                            ? Colors.greenAccent.withOpacity(0.8)
                            : Colors.blueAccent.withOpacity(0.6),
                        blurRadius: 12,
                        spreadRadius: facing ? 3 : 1,
                      )
                    ],
                  ),
                ) : SizedBox(),
              ],
            );
          },
        ),
      );

    }
  }

  // --- ERROR/LOADING WIDGET ---
  Widget _buildStatusOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isPermissionDenied)
                const CircularProgressIndicator(color: Colors.white)
              else
                const Icon(Icons.error_outline, color: Colors.red, size: 50),
              const SizedBox(height: 20),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              if (_isPermissionDenied)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: ElevatedButton(
                    onPressed: openAppSettings,
                    child: const Text("Open Settings"),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- DISPOSE ---
  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // --- BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    bool hasData = _currentPosition != null && _currentHeading != 0.0;

    if (!_isCameraInitialized || _isPermissionDenied) {
      return Scaffold(
        appBar: AppBar(title: const Text("AR Qibla Direction")),
        body: _buildStatusOverlay(),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("AR Qibla Compass"),
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // 1. Camera Live Feed (Background)
          SizedBox(
            width: size.width,
            height: size.height,
            child: CameraPreview(_cameraController!),
          ),

          // 2. AR Overlay (Direction Indicator)
          if (hasData)
            _buildDirectionIndicator(size),

          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Status: $_statusMessage", style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Text("Phone Heading (Aapka Rukh): ${_currentHeading.toStringAsFixed(1)}°", style: const TextStyle(color: Colors.white, fontSize: 14)),
                  Text("Target Bearing (Manzil): ${_targetBearing.toStringAsFixed(1)}°", style: const TextStyle(color: Colors.white, fontSize: 14)),
                  Text("Relative Angle (Shift): ${_directionAngle.toStringAsFixed(1)}°", style: const TextStyle(color: Colors.yellow, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}