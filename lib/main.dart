import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'models/client_model.dart';

void main() {
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
            icon: Icon(Icons.text_fields),
            selectedIcon: Icon(Icons.text_snippet),
            label: 'الاختصارات (Texpand)',
          ),
        ],
      ),
    );
  }
}

// ==================== تبويب مدير Starlink ====================
class StarlinkManagerTab extends StatefulWidget {
  const StarlinkManagerTab({super.key});

  @override
  State<StarlinkManagerTab> createState() => _StarlinkManagerTabState();
}

class _StarlinkManagerTabState extends State<StarlinkManagerTab> {
  List<ClientDevice> _clients = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadClients();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadClients() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('starlink_clients') ?? [];
    setState(() {
      _clients = data.map((item) => ClientDevice.fromJson(item)).toList();
    });
  }

  Future<void> _saveClients() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _clients.map((c) => c.toJson()).toList();
    await prefs.setStringList('starlink_clients', data);
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

  void _showAddClientDialog() {
    final nameController = TextEditingController();
    int selectedHours = 4;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة جهاز متصل جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الجهاز أو العميل',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_android),
              ),
            ),
            const SizedBox(height: 16),
            const Text('مدة الاشتراك:'),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (context, setDialogState) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [2, 4, 8, 12].map((hours) {
                  final isSelected = selectedHours == hours;
                  return ChoiceChip(
                    label: Text('$hoursس'),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setDialogState(() => selectedHours = hours);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                _addClient(name, selectedHours);
                Navigator.pop(ctx);
              }
            },
            child: const Text('إضافة وحساب الوقت'),
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
        title: const Text('أجهزة Starlink المتصلة'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadClients,
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddClientDialog,
        icon: const Icon(Icons.add_link),
        label: const Text('ربط جهاز جديد'),
      ),
      body: _clients.isEmpty
          ? const Center(
              child: Text(
                'لا توجد أجهزة مربوطة حالياً.\nاضغط على "ربط جهاز جديد" للبدء.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
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
                        Text('وقت الاتصال: ${timeFormat.format(client.startTime)}'),
                        Text('وقت الانتهاء: ${timeFormat.format(endAt)}'),
                        const SizedBox(height: 4),
                        Text(
                          isExpired
                              ? 'الوضع: منتهي الاشتراك ❌'
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
                          tooltip: client.isPaused ? 'استئناف' : 'إيقاف مؤقت',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteClient(client.id),
                          tooltip: 'حذف الجهاز',
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

// ==================== تبويب الاختصارات (Texpand) ====================
class TextExpanderTab extends StatefulWidget {
  const TextExpanderTab({super.key});

  @override
  State<TextExpanderTab> createState() => _TextExpanderTabState();
}

class _TextExpanderTabState extends State<TextExpanderTab> {
  final List<Map<String, String>> _shortcuts = [
    {'shortcut': '#سلا', 'expanded': 'السلام عليكم ورحمة الله وبركاته'},
    {'shortcut': '#وقت', 'expanded': 'الوقت الحالي: %time%'},
    {'shortcut': '#تاريخ', 'expanded': 'تاريخ اليوم: %date%'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتبة الاختصارات (Texpand)'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _shortcuts.length,
        itemBuilder: (context, index) {
          final item = _shortcuts[index];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.bolt, color: Colors.amber),
              title: Text(
                item['shortcut']!,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              subtitle: Text(item['expanded']!),
            ),
          );
        },
      ),
    );
  }
}
