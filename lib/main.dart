import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

int _notificationId = 0;

Future<void> _initNotifications() async {
  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  const settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await _notificationsPlugin.initialize(settings);
  await _notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

Future<String?> _downloadImage(String url, int id) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;
    final dir = await getTemporaryDirectory();
    final ext = url.split('.').last.split('?').first.toLowerCase();
    final validExt =
        ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext) ? ext : 'jpg';
    final file = File('${dir.path}/notiplus_$id.$validExt');
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<void> _showNotification(
  String title,
  String body, {
  String? imageUrl,
}) async {
  final id = _notificationId++;
  final imagePath = imageUrl != null && imageUrl.isNotEmpty
      ? await _downloadImage(imageUrl, id)
      : null;

  final AndroidNotificationDetails androidDetails;
  if (imagePath != null) {
    final bigPicture = BigPictureStyleInformation(
      FilePathAndroidBitmap(imagePath),
      largeIcon: FilePathAndroidBitmap(imagePath),
      contentTitle: title,
      summaryText: body,
    );
    androidDetails = AndroidNotificationDetails(
      'notiplus_channel',
      'NotiPlus',
      channelDescription: 'NotiPlus push notifications',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: bigPicture,
    );
  } else {
    androidDetails = const AndroidNotificationDetails(
      'notiplus_channel',
      'NotiPlus',
      channelDescription: 'NotiPlus push notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
  }

  final DarwinNotificationDetails iosDetails;
  if (imagePath != null) {
    iosDetails = DarwinNotificationDetails(
      attachments: [DarwinNotificationAttachment(imagePath)],
    );
  } else {
    iosDetails = const DarwinNotificationDetails();
  }

  await _notificationsPlugin.show(
    id,
    title,
    body,
    NotificationDetails(android: androidDetails, iOS: iosDetails),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NotiPlus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class ReceivedNotification {
  final String title;
  final String body;
  final String? imageUrl;
  final DateTime time;

  ReceivedNotification({
    required this.title,
    required this.body,
    this.imageUrl,
    required this.time,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _wsUrl =
      'wss://notiplus-api.k-kittanai46.workers.dev/ws';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  final List<ReceivedNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    if (_isConnected) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      setState(() => _isConnected = true);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    setState(() => _isConnected = false);
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _connect();
    });
  }

  void _onMessage(dynamic data) {
    try {
      final Map<String, dynamic> json = jsonDecode(data as String);
      final title = json['title'] as String? ?? 'NotiPlus';
      final body = json['body'] as String? ?? '';
      final imageUrl = json['imageUrl'] as String?;

      _showNotification(title, body, imageUrl: imageUrl);

      setState(() {
        _notifications.insert(
          0,
          ReceivedNotification(
            title: title,
            body: body,
            imageUrl: imageUrl,
            time: DateTime.now(),
          ),
        );
      });
    } catch (_) {}
  }

  void _onError(Object error) {
    setState(() => _isConnected = false);
    _scheduleReconnect();
  }

  void _onDone() {
    setState(() => _isConnected = false);
    _scheduleReconnect();
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NotiPlus'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _isConnected ? Icons.wifi : Icons.wifi_off,
              color: _isConnected ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          const Divider(height: 1),
          Expanded(child: _buildNotificationList()),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _isConnected ? Colors.green[50] : Colors.grey[100],
      child: Row(
        children: [
          Icon(
            _isConnected ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: _isConnected ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            _isConnected ? 'Connected — receiving notifications' : 'Connecting...',
            style: TextStyle(
              fontSize: 13,
              color: _isConnected ? Colors.green[700] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList() {
    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No notifications yet',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final n = _notifications[index];
        return ListTile(
          leading: n.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    n.imageUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const CircleAvatar(
                      child: Icon(Icons.broken_image),
                    ),
                  ),
                )
              : CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: const Icon(Icons.notifications),
                ),
          title: Text(n.title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(n.body),
          trailing: Text(
            _formatTime(n.time),
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_scanned) return;
          final barcode = capture.barcodes.firstOrNull;
          final value = barcode?.rawValue;
          if (value != null && value.startsWith('wss://')) {
            _scanned = true;
            Navigator.pop(context, value);
          }
        },
      ),
    );
  }
}
