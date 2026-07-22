import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
//import 'package:provider_cart_settings/objects/pizza_object.dart';

abstract class AppTheme {
  static final lightTheme = ThemeData(
    textTheme: baseTextTheme,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.red,
      brightness: Brightness.light,
    ),
  );
  static final darkTheme = ThemeData(
    textTheme: baseTextTheme,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.red,
      brightness: Brightness.dark,
    ),
  );

  static final TextTheme baseTextTheme = TextTheme(
    // Display Styles - für Hero-Texte
    displayLarge: GoogleFonts.poppins(
      fontSize: 57,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
    ),
    displayMedium: GoogleFonts.poppins(
      fontSize: 45,
      fontWeight: FontWeight.w400,
    ),
    displaySmall: GoogleFonts.poppins(
      fontSize: 36,
      fontWeight: FontWeight.w400,
    ),

    // Headline Styles - für Überschriften
    headlineLarge: GoogleFonts.poppins(
      fontSize: 32,
      fontWeight: FontWeight.w600,
    ),
    headlineMedium: GoogleFonts.poppins(
      fontSize: 28,
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: GoogleFonts.poppins(
      fontSize: 24,
      fontWeight: FontWeight.w500,
    ),

    // Title Styles - für Komponenten-Titel
    titleLarge: GoogleFonts.lato(
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: GoogleFonts.lato(
      fontSize: 18,
      fontWeight: FontWeight.w500,
    ),
    titleSmall: GoogleFonts.lato(
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),

    // Body Styles - für Fließtext
    bodyLarge: GoogleFonts.lato(
      fontSize: 16,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: GoogleFonts.lato(
      fontSize: 14,
      fontWeight: FontWeight.w400,
    ),
    bodySmall: GoogleFonts.lato(
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ),

    // Label Styles - für Beschriftungen
    labelLarge: GoogleFonts.lato(
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    labelMedium: GoogleFonts.lato(
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: GoogleFonts.lato(
      fontSize: 11,
      fontWeight: FontWeight.w500,
    ),
  );

  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
    ThemeMode.light,
  );
}

/*abstract class AppPizzaTheme {
  static final List<Pizza> pizzas = [
    Pizza(
      name: 'Margaritha',
      price: 6.00,
      image: 'assets/images/echo_margaritha.jpg',
    ),
    Pizza(
      name: 'Hawaii',
      price: 6.25,
      image: 'assets/images/echo_hawaii.png',
    ),
    Pizza(
      name: 'Calzone',
      price: 6.50,
      image: 'assets/images/echo_calzone.png',
    ),
    Pizza(
      name: 'Mexicana',
      price: 7.00,
      image: 'assets/images/echo_mexicana.png',
    ),
    Pizza(name: 'BBQ', price: 8.00, image: 'assets/images/echo_bbq.png'),
    Pizza(
      name: 'Tonno',
      price: 7.50,
      image: 'assets/images/echo_tonno.png',
    ),
    Pizza(
      name: 'Peperoni',
      price: 6.75,
      image: 'assets/images/echo_peperoni.png',
    ),
    Pizza(
      name: 'Romana',
      price: 6.50,
      image: 'assets/images/echo_romana.png',
    ),
  ];
}*/
