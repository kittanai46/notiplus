import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ─── Notifications setup ─────────────────────────────────────────────────────

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();
int _notificationId = 0;

Future<void> _initNotifications() async {
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    ),
  );
  await _notificationsPlugin.initialize(settings);
  await _notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

Future<String?> _downloadImage(String url, int id) async {
  try {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) return null;
    final dir = await getTemporaryDirectory();
    final ext = url.split('.').last.split('?').first.toLowerCase();
    final validExt =
        ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext) ? ext : 'jpg';
    final file = File('${dir.path}/notiplus_$id.$validExt');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<void> _showLocalNotification(
  String title,
  String body, {
  String? imageUrl,
}) async {
  final id = _notificationId++;
  final imagePath = imageUrl != null && imageUrl.isNotEmpty
      ? await _downloadImage(imageUrl, id)
      : null;

  final androidDetails = imagePath != null
      ? AndroidNotificationDetails(
          'notiplus_channel', 'NotiPlus',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigPictureStyleInformation(
            FilePathAndroidBitmap(imagePath),
            largeIcon: FilePathAndroidBitmap(imagePath),
            contentTitle: title,
            summaryText: body,
          ),
        )
      : const AndroidNotificationDetails(
          'notiplus_channel', 'NotiPlus',
          importance: Importance.high,
          priority: Priority.high,
        );

  final iosDetails = imagePath != null
      ? DarwinNotificationDetails(
          attachments: [DarwinNotificationAttachment(imagePath)])
      : const DarwinNotificationDetails();

  await _notificationsPlugin.show(
    id, title, body,
    NotificationDetails(android: androidDetails, iOS: iosDetails),
  );
}

// ─── App entry ───────────────────────────────────────────────────────────────

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
      home: const MainScreen(),
    );
  }
}

// ─── Data model ──────────────────────────────────────────────────────────────

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

// ─── Main screen ─────────────────────────────────────────────────────────────

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const String _wsUrl =
      'wss://notiplus-api.k-kittanai46.workers.dev/ws';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  int _selectedIndex = 0;
  final List<ReceivedNotification> _notifications = [];
  int _unreadCount = 0;

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
        onError: (_) => _onDisconnect(),
        onDone: _onDisconnect,
        cancelOnError: false,
      );
      setState(() => _isConnected = true);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onDisconnect() {
    setState(() => _isConnected = false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _connect();
    });
  }

  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final title = json['title'] as String? ?? 'NotiPlus';
      final body = json['body'] as String? ?? '';
      final imageUrl = json['imageUrl'] as String?;

      _showLocalNotification(title, body, imageUrl: imageUrl);

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
        _unreadCount++;
      });
    } catch (_) {}
  }

  void _openNotifications() {
    setState(() => _unreadCount = 0);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => NotificationSheet(notifications: _notifications),
    );
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const HomeTab(),
      const ExploreTab(),
      const ProfileTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('NotiPlus'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: _openNotifications,
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outlined),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ─── Tabs (Skeleton) ─────────────────────────────────────────────────────────

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stories row
        SizedBox(
          height: 82,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 6,
            itemBuilder: (_, __) => Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.grey[200],
                ),
                const SizedBox(height: 4),
                Container(
                    width: 44,
                    height: 8,
                    decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4))),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...List.generate(4, (_) => _PostCard()),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 18, backgroundColor: Colors.grey[200]),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 120,
                  height: 10,
                  decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 5),
              Container(
                  width: 80,
                  height: 8,
                  decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4))),
            ]),
          ]),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 12),
          Container(
              width: double.infinity,
              height: 10,
              decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          Container(
              width: 180,
              height: 10,
              decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4))),
        ]),
      ),
    );
  }
}

class ExploreTab extends StatelessWidget {
  const ExploreTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: 8,
            itemBuilder: (_, __) => Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: Column(children: [
            CircleAvatar(radius: 44, backgroundColor: Colors.grey[200]),
            const SizedBox(height: 12),
            Container(
                width: 140,
                height: 14,
                decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            Container(
                width: 100,
                height: 10,
                decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4))),
          ]),
        ),
        const SizedBox(height: 32),
        ...List.generate(
          5,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 52,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Notification Sheet ───────────────────────────────────────────────────────

class NotificationSheet extends StatelessWidget {
  final List<ReceivedNotification> notifications;

  const NotificationSheet({super.key, required this.notifications});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.3,
      expand: false,
      builder: (_, controller) => Column(children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Notifications',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  )),
        ),
        const Divider(height: 1),
        Expanded(
          child: notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none,
                          size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('No notifications yet',
                          style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: controller,
                  itemCount: notifications.length,
                  itemBuilder: (_, i) {
                    final n = notifications[i];
                    return ListTile(
                      leading: n.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                n.imageUrl!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => CircleAvatar(
                                  backgroundColor: Colors.deepPurple[50],
                                  child: const Icon(Icons.notifications,
                                      color: Colors.deepPurple),
                                ),
                              ),
                            )
                          : CircleAvatar(
                              backgroundColor: Colors.deepPurple[50],
                              child: const Icon(Icons.notifications,
                                  color: Colors.deepPurple),
                            ),
                      title: Text(n.title,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(n.body),
                      trailing: Text(
                        '${n.time.hour.toString().padLeft(2, '0')}:${n.time.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ─── QR Scanner ──────────────────────────────────────────────────────────────

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
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_scanned) return;
          final value = capture.barcodes.firstOrNull?.rawValue;
          if (value != null && value.startsWith('wss://')) {
            _scanned = true;
            Navigator.pop(context, value);
          }
        },
      ),
    );
  }
}
