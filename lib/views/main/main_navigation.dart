import 'package:flutter/material.dart';

import '../../services/order_service.dart';
import '../../services/user_session_service.dart';
import 'chat_screen.dart';
import 'map_screen.dart';
import 'order_list_screen.dart';
import 'profile_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({
    super.key,
    required this.isDarkMode,
    required this.onThemeModeChanged,
    required this.orderService,
    required this.userSessionService,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onThemeModeChanged;
  final OrderService orderService;
  final UserSessionService userSessionService;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      MapScreen(
        orderService: widget.orderService,
        userSessionService: widget.userSessionService,
      ),
      OrderListScreen(
        orderService: widget.orderService,
        userSessionService: widget.userSessionService,
      ),
      const ChatScreen(),
      ProfileScreen(
        isDarkMode: widget.isDarkMode,
        onThemeModeChanged: widget.onThemeModeChanged,
      ),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Bản đồ',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Đơn hàng',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Trò chuyện',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Hồ sơ',
          ),
        ],
      ),
    );
  }
}
