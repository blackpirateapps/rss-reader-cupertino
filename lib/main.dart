library rss_reader_cupertino_app;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webfeed_plus/webfeed_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'src/feed_screen.dart';
part 'src/library_settings_screens.dart';
part 'src/article_screens.dart';
part 'src/data_models.dart';
part 'src/ui_components.dart';
part 'src/helpers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppController.create();
  runApp(RssReaderApp(controller: controller));
}

class RssReaderApp extends StatelessWidget {
  const RssReaderApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return AppScope(
          controller: controller,
          child: CupertinoApp(
            title: 'RSS Reader',
            debugShowCheckedModeBanner: false,
            theme: CupertinoThemeData(
              brightness: controller.isDarkMode ? Brightness.dark : Brightness.light,
              primaryColor: CupertinoColors.activeBlue,
              scaffoldBackgroundColor: controller.isDarkMode
                  ? const Color(0xFF000000)
                  : const Color(0xFFF2F2F7),
              barBackgroundColor: controller.isDarkMode
                  ? const Color(0xFF111111)
                  : CupertinoColors.systemBackground,
            ),
            home: const HomeShell(),
          ),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final CupertinoTabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = CupertinoTabController(initialIndex: 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);

    return CupertinoTabScaffold(
      controller: _tabController,
      tabBar: CupertinoTabBar(
        items: [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.list_bullet),
            label: 'Feed',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.book),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        if (index == 0) {
          return CupertinoTabView(
            builder: (_) => FeedScreen(controller: controller),
          );
        }
        if (index == 1) {
          return CupertinoTabView(
            builder: (_) => LibraryScreen(
              controller: controller,
              onOpenFeed: (url) {
                controller.selectFeed(url);
                _tabController.index = 0;
              },
            ),
          );
        }
        return CupertinoTabView(
          builder: (_) => SettingsScreen(controller: controller),
        );
      },
    );
  }
}
