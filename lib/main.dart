import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'models/client_model.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null) {
        final parts = response.payload!.split('|'); // deviceName|hours
        if (parts.length == 2) {
          final deviceName = parts[0];
          final hours = int.tryParse(parts[1]) ?? 0;
          if (hours > 0) {
            _StarlinkManagerTabState.addClientByIpStatic(deviceName, hours);
          }
        }
      }
    },
  );

  runApp(const StarlinkTextExpanderApp());
}

class StarlinkTextExpanderApp extends StatelessWidget {
  const StarlinkTextExpanderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مدير Starlink التلقائي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [Locale('ar', 'SA')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const StarlinkManagerTab(),
    const TextExpanderTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wifi),
            selectedIcon: Icon(Icons.wifi_tethering),
            label: 'مدير Starlink',
          ),
          NavigationDestination(
            icon: Icon(Icons.text_fields),
            selectedIcon: Icon(Icons.text_snippet),
            label: 'الاختصارات (Texpand)',
          ),
        ],
      ),
    );
  }
}

class StarlinkManagerTab extends StatefulWidget {
  const StarlinkManagerTab({super.key});

  static _StarlinkManagerTabState? globalState;

  @override
  State<StarlinkManagerTab> createState() {
    final state = _StarlinkManagerTabState();
    globalState = state;
    return state;
  }
}

class _StarlinkManagerTabState extends State<StarlinkManagerTab> {
  List<ClientDevice> _clients = [];
  Set<String> _knownIPs = {};
  Timer? _timer;
  Timer? _bgScanTimer;

  static void addClientByIpStatic(String name, int hours) {
    StarlinkManagerTab.globalState?._addClient(name, hours);
  }

  @override
  void initState() {
    super.initState();
    _loadClients();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // مراقبة الشبكة تلقائياً كل 30 ثانية
    _bgScanTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _autoScanNetwork();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bgScanTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadClients() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('starlink_clients') ?? [];
    setState(() {
      _clients = data.map((item) => ClientDevice.fromJson(item)).toList();
      _knownIPs = _clients.map((c) => c.deviceName).toSet();
    });
  }

