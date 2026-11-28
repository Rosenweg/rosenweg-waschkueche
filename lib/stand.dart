// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/foundation.dart';

import 'daten.dart';
import 'erinnerung.dart';
import 'wasch_api.dart';

/// Was alle Seiten teilen: die Raeume der Person und ihre eigenen kommenden
/// Reservationen (fuer „Meine“, die Farbe im Raster und die Erinnerung).
class WaschStand extends ChangeNotifier {
  WaschStand(this.api, {DateTime Function()? jetzt, this.erinnerungen = false}) : jetzt = jetzt ?? DateTime.now;

  final WaschApi api;
  final DateTime Function() jetzt;

  /// Benachrichtigungen 15 Minuten vor Beginn planen (nicht auf geteilten
  /// Telefonen, nicht mit Vorfuehrdaten).
  final bool erinnerungen;

  List<Raum>? raeume;
  List<Reservation> meine = const [];

  /// Wirksame Regeln (Tage im Voraus usw.); Standard, bis geladen.
  Einstellungen einstellungen = const Einstellungen();
  Object? fehler;
  bool laedt = false;

  /// Zuletzt gewaehlter Raum (bleibt beim Wechsel der Seiten).
  int? raumId;

  Raum? get raum {
    final r = raeume;
    if (r == null || r.isEmpty) return null;
    return r.firstWhere((x) => x.id == raumId, orElse: () => r.first);
  }

  Set<int> get meineIds => {for (final r in meine) r.id};

  Erinnerung? get erinnerung => Erinnerung.fuer(meine, jetzt());

  /// Raeume und eigene Termine (beim Start, beim Zurueckkommen in die App).
  Future<void> laden() async {
    laedt = true;
    notifyListeners();
    try {
      final r = await api.raeume();
      final m = await api.meine();
      raeume = r;
      meine = m;
      try {
        einstellungen = await api.einstellungen();
      } catch (_) {
        // aeltere API ohne Einstellungen: Standard
      }
      fehler = null;
    } catch (e) {
      fehler = e;
    } finally {
      laedt = false;
      notifyListeners();
    }
  }

  /// Nur die eigenen Termine (nach Reservieren/Stornieren, regelmaessig).
  Future<void> meineLaden() async {
    try {
      meine = await api.meine();
      notifyListeners();
    } catch (_) {
      // still: die Erinnerung bleibt beim letzten Stand
    }
  }

  void raumWaehlen(int id) {
    raumId = id;
    notifyListeners();
  }

  /// Uhr weiter (Erinnerung neu berechnen).
  void ticken() => notifyListeners();
}
