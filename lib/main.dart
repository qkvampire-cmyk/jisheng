import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/poker_provider.dart';
import 'providers/exchange_provider.dart';
import 'providers/table_timer_provider.dart';
import 'providers/volatility_provider.dart';
import 'pages/record_list_page.dart';
import 'pages/stats_page.dart';
import 'pages/settings_page.dart';
import 'pages/volatility_page.dart';
import 'pages/record_edit_page.dart';
import 'theme/app_colors.dart';
import 'widgets/app_appbar.dart';

void main() {
  runApp(const PokerTrackerApp());
}

class PokerTrackerApp extends StatelessWidget {
  const PokerTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PokerProvider()..init(),
        ),
        ChangeNotifierProvider(
          create: (_) => ExchangeProvider()..loadRecords(),
        ),
        ChangeNotifierProvider(
          create: (_) => TableTimerProvider()..init(),
        ),
        ChangeNotifierProvider(
          create: (_) => VolatilityProvider()..init(),
        ),
      ],
      child: MaterialApp(
        title: '积胜',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.seed,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: Colors.grey.shade50,
          appBarTheme: AppBarTheme(
            backgroundColor: AppColors.barTop,
            foregroundColor: AppColors.barText,
            elevation: 0,
            centerTitle: true,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
        ),
        home: const MainPage(),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  final _pages = const [
    RecordListPage(),
    StatsPage(),
    VolatilityPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: _getAppBarTitle(), centerTitle: false),
      body: _pages[_currentIndex],
      floatingActionButton: _currentIndex == 0
          ? SizedBox(
              width: 46,
              height: 46,
              child: FloatingActionButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RecordEditPage(),
                    ),
                  );
                },
                child: const Icon(Icons.add),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '账单',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.waves_outlined),
            selectedIcon: Icon(Icons.waves),
            label: '波动',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0:
        return '账单列表';
      case 1:
        return '数据统计';
      case 2:
        return '波动分析';
      case 3:
        return '设置';
      default:
        return '积胜';
    }
  }
}
