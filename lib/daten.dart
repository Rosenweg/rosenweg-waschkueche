// SPDX-License-Identifier: GPL-3.0-or-later
// Was die Haupt-API zur Waschkueche liefert (api/server.js, /api/wasch/*).

String? _text(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

/// Zeitpunkt aus der API (ISO, UTC) als Ortszeit.
DateTime? zeitAus(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

double _zahl(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

String _zwei(int n) => n.toString().padLeft(2, '0');

/// So erwartet die API Zeiten: Ortszeit ohne Zone (wie waschkueche.html).
String apiZeit(DateTime z) => '${z.year}-${_zwei(z.month)}-${_zwei(z.day)}T${_zwei(z.hour)}:${_zwei(z.minute)}:00';

/// 2026-11-27
String apiDatum(DateTime z) => '${z.year}-${_zwei(z.month)}-${_zwei(z.day)}';

/// 2026-11
String apiMonat(DateTime z) => '${z.year}-${_zwei(z.month)}';

/// CHF 12.50
String franken(double b) => 'CHF ${b.toStringAsFixed(2)}';

const _monate = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

/// November 2026
String monatText(DateTime z) => '${_monate[z.month - 1]} ${z.year}';

/// Waschkueche (Raum) – GET /api/wasch/rooms.
class Raum {
  const Raum({
    required this.id,
    required this.name,
    this.ort,
    this.stweg,
    this.zaehler,
    this.tuer,
    this.aktiv = true,
  });

  final int id;
  final String name;
  final String? ort;
  final int? stweg;

  /// Energiezaehler (Energie-Monitor), z. B. shelly-wasch1.
  final String? zaehler;

  /// Tuer in UniFi Access (nur Technik/Praesident stellen sie ein).
  final String? tuer;
  final bool aktiv;

  factory Raum.aus(Map<String, dynamic> j) => Raum(
        id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
        name: _text(j['name']) ?? 'Waschküche',
        ort: _text(j['location']),
        stweg: int.tryParse('${j['stweg']}'),
        zaehler: _text(j['energy_meter_id']),
        tuer: _text(j['unifi_door_id']),
        aktiv: j['active'] != false,
      );
}

/// Reservation – GET /api/wasch/reservations, /api/wasch/my/reservations.
class Reservation {
  const Reservation({
    required this.id,
    required this.raumId,
    required this.von,
    required this.bis,
    this.raumName,
    this.person,
    this.wohnung,
    this.woechentlich = false,
    this.serieBis,
  });

  final int id;
  final int raumId;
  final DateTime von;
  final DateTime bis;
  final String? raumName;

  /// Name der Person (nur in der Belegung, nicht in „Meine“).
  final String? person;
  final String? wohnung;
  final bool woechentlich;
  final DateTime? serieBis;

  static Reservation? aus(Map<String, dynamic> j) {
    final von = zeitAus(j['start_time']);
    final bis = zeitAus(j['end_time']);
    if (von == null || bis == null) return null;
    return Reservation(
      id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
      raumId: j['room_id'] is int ? j['room_id'] as int : int.tryParse('${j['room_id']}') ?? 0,
      von: von,
      bis: bis,
      raumName: _text(j['room_name']),
      person: _text(j['user_name']),
      wohnung: _text(j['wohnung']),
      woechentlich: j['recurring'] == true,
      serieBis: zeitAus(j['recurring_until']),
    );
  }

  Duration get dauer => bis.difference(von);
  bool laeuft(DateTime jetzt) => !jetzt.isBefore(von) && jetzt.isBefore(bis);
  bool vorbei(DateTime jetzt) => !bis.isAfter(jetzt);

  /// „Erika Muster (EG.1)“
  String get personText {
    final p = person ?? 'Reserviert';
    return wohnung == null ? p : '$p ($wohnung)';
  }
}

/// „2 Std. 30 Min.“
String dauerText(Duration d) {
  final h = d.inMinutes ~/ 60, m = d.inMinutes % 60;
  return [if (h > 0) '$h Std.', if (m > 0 || h == 0) '$m Min.'].join(' ');
}

/// Sperrzeit eines Raums (Reinigung, Wartung …) – GET /api/wasch/sperrzeiten.
/// In dieser Zeit lehnt die API jede Reservation ab.
class Sperrzeit {
  const Sperrzeit({required this.id, required this.raumId, required this.von, required this.bis, required this.grund, this.raumName});
  final int id;
  final int raumId;
  final DateTime von;
  final DateTime bis;
  final String grund;
  final String? raumName;

  static Sperrzeit? aus(Map<String, dynamic> j) {
    final von = zeitAus(j['start_time']);
    final bis = zeitAus(j['end_time']);
    if (von == null || bis == null) return null;
    return Sperrzeit(
      id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
      raumId: j['room_id'] is int ? j['room_id'] as int : int.tryParse('${j['room_id']}') ?? 0,
      von: von,
      bis: bis,
      grund: _text(j['grund']) ?? 'Gesperrt',
      raumName: _text(j['room_name']),
    );
  }
}

/// Reservation, die eine neue Sperrzeit stornieren wuerde (Vorschau der API).
class Betroffen {
  const Betroffen({required this.von, required this.bis, this.person, this.wohnung, this.woechentlich = false});
  final DateTime von;
  final DateTime bis;
  final String? person;
  final String? wohnung;
  final bool woechentlich;

  static Betroffen? aus(Map<String, dynamic> j) {
    final von = zeitAus(j['start_time']), bis = zeitAus(j['end_time']);
    if (von == null || bis == null) return null;
    return Betroffen(von: von, bis: bis, person: _text(j['user_name']), wohnung: _text(j['wohnung']), woechentlich: j['wiederkehrend'] == true);
  }
}

/// Einstellungen der Waschkueche – GET /api/wasch/settings (wirksame Werte).
class Einstellungen {
  const Einstellungen({this.preisProKwh = '0.30', this.maxTage = 90, this.maxOffen = 120, this.autoAbrechnung = true});
  final String preisProKwh;

  /// Reservieren hoechstens so viele Tage im Voraus (reservation_max_days).
  final int maxTage;

  /// Offene Reservationen je Person hoechstens (reservation_max_per_user).
  final int maxOffen;

  /// Am 1. um 08:00 den Vormonat abrechnen (auto_billing).
  final bool autoAbrechnung;

  factory Einstellungen.aus(Map<String, dynamic> j) {
    int ganz(Object? v, int d) {
      final n = int.tryParse('${v ?? ''}');
      return n != null && n > 0 ? n : d;
    }

    return Einstellungen(
      preisProKwh: _text(j['cost_per_kwh']) ?? '0.30',
      maxTage: ganz(j['reservation_max_days'], 90),
      maxOffen: ganz(j['reservation_max_per_user'], 120),
      autoAbrechnung: '${j['auto_billing'] ?? 'true'}' == 'true' || '${j['auto_billing']}' == '1',
    );
  }
}

/// Nutzung (Session) einer Maschine – GET /api/wasch/admin/sessions.
class Nutzung {
  const Nutzung({
    required this.id,
    this.beginn,
    this.person,
    this.wohnung,
    this.raumName,
    this.minuten,
    this.kwh,
    this.kosten,
    this.status,
  });

  final String id;
  final DateTime? beginn;
  final String? person;
  final String? wohnung;
  final String? raumName;
  final int? minuten;
  final double? kwh;
  final double? kosten;
  final String? status;

  factory Nutzung.aus(Map<String, dynamic> j) => Nutzung(
        id: '${j['id']}',
        beginn: zeitAus(j['started_at']),
        person: _text(j['name']),
        wohnung: _text(j['wohnung']),
        raumName: _text(j['room_name']),
        minuten: int.tryParse('${j['duration_minutes']}'),
        kwh: j['energy_consumed'] == null ? null : _zahl(j['energy_consumed']),
        kosten: j['cost'] == null ? null : _zahl(j['cost']),
        status: _text(j['status']),
      );

  String get statusText => switch (status) {
        'completed' => 'Abgeschlossen',
        'active' => 'Läuft',
        null => '–',
        _ => status!,
      };

  String get suchText => '${person ?? ''} ${wohnung ?? ''} ${raumName ?? ''}';
}

/// Kosten einer Person in einem Monat – GET /api/wasch/admin/costs.
class Kosten {
  const Kosten({required this.person, this.wohnung, required this.nutzungen, required this.minuten, required this.kwh, required this.betrag});
  final String person;
  final String? wohnung;
  final int nutzungen;
  final int minuten;
  final double kwh;
  final double betrag;

  factory Kosten.aus(Map<String, dynamic> j) => Kosten(
        person: _text(j['name']) ?? _text(j['email']) ?? '–',
        wohnung: _text(j['wohnung']),
        nutzungen: _zahl(j['sessions']).round(),
        minuten: _zahl(j['total_minutes']).round(),
        kwh: _zahl(j['total_kwh']),
        betrag: _zahl(j['total_cost']),
      );
}

/// Uebersicht fuer die Verwaltung – GET /api/wasch/admin/stats.
class Statistik {
  const Statistik({required this.raeume, required this.nutzungen, required this.kwh, required this.betrag, this.oben = const []});
  final int raeume;
  final int nutzungen;
  final double kwh;
  final double betrag;

  /// Die fuenf Personen mit den hoechsten Kosten.
  final List<Kosten> oben;

  factory Statistik.aus(Map<String, dynamic> j) => Statistik(
        raeume: _zahl(j['rooms']).round(),
        nutzungen: _zahl(j['total_sessions']).round(),
        kwh: _zahl(j['total_kwh']),
        betrag: _zahl(j['total_cost']),
        oben: [
          for (final u in j['top_users'] is List ? j['top_users'] as List : const [])
            if (u is Map<String, dynamic>)
              Kosten(
                person: _text(u['name']) ?? '–',
                wohnung: _text(u['wohnung']),
                nutzungen: _zahl(u['sessions']).round(),
                minuten: _zahl(u['minutes']).round(),
                kwh: 0,
                betrag: _zahl(u['cost']),
              ),
        ],
      );
}

/// Regeln der Reservation – wie POST /api/wasch/reservations prueft.
class Regeln {
  Regeln._();
  static const minDauer = Duration(minutes: 30);
  static const maxDauer = Duration(hours: 12);
  static const maxSerie = Duration(days: 366);

  /// Satz fuer die Person oder null (in Ordnung). [verwaltung] = Technik/
  /// Praesident: die API laesst Vergangenheit und weite Zukunft zu.
  /// [maxTage] aus den Einstellungen (reservation_max_days).
  static String? pruefen(DateTime von, DateTime bis,
      {required DateTime jetzt, bool verwaltung = false, DateTime? serieBis, int maxTage = 90, List<Sperrzeit> sperren = const []}) {
    if (!bis.isAfter(von)) return 'Das Ende muss nach dem Beginn liegen.';
    final d = bis.difference(von);
    if (d < minDauer) return 'Mindestens 30 Minuten.';
    if (d > maxDauer) return 'Höchstens 12 Stunden am Stück.';
    if (!verwaltung) {
      if (von.isBefore(jetzt.subtract(const Duration(minutes: 10)))) return 'Dieser Zeitpunkt ist schon vorbei.';
      if (von.isAfter(jetzt.add(Duration(days: maxTage)))) return 'Höchstens $maxTage Tage im Voraus.';
      if (serieBis != null && serieBis.isAfter(jetzt.add(maxSerie))) return 'Eine Serie geht höchstens ein Jahr voraus.';
    }
    if (serieBis != null && serieBis.isBefore(DateTime(von.year, von.month, von.day))) return 'Die Serie muss nach dem ersten Termin enden.';
    // nur der erste Termin; bei einer Serie laesst die API gesperrte Wochen aus
    for (final s in sperren) {
      if (s.von.isBefore(bis) && s.bis.isAfter(von)) return 'Gesperrt: ${s.grund}.';
    }
    return null;
  }
}
