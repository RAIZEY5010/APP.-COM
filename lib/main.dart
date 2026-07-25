import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        final parts = response.payload!.split('|');
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
      title: 'مدير Starlink والاختصارات',
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
            icon: Icon(Icons.bolt),
            selectedIcon: Icon(Icons.flash_on),
            label: 'الاختصارات (Texpand)',
          ),
        ],
      ),
    );
  }
}

// ==================== 1. مدير شبكة Starlink (خيارات إشعارات مخصصة) ====================
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
  Set<String> _notifiedExpiredIDs = {};
  Timer? _timer;
  Timer? _bgScanTimer;

  // توقيتات الإشعار المخصصة (يمكن تعديلها من الإعدادات)
  int _notifOption1 = 2; // الخيار الأول بالافتراضي 2س
  int _notifOption2 = 5; // الخيار الثاني بالافتراضي 5س

  static void addClientByIpStatic(String name, int hours) {
    StarlinkManagerTab.globalState?._addClient(name, hours);
  }

  @override
  void initState() {
    super.initState();
    _loadClients();
    _loadNotifSettings();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkExpiredClients();
      if (mounted) setState(() {});
    });

    _bgScanTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _autoScanNetwork();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bgScanTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNotifSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifOption1 = prefs.getInt('notif_opt1') ?? 2;
      _notifOption2 = prefs.getInt('notif_opt2') ?? 5;
    });
  }

  Future<void> _saveNotifSettings(int opt1, int opt2) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_opt1', opt1);
    await prefs.setInt('notif_opt2', opt2);
    setState(() {
      _notifOption1 = opt1;
      _notifOption2 = opt2;
    });
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

  void _checkExpiredClients() {
    for (var client in _clients) {
      if (client.remainingSeconds <= 0 && !_notifiedExpiredIDs.contains(client.id)) {
        _notifiedExpiredIDs.add(client.id);
        _showExpiredNotification(client.deviceName);
      }
    }
  }

  Future<void> _showExpiredNotification(String deviceName) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'starlink_expired_channel',
      'تنبيهات انتهاء الوقت',
      channelDescription: 'تنبيه فوري عند انتهاء وقت اشتراك جهاز',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '⏰ انتهى وقت الاشتراك!',
      'الجهاز: $deviceName انتهت مدته الحالية. قم بفصله من Starlink.',
      platformDetails,
    );
  }

  Future<void> _autoScanNetwork() async {
    final info = NetworkInfo();
    final wifiIP = await info.getWifiIP();
    if (wifiIP == null) return;

    final subnet = wifiIP.substring(0, wifiIP.lastIndexOf('.'));

    for (int i = 2; i < 60; i++) {
      final targetIP = '$subnet.$i';
      final ipSuffix = '.$i';

      final isAlive = await _pingIP(targetIP);
      if (isAlive) {
        String resolvedHost = 'جهاز';
        try {
          final hostObj = await InternetAddress(targetIP).reverse().timeout(const Duration(milliseconds: 100));
          if (hostObj.host.isNotEmpty && hostObj.host != targetIP) {
            resolvedHost = hostObj.host.split('.').first;
          }
        } catch (_) {}

        final fullDeviceLabel = '$resolvedHost ($ipSuffix)';

        if (_knownIPs.contains(fullDeviceLabel) || _knownIPs.contains(targetIP)) continue;

        _knownIPs.add(fullDeviceLabel);
        _knownIPs.add(targetIP);

        _showNewDeviceNotification(fullDeviceLabel, ipSuffix);
      }
    }
  }

  Future<bool> _pingIP(String ip) async {
    try {
      final result = await Process.run('ping', ['-c', '1', '-w', '1', ip]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // بناء الإشعار بأزرار توقيت مخصصة
  Future<void> _showNewDeviceNotification(String fullLabel, String ipSuffix) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'starlink_auto_channel',
      'تنبيهات أجهزة Starlink',
      channelDescription: 'تنبيهات فورية عند اتصال أجهزة جديدة',
      importance: Importance.max,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction('opt1', '$_notifOption1 ساعات', inputs: []),
        AndroidNotificationAction('opt2', '$_notifOption2 ساعات', inputs: []),
        const AndroidNotificationAction('cancel', 'إلغاء / حظر'),
      ],
    );
    final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '📡 جهاز جديد اتصل بالشبكة!',
      '$fullLabel - اختر مدة الاشتراك الفورية:',
      platformDetails,
      payload: '$fullLabel|$_notifOption1',
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

  void _showNotificationSettingsDialog() {
    int tempOpt1 = _notifOption1;
    int tempOpt2 = _notifOption2;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تخصيص أزرار توقيت الإشعار'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اختر التوقيتين اللذين ترغب بظهورهما في أزرار الإشعار الفوري:'),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('الخيار الأول: '),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: tempOpt1,
                  items: [1, 2, 3, 4, 5, 6, 8, 12, 24].map((h) {
                    return DropdownMenuItem(value: h, child: Text('$h ساعات'));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => tempOpt1 = val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('الخيار الثاني: '),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: tempOpt2,
                  items: [1, 2, 3, 4, 5, 6, 8, 12, 24].map((h) {
                    return DropdownMenuItem(value: h, child: Text('$h ساعات'));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => tempOpt2 = val);
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              _saveNotifSettings(tempOpt1, tempOpt2);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم حفظ التوقيتات: ($tempOpt1 ساعات و $tempOpt2 ساعات)')),
              );
            },
            child: const Text('حفظ التوقيتات'),
          ),
        ],
      ),
    );
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
            icon: const Icon(Icons.settings),
            tooltip: 'إعدادات أزرار الإشعار',
            onPressed: _showNotificationSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.radar),
            tooltip: 'فحص الشبكة فوراً',
            onPressed: () {
              _autoScanNetwork();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('جاري فحص الأجهزة المتصلة بـ Starlink...')),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showManualAddDialog(),
        icon: const Icon(Icons.add_link),
        label: const Text('إضافة يدوي'),
      ),
      body: _clients.isEmpty
          ? const Center(
              child: Text(
                'المراقب التلقائي شغال 📡\nاضغط على أيقونة الضبط ⚙️ بالأعلى لتغيير أزرار التوقيت ببطاقة الإشعار.',
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

  void _showManualAddDialog() {
    final nameController = TextEditingController();
    int hours = _notifOption1;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة جهاز يدوي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الجهاز أو الـ IP',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [2, 4, 5, 8, 12].map((h) => ChoiceChip(
                label: Text('$hس'),
                selected: hours == h,
                onSelected: (v) { if (v) setState(() => hours = h); },
              )).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                _addClient(nameController.text.trim(), hours);
                Navigator.pop(ctx);
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }
}