  Future<void> _saveClients() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _clients.map((c) => c.toJson()).toList();
    await prefs.setStringList('starlink_clients', data);
  }

  // فحص الشبكة واستخراج اسم الجهاز برقم الـ IP
  Future<void> _autoScanNetwork() async {
    final info = NetworkInfo();
    final wifiIP = await info.getWifiIP();
    if (wifiIP == null) return;

    final subnet = wifiIP.substring(0, wifiIP.lastIndexOf('.'));

    for (int i = 2; i < 50; i++) {
      final targetIP = '$subnet.$i';
      final ipSuffix = '.$i';

      try {
        final socket = await Socket.connect(targetIP, 80, timeout: const Duration(milliseconds: 40));
        socket.destroy();

        // محاولة جلب اسم هاتف الجهاز العميل
        String resolvedHost = 'جهاز';
        try {
          final hostObj = await InternetAddress(targetIP).reverse().timeout(const Duration(milliseconds: 80));
          if (hostObj.host.isNotEmpty && hostObj.host != targetIP) {
            resolvedHost = hostObj.host.split('.').first;
          }
        } catch (_) {}

        final fullDeviceLabel = '$resolvedHost ($ipSuffix)';

        if (_knownIPs.contains(fullDeviceLabel) || _knownIPs.contains(targetIP)) continue;

        _knownIPs.add(fullDeviceLabel);
        _knownIPs.add(targetIP);

        // إرسال الإشعار بالاسم والـ IP التلقائي
        _showNewDeviceNotification(fullDeviceLabel, ipSuffix);
      } catch (_) {}
    }
  }

  Future<void> _showNewDeviceNotification(String fullLabel, String ipSuffix) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'starlink_auto_channel',
      'تنبيهات أجهزة Starlink',
      channelDescription: 'تنبيهات فورية عند اتصال أجهزة جديدة',
      importance: Importance.max,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction('2h', '2 ساعة'),
        AndroidNotificationAction('4h', '4 ساعات'),
        AndroidNotificationAction('cancel', 'إلغاء / حظر'),
      ],
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '📡 جهاز جديد اتصل بالشبكة!',
      '$fullLabel - حدد مدة الاشتراك:',
      platformChannelSpecifics,
      payload: '$fullLabel|4',
    );
  }

  void _addClient(String name, int hours) {
    final newClient = ClientDevice(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      deviceName: name,
      startTime: DateTime.now(),
      durationHours: hours,
    );
    setState(() {
      _clients.add(newClient);
      _knownIPs.add(name);
    });
    _saveClients();
  }

  void _togglePause(ClientDevice client) {
    setState(() {
      if (client.isPaused) {
        client.isPaused = false;
      } else {
        client.remainingSecondsWhenPaused = client.remainingSeconds;
        client.isPaused = true;
      }
    });
    _saveClients();
  }

  void _deleteClient(String id) {
    setState(() {
      _clients.removeWhere((c) => c.id == id);
    });
    _saveClients();
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('hh:mm a', 'ar');

    return Scaffold(
      appBar: AppBar(
        title: const Text('مراقب Starlink التلقائي'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.radar),
            tooltip: 'فحص الشبكة فوراً',
            onPressed: () {
              _autoScanNetwork();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('جاري التعرف على أجهزة Starlink جديدة...')),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _addClient('جهاز يدوي (.${DateTime.now().second})', 4);
        },
        icon: const Icon(Icons.add_link),
        label: const Text('إضافة يدوي'),
      ),
      body: _clients.isEmpty
          ? const Center(
              child: Text(
                'المراقب التلقائي شغال 📡\nعند دخول أي جهاز لشبكة Starlink سيصلك إشعار باسم الهاتف ورقم الـ IP مباشرة.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _clients.length,
              itemBuilder: (context, index) {
                final client = _clients[index];
                final endAt = client.startTime.add(Duration(hours: client.durationHours));
                final isExpired = client.remainingSeconds <= 0;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isExpired
                          ? Colors.red.shade100
                          : (client.isPaused ? Colors.amber.shade100 : Colors.green.shade100),
                      child: Icon(
                        isExpired
                            ? Icons.timer_off
                            : (client.isPaused ? Icons.pause : Icons.wifi),
                        color: isExpired
                            ? Colors.red
                            : (client.isPaused ? Colors.amber.shade900 : Colors.green.shade900),
                      ),
                    ),
                    title: Text(
                      '${client.deviceName} (${client.durationHours} ساعات)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('بداية الاتصال: ${timeFormat.format(client.startTime)}'),
                        Text('ينتهي في: ${timeFormat.format(endAt)}'),
                        const SizedBox(height: 4),
                        Text(
                          isExpired
                              ? 'الوضع: منتهي! قم بفصله من Starlink ❌'
                              : 'المتبقي: ${client.remainingFormatted} ${client.isPaused ? "(مؤقت)" : ""}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isExpired
                                ? Colors.red
                                : (client.isPaused ? Colors.amber.shade900 : Colors.green),
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(client.isPaused ? Icons.play_arrow : Icons.pause),
                          color: Colors.orange,
                          onPressed: () => _togglePause(client),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteClient(client.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class TextExpanderTab extends StatefulWidget {
  const TextExpanderTab({super.key});

  @override
  State<TextExpanderTab> createState() => _TextExpanderTabState();
}

class _TextExpanderTabState extends State<TextExpanderTab> {
  final List<Map<String, String>> _shortcuts = [
    {'shortcut': '#سلا', 'expanded': 'السلام عليكم ورحمة الله وبركاته'},
    {'shortcut': '#وقت', 'expanded': 'الوقت الحالي: %time%'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتبة الاختصارات'),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _shortcuts.length,
        itemBuilder: (context, index) {
          final item = _shortcuts[index];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.bolt, color: Colors.amber),
              title: Text(item['shortcut']!, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(item['expanded']!),
            ),
          );
        },
      ),
    );
  }
}
