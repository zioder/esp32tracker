import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vibration/vibration.dart';
import 'dart:math';

class LocateTagScreen extends StatefulWidget {
  final BluetoothDevice device;
  final int rssiThreshold;

  const LocateTagScreen({
    super.key,
    required this.device,
    required this.rssiThreshold,
  });

  @override
  _LocateTagScreenState createState() => _LocateTagScreenState();
}

class _LocateTagScreenState extends State<LocateTagScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double? _distance;
  bool _isMonitoring = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween(begin: 0.5, end: 1.0).animate(_controller);
    _startRssiMonitoring();
  }

  void _startRssiMonitoring() async {
    while (_isMonitoring) {
      int? rssi = await widget.device.readRssi();
      if (mounted) {
        setState(() {
          _distance = _calculateDistance(rssi ?? 0);
        });
        _updateAnimation();
        _triggerVibration();
      }
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _updateAnimation() {
    if (_distance == null) return;
    double maxDistance = 10.0;
    double adjustedDistance = _distance!.clamp(0.7, maxDistance);
    double durationMs = 300 + (1700 * (adjustedDistance - 0.7) / (maxDistance - 0.7));
    _controller.stop();
    _controller.duration = Duration(milliseconds: durationMs.round());
    _controller.repeat(reverse: true);
  }
  double _calculateDistance(int rssi) {
    // Using the log-distance path loss model
    // Measured power (txPower) is the RSSI at 1 meter distance (default: -59 dBm)
    const int txPower = -59;
    const double n = 2.0; // Path loss exponent (2.0 to 4.0)
    
    if (rssi == 0) return 10.0;
    
    double ratio = (txPower - rssi) / (10 * n);
    return pow(10, ratio).toDouble();
  }

  void _triggerVibration() async {
    if (_distance == null) return;
    bool canControlAmplitude = await Vibration.hasAmplitudeControl();
    if (_distance! <= 0.7) {
      if (canControlAmplitude) {
        Vibration.vibrate(amplitude: 255);
      } else {
        Vibration.vibrate(duration: 500);
      }
    } else {
      double intensity = (1 - (_distance! / 10)).clamp(0.0, 1.0);
      int amplitude = (255 * intensity).toInt();
      if (canControlAmplitude) {
        Vibration.vibrate(duration: 100, amplitude: amplitude);
      } else {
        Vibration.vibrate(duration: 100);
      }
    }
  }

  @override
  void dispose() {
    _isMonitoring = false;
    _controller.dispose();
    Vibration.cancel();
    super.dispose();
  }

  Color get _circleColor {
    if (_distance == null) return Colors.blue;
    if (_distance! <= 0.7) return Colors.green;
    if (_distance! <= 2.0) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Locate Tag')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Opacity(
                  opacity: _animation.value,
                  child: Container(
                    width: 200 * _animation.value,
                    height: 200 * _animation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _circleColor.withOpacity(0.5),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            if (_distance != null && _distance! <= 0.7)
              const Text(
                'The tag is right there!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            Text(
              _distance != null ? '${_distance!.toStringAsFixed(2)} meters' : 'Measuring...',
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}