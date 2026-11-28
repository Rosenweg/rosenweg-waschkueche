// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/painting.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Angaben der App fuer rosenweg_basis.
///
/// kennung = applicationId (Android) = Bundle-ID (iOS/macOS) = GTK-ID (Linux)
/// = Schema des Ruecksprungs (ch.rosenweg4303.waschkueche:/anmeldung, in Authentik
/// bei rosenweg-apps eintragen) = Paket im App-Katalog (/apps, Updater).
const appAngaben = RosenwegApp(
  kennung: 'ch.rosenweg4303.waschkueche',
  name: 'Rosenweg Waschküche',
  ordner: 'rosenweg-waschkueche',
  beschreibung: 'Waschküche reservieren, Erinnerung an die eigenen Termine; für den Ausschuss Räume, Nutzungen, Abrechnung und Preis.',
  quelle: 'https://github.com/Rosenweg/rosenweg-waschkueche',
  logo: AssetImage('assets/logo/rosenweg-waschkueche-512.png'),
  // Farbe des Anmeldeschirms wie der Logo-Grund (assets/logo/erzeugen.sh GRUPPE);
  // neue-app.sh setzt sie aus werkzeug/logo/flutter-apps.txt
  gruppe: RosenwegGruppe.bewohner,
  // Farbe nach freigeschalteter Funktion (rosenweg-basis docs/gruppenfarbe.md): Verwalten ab Seitenrecht waschküche-admin (Verwaltung); Technik/Praesident alles
  farbGruppen: {RosenwegGruppe.verwaltung, RosenwegGruppe.technik},
  farbRechte: {'waschküche-admin'},
);

/// --dart-define=RW_ATTRAPPE=1: ohne Anmeldung und ohne Server, mit
/// erfundenen Vorfuehrdaten (Entwicklung, Bildschirmfotos, Tests).
const attrappe = bool.fromEnvironment('RW_ATTRAPPE');
