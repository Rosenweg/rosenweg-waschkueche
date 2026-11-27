// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:rosenweg_basis/rosenweg_basis.dart';

import 'daten.dart';

/// Alle Aufrufe der App gegen die Haupt-API (www.rosenweg4303.ch, /api/wasch/*).
///
/// Die Haupt-API prueft selbst:
///  * Raeume und Belegung sieht nur, wer zur STWEG des Raums gehoert (auch
///    deren Hausverwaltung); reservieren duerfen nur die Bewohnergruppen.
///  * Verwalten: Technik/Praesident oder Seitenrecht „waschküche-admin“
///    (lesen = ansehen, schreiben = aendern) und Ausschuss/Verwaltung der
///    STWEG mit Waschkueche (api/lib/wasch-admin.js). Die Tuer stellt nur
///    Technik/Praesident ein.
class WaschApi {
  WaschApi(this.api);
  final RosenwegApi api;

  static List<Map<String, dynamic>> _liste(Object? l) =>
      [for (final e in l is List ? l : const []) if (e is Map<String, dynamic>) e];

  static Map<String, dynamic> _objekt(Object? j) => j is Map<String, dynamic> ? j : const {};

  static String _q(String s) => Uri.encodeQueryComponent(s);

  // ── Reservieren ──
  Future<List<Raum>> raeume() async => [for (final r in _liste(await api.get('/api/wasch/rooms'))) Raum.aus(r)];

  /// Belegung eines Raums von [von] bis [bis] (alle Personen). Zeiten als
  /// Ortszeit ohne Zone, wie die Tabelle sie fuehrt.
  Future<List<Reservation>> belegung(int raum, DateTime von, DateTime bis) async {
    final l = await api.get('/api/wasch/reservations?room_id=$raum'
        '&from=${_q(apiZeit(von))}&to=${_q(apiZeit(bis))}');
    return [for (final r in _liste(l)) ?Reservation.aus(r)];
  }

  /// Eigene kommende Reservationen.
  Future<List<Reservation>> meine() async {
    final l = [for (final r in _liste(await api.get('/api/wasch/my/reservations'))) ?Reservation.aus(r)];
    l.sort((a, b) => a.von.compareTo(b.von));
    return l;
  }

  /// Einmal oder woechentlich bis [serieBis]. Rueckgabe: Anzahl angelegter
  /// Termine (bei einer Serie fallen belegte Wochen still weg, wie im Web).
  Future<int> reservieren(int raum, DateTime von, DateTime bis, {DateTime? serieBis}) async {
    final j = _objekt(await api.post('/api/wasch/reservations', {
      'room_id': raum,
      'start_time': apiZeit(von),
      'end_time': apiZeit(bis),
      if (serieBis != null) ...{'recurring': true, 'recurring_until': apiDatum(serieBis)},
    }));
    final n = j['created'];
    return n is int ? n : 1;
  }

  Future<void> stornieren(int id) => api.delete('/api/wasch/reservations/$id');

  /// Alle kuenftigen Termine der Serie; Rueckgabe: Anzahl.
  Future<int> serieStornieren(int id) async {
    final j = _objekt(await api.delete('/api/wasch/reservations/$id/series'));
    final n = j['cancelled'];
    return n is int ? n : 0;
  }

  /// Sperrzeiten eines Raums (oder aller, ohne [raum]); ohne Zeitraum die kommenden.
  Future<List<Sperrzeit>> sperrzeiten({int? raum, DateTime? von, DateTime? bis}) async {
    final q = [
      if (raum != null) 'room_id=$raum',
      if (von != null) 'from=${_q(apiZeit(von))}',
      if (bis != null) 'to=${_q(apiZeit(bis))}',
    ].join('&');
    final l = await api.get('/api/wasch/sperrzeiten${q.isEmpty ? '' : '?$q'}');
    return [for (final s in _liste(l)) ?Sperrzeit.aus(s)];
  }

  /// Rueckgabe: wie viele bestehende Reservationen in die Sperrzeit fallen.
  Future<int> sperren(int raum, DateTime von, DateTime bis, String grund) async {
    final j = _objekt(await api.post('/api/wasch/sperrzeiten', {
      'room_id': raum,
      'start_time': apiZeit(von),
      'end_time': apiZeit(bis),
      'grund': grund,
    }));
    final n = j['betroffene_reservationen'];
    return n is int ? n : 0;
  }

  Future<void> sperreAufheben(int id) => api.delete('/api/wasch/sperrzeiten/$id');

  Future<Einstellungen> einstellungen() async => Einstellungen.aus(_objekt(await api.get('/api/wasch/settings')));

  Future<void> einstellungenSpeichern(Einstellungen e) => api.put('/api/wasch/settings', {
        'cost_per_kwh': e.preisProKwh,
        'reservation_max_days': e.maxTage,
        'reservation_max_per_user': e.maxOffen,
        'auto_billing': e.autoAbrechnung,
      });

  // ── Verwalten ──
  Future<Statistik> statistik() async => Statistik.aus(_objekt(await api.get('/api/wasch/admin/stats')));

  Future<List<Nutzung>> nutzungen({DateTime? monat}) async {
    final l = await api.get('/api/wasch/admin/sessions${monat == null ? '' : '?month=${apiMonat(monat)}'}');
    return [for (final n in _liste(l)) Nutzung.aus(n)];
  }

  Future<List<Kosten>> kosten(DateTime monat) async =>
      [for (final k in _liste(await api.get('/api/wasch/admin/costs?month=${apiMonat(monat)}'))) Kosten.aus(k)];

  /// Abrechnung eines vergangenen Monats per E-Mail an alle Personen mit
  /// Nutzungen; jeder Monat nur einmal (sonst 409).
  Future<String?> abrechnungSenden(DateTime monat) async {
    final j = _objekt(await api.post('/api/wasch/admin/billing/run', {'month': apiMonat(monat)}));
    final m = j['message'];
    return m is String ? m : null;
  }

  /// Neu (ohne [id]) oder aendern. [tuer] schickt nur, wer sie aendern darf
  /// (sonst den bisherigen Wert, die API vergleicht).
  Future<void> raumSpeichern({int? id, required String name, String? ort, String? zaehler, String? tuer, int? stweg}) async {
    final k = <String, Object?>{
      'name': name,
      'location': ort ?? '',
      'energy_meter_id': (zaehler == null || zaehler.isEmpty) ? null : zaehler,
      'unifi_door_id': (tuer == null || tuer.isEmpty) ? null : tuer,
    };
    if (id == null) {
      await api.post('/api/wasch/rooms', {...k, 'stweg': ?stweg});
    } else {
      await api.put('/api/wasch/rooms/$id', k);
    }
  }
}