// ==================== 2. مكتبة الاختصارات التفاعلية بالحساب الذكي للوقت ====================
class TextExpanderTab extends StatefulWidget {
  const TextExpanderTab({super.key});

  @override
  State<TextExpanderTab> createState() => _TextExpanderTabState();
}

class _TextExpanderTabState extends State<TextExpanderTab> {
  List<Map<String, String>> _shortcuts = [];

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  Future<void> _loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('saved_shortcuts');
    if (data != null) {
      final List decoded = jsonDecode(data);
      setState(() {
        _shortcuts = decoded.map((e) => Map<String, String>.from(e)).toList();
      });
    } else {
      _shortcuts = [
        {'shortcut': 'mn', 'expanded': 'ينتهي اشتراكك الساعة: %time+5h%'},
        {'shortcut': '#سلا', 'expanded': 'السلام عليكم ورحمة الله وبركاته'},
        {'shortcut': '#وقت', 'expanded': 'الوقت الحالي: %time%'},
      ];
      _saveShortcuts();
    }
  }

  Future<void> _saveShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_shortcuts', jsonEncode(_shortcuts));
  }

  String _processDynamicText(String text) {
    final now = DateTime.now();
    final format = DateFormat('hh:mm a', 'ar');

    text = text.replaceAll('%time%', format.format(now));

    final regExp = RegExp(r'%time\+(\d+)h%');
    text = text.replaceAllMapped(regExp, (match) {
      final hoursToAdd = int.tryParse(match.group(1) ?? '0') ?? 0;
      final futureDate = now.add(Duration(hours: hoursToAdd));
      return format.format(futureDate);
    });

    return text;
  }

  void _addOrEditShortcut({int? index}) {
    final shortcutCtrl = TextEditingController(text: index != null ? _shortcuts[index]['shortcut'] : '');
    final expandedCtrl = TextEditingController(text: index != null ? _shortcuts[index]['expanded'] : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'إضافة اختصار جديد' : 'تعديل الاختصار'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: shortcutCtrl,
              decoration: const InputDecoration(
                labelText: 'رمز الاختصار (مثال: mn)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: expandedCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'النص الكامل البديل',
                hintText: 'مثال: ينتهي الوقت %time+5h%',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '💡 يمكنك استخدام:\n• %time% للوقت الحالي\n• %time+2h% للوقت بعد ساعتين\n• %time+5h% للوقت بعد 5 ساعات',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (shortcutCtrl.text.isNotEmpty && expandedCtrl.text.isNotEmpty) {
                setState(() {
                  if (index == null) {
                    _shortcuts.add({'shortcut': shortcutCtrl.text, 'expanded': expandedCtrl.text});
                  } else {
                    _shortcuts[index] = {'shortcut': shortcutCtrl.text, 'expanded': expandedCtrl.text};
                  }
                });
                _saveShortcuts();
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _deleteShortcut(int index) {
    setState(() {
      _shortcuts.removeAt(index);
    });
    _saveShortcuts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتبة الاختصارات (Texpand)'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditShortcut(),
        child: const Icon(Icons.add),
      ),
      body: _shortcuts.isEmpty
          ? const Center(child: Text('لا توجد اختصارات محفوظة.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _shortcuts.length,
              itemBuilder: (context, index) {
                final item = _shortcuts[index];
                final processedText = _processDynamicText(item['expanded']!);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.bolt, color: Colors.amber),
                    title: Text(
                      item['shortcut']!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('النص المنسوخ: $processedText', style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                        Text('القالب: ${item['expanded']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.blue),
                          tooltip: 'نسخ النص بالوقت المحسوب',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: processedText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('تم النسخ بالوقت المحسوب: ($processedText)')),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.grey),
                          onPressed: () => _addOrEditShortcut(index: index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteShortcut(index),
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
