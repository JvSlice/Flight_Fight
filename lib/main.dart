import 'package:flutter/material.dart';
import 'game/empire_flight_game.dart';

void main() {
  runApp(const EmpireFlightApp());
}

class EmpireFlightApp extends StatelessWidget {
  const EmpireFlightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Empire Flight',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF05070D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7FDBFF),
          secondary: Color(0xFFFFC857),
        ),
      ),
      home: const EmpireFlightGame(),
    );
  }
}
