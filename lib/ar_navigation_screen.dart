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


class ARNavigationScreen extends StatefulWidget {
  const ARNavigationScreen({super.key});

  @override
  State<ARNavigationScreen> createState() => _ARNavigationScreenState();
}

class _ARNavigationScreenState extends State<ARNavigationScreen> {
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
        top: size.height / 2 - 150,
        left: positionX,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              width: cardWidthEstimate,
              decoration: BoxDecoration(
                color: _isPointingToTarget
                    ? Colors.green.shade600.withOpacity(0.9)
                    : Colors.blue.shade800.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white38, width: 1),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _targetLocation.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Distance: ${_formatDistance(distance)}",
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  const Icon(
                    Icons.mosque, // Masjid icon for Qibla
                    color: Colors.white,
                    size: 30,
                  ),
                  if (_isPointingToTarget)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                        "Correct Direction",
                        style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: cardWidthEstimate,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Icon(
                    _isPointingToTarget ? Icons.check_circle : Icons.arrow_drop_up,
                    color: _isPointingToTarget ? Colors.greenAccent : Colors.white,
                    size: 50,
                  ),
                ),
              ),
            )
          ],
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