import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:math';

import 'package:tag3/locatetagscreen.dart';
import 'package:tag3/rename_tag_bottom_sheet.dart';
import 'package:tag3/tag_storage.dart';


double _calculateDistance(int rssi) {
  // Using the formula: distance = 10 ^ ((txPower - rssi) / (10 * n))
  // Here we assume txPower = -59 and the path-loss exponent n = 2
  return pow(10, ((-59 - rssi) / (10 * 2))).toDouble();
}


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the local notifications plugin
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Tracker',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DeviceListScreen(),
    );
  }
}

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  _DeviceListScreenState createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  final FlutterBluePlus flutterBlue = FlutterBluePlus();
  final List<BluetoothDevice> devicesList = [];
  final String serviceUuid = "12345678-1234-1234-1234-1234567890ab";
  final String characteristicUuid = "abcd1234-ab12-cd34-ef56-1234567890ab";
  final int rssiThreshold = -90;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    // Listen to scan results and add devices that match a certain name (or criteria)
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        // For example, filtering devices by name "ESP32_Tag"
        if (!devicesList.contains(result.device) &&
            result.device.name == "ESP32_Tag") {
          setState(() => devicesList.add(result.device));
        }
      }
    });
    FlutterBluePlus.startScan();
  }

  void _connectToDevice(BluetoothDevice device) async {
    await device.connect();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceScreen(device: device, rssiThreshold: rssiThreshold),
      ),
    );
  }

  Future<void> _navigateToAddDevice() async {
    // Navigate to AddTagScreen and wait for the selected device.
    final BluetoothDevice? newDevice = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddTagScreen()),
    );
    if (newDevice != null && !devicesList.contains(newDevice)) {
      setState(() {
        devicesList.add(newDevice);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: TagStorage.getSavedTags(),
      builder: (context, snapshot) {
        final savedTags = snapshot.data ?? {};
        final savedDeviceIds = savedTags.keys.toList();
        final scannedDeviceIds = devicesList.map((d) => d.id.toString()).toList();
        final missingDevices = savedDeviceIds.where((id) => !scannedDeviceIds.contains(id)).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('BLE Trackers'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _navigateToAddDevice,
              )
            ],
          ),
          body: ListView(
            children: [
              if (devicesList.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("Available Devices"),
                ),
                ...devicesList.map((device) {
                  final displayName = savedTags[device.id.toString()] ?? device.name;
                  return ListTile(
                    title: Text(displayName.isNotEmpty ? displayName : 'Unknown Device'),
                    subtitle: Text(device.id.toString()),
                    onTap: () => _connectToDevice(device),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        await showRenameTagBottomSheet(
                          context,
                          device.id.toString(),
                          currentName: savedTags[device.id.toString()],
                        );
                        setState(() {});
                      },
                    ),
                  );
                }).toList(),
              ],
              if (missingDevices.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("Saved Devices"),
                ),
                ...missingDevices.map((id) {
                  return ListTile(
                    title: Text(savedTags[id]!, style: const TextStyle(color: Colors.grey)),
                    subtitle: Text(id, style: const TextStyle(color: Colors.grey)),
                    onTap: () {},
                  );
                }).toList(),
              ],
            ],
          ),
        );
      },
    );
  }
}

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;
  final int rssiThreshold;

  const DeviceScreen({super.key, required this.device, this.rssiThreshold = -70});

  @override
  _DeviceScreenState createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  BluetoothCharacteristic? buzzerCharacteristic;
  int? rssiValue;
  bool isConnected = true;
  bool isMonitoring = true;
  bool _isThresholdNotificationSent = false; // Flag to track if the notification has been sent

  @override
  void initState() {
    super.initState();
    _setupDevice();
    _startRssiMonitoring();
  }

  void _setupDevice() async {
    widget.device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && mounted) {
        setState(() => isConnected = false);
        _showNotification('Connection Lost', 'You have lost connection to the device.');
      }
    });

    List<BluetoothService> services = await widget.device.discoverServices();
    for (var service in services) {
      if (service.uuid.toString() == "12345678-1234-1234-1234-1234567890ab") {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() ==
              "abcd1234-ab12-cd34-ef56-1234567890ab") {
            buzzerCharacteristic = characteristic;
          }
        }
      }
    }
  }

  void _startRssiMonitoring() async {
    while (isMonitoring) {
      if (isConnected) {
        int? rssi = await widget.device.readRssi();
        if (mounted) setState(() => rssiValue = rssi);

        if (rssi != null) {
          if (rssi < widget.rssiThreshold && !_isThresholdNotificationSent) {
            _showNotification('Low Signal', 'The device is under the RSSI threshold.');
            _isThresholdNotificationSent = true; // Mark notification as sent
          } else if (rssi >= widget.rssiThreshold && _isThresholdNotificationSent) {
            _isThresholdNotificationSent = false; // Reset the flag when RSSI goes above the threshold
          }
        }
      }
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _activateBuzzer() async {
    if (buzzerCharacteristic != null) {
      await buzzerCharacteristic!.write("BUZZER_ON".codeUnits);
    }
  }

  void _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'your_channel_id',
      'your_channel_name',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  @override
  void dispose() {
    isMonitoring = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.name)),
      body: Column(
        children: [
          
          ListTile(
            title: const Text('Connection Status'),
            trailing: Chip(
              label: Text(isConnected ? 'Connected' : 'Disconnected'),
              backgroundColor: isConnected ? Colors.green : Colors.red,
            ),
          ),
          ListTile(
            title: const Text('Signal Strength'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.signal_cellular_alt,
                    color: _getSignalColor(rssiValue ?? -100)),
                const SizedBox(width: 10),
                Text('${rssiValue ?? 'N/A'} dBm'),
              ],
            ),
          ),
           ListTile(
      title: const Text('Estimated Distance'),
      trailing: Text(
        rssiValue != null
            ? '${_calculateDistance(rssiValue!).toStringAsFixed(2)} m'
            : 'N/A',
      ),
    ),
          
          ElevatedButton(
            onPressed: _activateBuzzer,
            child: const Text('Activate Buzzer'),
          ),
          ElevatedButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocateTagScreen(
          device: widget.device,
          rssiThreshold: widget.rssiThreshold,
        ),
      ),
    );
  },
  child: const Text('Locate Tag'),
),
          const SizedBox(height: 20),
   
        ],
      ),
    );
  }

  Color _getSignalColor(int rssi) {
    if (rssi > -60) return Colors.green;
    if (rssi > -70) return Colors.orange;
    return Colors.red;
  }
}

