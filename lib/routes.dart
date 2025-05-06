import 'package:flutter/material.dart';
import 'package:aithelete/pages/splash_screen.dart';
import 'package:aithelete/pages/login_screen.dart';
import 'package:aithelete/pages/register_screen.dart';
import 'package:aithelete/pages/Home.dart';
import 'package:aithelete/pages/chatbot.dart';
import 'package:aithelete/pages/motion_tracking_page.dart';

final Map<String, WidgetBuilder> appRoutes = {
  '/': (context) => const SplashScreen(),
  '/login': (context) => const LoginScreen(),
  '/register': (context) => const RegisterScreen(),
  '/home': (context) => HomePage(),

  '/chatbot': (context) => const ChatbotPage(),
  '/motion': (context) => const MotionTrackingPage(),
};
