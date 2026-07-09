import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// The GATT contract exposed by the BabyLink ESP32-S3 firmware.
/// Must match esp32-s3-firmware-idf/main/main.cpp (BLE_* UUIDs).
class BabyLinkUuids {
  static final service = Guid('bab71111-0002-1000-8000-00805f9b34fb');
  static final config = Guid('bab71111-0002-1001-8000-00805f9b34fb'); // R/W JSON config
  static final scan = Guid('bab71111-0002-1002-8000-00805f9b34fb'); // W "scan" -> R list
  static final command = Guid('bab71111-0002-1003-8000-00805f9b34fb'); // W "apply"/"wifi-reset"
  static final info = Guid('bab71111-0002-1004-8000-00805f9b34fb'); // R/Notify device info
  static const namePrefix = 'BabyLink';
}

/// What the INFO characteristic tells us about a device.
class DeviceInfo {
  final String model;
  final String fw;
  final String mac;
  final bool configured; // already has a server/room
  final bool provOpen; // provisioning window currently open
  final Map<String, dynamic> raw;

  DeviceInfo({
    required this.model,
    required this.fw,
    required this.mac,
    required this.configured,
    required this.provOpen,
    required this.raw,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        model: (j['model'] ?? '').toString(),
        fw: (j['fw'] ?? '').toString(),
        mac: (j['mac'] ?? '').toString(),
        configured: j['configured'] == true,
        provOpen: j['provOpen'] == true,
        raw: j,
      );
}

/// One WiFi network the device found nearby.
class WifiNetwork {
  final String ssid;
  final int rssi;
  final bool secure;
  WifiNetwork({required this.ssid, required this.rssi, required this.secure});

  factory WifiNetwork.fromJson(Map<String, dynamic> j) => WifiNetwork(
        ssid: (j['ssid'] ?? '').toString(),
        rssi: (j['rssi'] is num) ? (j['rssi'] as num).toInt() : 0,
        secure: j['secure'] == true,
      );
}

/// Thin, UI-agnostic wrapper over flutter_blue_plus for the BabyLink flow.
class BabyLinkBle {
  BluetoothDevice? _device;
  final Map<Guid, BluetoothCharacteristic> _chars = {};

  BluetoothDevice? get device => _device;

  /// Ask for the BLE runtime permissions. On Android 12+ that's scan+connect;
  /// on older Android BLE scanning also needs location. iOS uses the Info.plist
  /// usage strings and grants at connect time.
  Future<bool> ensurePermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // only enforced on Android < 12
    ].request();
    // Treat "granted" or "limited"/"restricted-but-usable" as ok; location may
    // be permanently denied on Android 12+ where it isn't needed.
    final scanOk = results[Permission.bluetoothScan]?.isGranted ?? false;
    final connOk = results[Permission.bluetoothConnect]?.isGranted ?? false;
    return scanOk && connOk;
  }

  /// Is the phone's Bluetooth turned on?
  Future<bool> isBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState
        .firstWhere((s) => s != BluetoothAdapterState.unknown);
    return state == BluetoothAdapterState.on;
  }

  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;

  /// Scan for BabyLink devices (filtered to our service UUID). Emits the list
  /// of matching results as they're discovered. Stop with [stopScan].
  Stream<List<ScanResult>> scanForDevices(
      {Duration timeout = const Duration(seconds: 15)}) {
    FlutterBluePlus.startScan(
      withServices: [BabyLinkUuids.service],
      timeout: timeout,
    );
    return FlutterBluePlus.onScanResults.map((results) => results
        .where((r) =>
            r.device.platformName.startsWith(BabyLinkUuids.namePrefix) ||
            r.advertisementData.serviceUuids.contains(BabyLinkUuids.service))
        .toList());
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// Connect to a device and cache its characteristics.
  Future<void> connect(BluetoothDevice device,
      {Duration timeout = const Duration(seconds: 20)}) async {
    await stopScan();
    _device = device;
    _chars.clear();
    // flutter_blue_plus 2.x requires a license arg. License.nonprofit covers
    // personal / self-hosted use (commercial use needs their paid license).
    await device.connect(license: License.nonprofit, timeout: timeout, mtu: 512);
    final services = await device.discoverServices();
    for (final s in services) {
      if (s.uuid != BabyLinkUuids.service) continue;
      for (final c in s.characteristics) {
        _chars[c.uuid] = c;
      }
    }
    if (_chars[BabyLinkUuids.info] == null) {
      throw StateError('Not a BabyLink device (service/characteristics missing)');
    }
  }

  Future<void> disconnect() async {
    try {
      await _device?.disconnect();
    } finally {
      _device = null;
      _chars.clear();
    }
  }

  Stream<BluetoothConnectionState>? get connectionState =>
      _device?.connectionState;

  BluetoothCharacteristic _char(Guid id) {
    final c = _chars[id];
    if (c == null) throw StateError('Characteristic $id not available');
    return c;
  }

  Map<String, dynamic> _readJson(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty) return {};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  /// Read the INFO characteristic (model/mac/configured/provOpen).
  Future<DeviceInfo> readInfo() async {
    final bytes = await _char(BabyLinkUuids.info).read();
    return DeviceInfo.fromJson(_readJson(bytes));
  }

  /// Subscribe to INFO notifications — fires when the provisioning window opens
  /// (user taps the device button), so the wizard can auto-advance.
  Stream<DeviceInfo> watchInfo() async* {
    final c = _char(BabyLinkUuids.info);
    await c.setNotifyValue(true);
    yield* c.onValueReceived
        .map((b) => DeviceInfo.fromJson(_readJson(b)));
  }

  /// Read the current saved config JSON from the device.
  Future<Map<String, dynamic>> readConfig() async {
    return _readJson(await _char(BabyLinkUuids.config).read());
  }

  /// Ask the device to scan WiFi, then poll the SCAN characteristic until a
  /// non-empty list arrives (WiFi scan with BT coexist takes a few seconds).
  Future<List<WifiNetwork>> scanWifi(
      {Duration timeout = const Duration(seconds: 12)}) async {
    final c = _char(BabyLinkUuids.scan);
    await c.write(utf8.encode('scan'), withoutResponse: false);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 600));
      final raw = utf8.decode(await c.read(), allowMalformed: true).trim();
      if (raw.isNotEmpty && raw != '[]') {
        final list = jsonDecode(raw);
        if (list is List && list.isNotEmpty) {
          return list
              .whereType<Map<String, dynamic>>()
              .map(WifiNetwork.fromJson)
              .toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
        }
      }
    }
    return [];
  }

  /// Write a full config JSON to the device (staged, not yet persisted).
  Future<void> writeConfig(Map<String, dynamic> config) async {
    await _char(BabyLinkUuids.config)
        .write(utf8.encode(jsonEncode(config)), withoutResponse: false);
  }

  /// Persist the staged config and reboot ('apply'). The device drops the BLE
  /// link on reboot, so a disconnect here is expected (not an error).
  Future<void> apply() async {
    await _char(BabyLinkUuids.command)
        .write(utf8.encode('apply'), withoutResponse: false);
  }

  Future<void> factoryReset() async {
    await _char(BabyLinkUuids.command)
        .write(utf8.encode('wifi-reset'), withoutResponse: false);
  }
}