class AddTagScreen extends StatefulWidget {
  const AddTagScreen({super.key});

  @override
  _AddTagScreenState createState() => _AddTagScreenState();
}

class _AddTagScreenState extends State<AddTagScreen> {
  final FlutterBluePlus flutterBlue = FlutterBluePlus();
  final List<ScanResult> scanResults = [];
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() async {
    setState(() {
      isScanning = true;
    });
    // Clear any previous results.
    scanResults.clear();

    // Listen to scan results and add unique entries.
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (!scanResults.any((r) => r.device.id == result.device.id)) {
          setState(() {
            scanResults.add(result);
          });
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    setState(() {
      isScanning = false;
    });
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  void _selectDevice(BluetoothDevice device) {
    // Return the selected device back to the DeviceListScreen.
    Navigator.pop(context, device);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Tag'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _startScan,
          )
        ],
      ),
      body: isScanning
          ? const Center(child: CircularProgressIndicator())
          : scanResults.isEmpty
              ? const Center(child: Text('No devices found.'))
              : ListView.builder(
                  itemCount: scanResults.length,
                  itemBuilder: (context, index) {
                    final result = scanResults[index];
                    return ListTile(
                      title: Text(result.device.name.isNotEmpty
                          ? result.device.name
                          : 'Unknown Device'),
                      subtitle: Text(result.device.id.toString()),
                      onTap: () => _selectDevice(result.device),
                    );
                  },
                ),
    );
  }
}