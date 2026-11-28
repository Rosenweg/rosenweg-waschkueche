// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Antwortet wie die Haupt-API (/api/wasch/*, /api/auth/me), mit erfundenen
/// Daten (keine echten Personen, keine echten Reservationen). Fuer Tests,
/// Bildschirmfotos und Entwicklung ohne Server (--dart-define=RW_ATTRAPPE=1).
///
/// Angemeldet ist „Erika Muster“ (STWEG 3). Standard: darf reservieren und
/// verwalten (`waschküche-admin` schreiben); Tests setzen [rechte] und
/// [gruppen] anders (ohne Recht, nur lesen, Technik).
class Attrappe implements Transport {
  Attrappe({
    this.gruppen = const ['stweg3-eigentuemer', 'stweg3-ausschuss'],
    this.rechte = const {'waschküche-admin': 'write'},
    this.ohneRaeume = false,
    DateTime Function()? jetzt,
  }) : jetzt = jetzt ?? DateTime.now {
    _vorbereiten();
  }

  final List<String> gruppen;
  final Map<String, String> rechte;

  /// Person ohne Waschkueche (z. B. andere STWEG).
  final bool ohneRaeume;
  final DateTime Function() jetzt;

  /// Alle Anfragen in der Reihenfolge (fuer Tests).
  final anfragen = <({String methode, String pfad, Object? koerper})>[];

  /// Naechste Antwort fuer einen Pfad (ohne Abfrage) erzwingen (Tests):
  /// `erzwungen['DELETE /api/wasch/reservations/3'] = (status: 503, json: null);`
  final erzwungen = <String, ApiAntwort>{};

  static const ich = 7;
  static const _personen = {
    7: ('Erika Muster', 'EG.1'),
    8: ('Max Beispiel', '1.OG links'),
    9: ('Lea Probe', '2.OG rechts'),
  };

  final _raeume = <Map<String, dynamic>>[
    {'id': 1, 'name': 'Waschküche 1', 'location': 'UG links', 'stweg': 3, 'energy_meter_id': 'shelly-wasch1', 'unifi_door_id': null, 'active': true},
    {'id': 2, 'name': 'Waschküche 2', 'location': 'UG rechts', 'stweg': 3, 'energy_meter_id': null, 'unifi_door_id': 'door-beispiel', 'active': true},
  ];
  final _reservationen = <Map<String, dynamic>>[];
  final _einstellungen = <String, String>{
    'cost_per_kwh': '0.30',
    'reservation_max_days': '90',
    'reservation_max_per_user': '120',
    'auto_billing': 'true',
  };
  final _sperrzeiten = <Map<String, dynamic>>[];
  final _abgerechnet = <String>{};
  var _naechste = 1;

  DateTime _tag(int plus, int stunde, [int minute = 0]) {
    final j = jetzt();
    return DateTime(j.year, j.month, j.day + plus, stunde, minute);
  }

  void _anlegen(int user, int raum, DateTime von, DateTime bis, {DateTime? serieBis}) => _reservationen.add({
        'id': _naechste++,
        'user_id': user,
        'room_id': raum,
        'start_time': von.toUtc().toIso8601String(),
        'end_time': bis.toUtc().toIso8601String(),
        'recurring': serieBis != null,
        'recurring_until': serieBis?.toUtc().toIso8601String(),
        'cancelled': false,
      });

  /// Belegung rund um heute: eigene heute in zwei Stunden und uebermorgen
  /// (jede Woche, vier Mal), fremde gestern, heute frueh und morgen.
  void _vorbereiten() {
    final j = jetzt();
    final inZwei = DateTime(j.year, j.month, j.day, j.hour + 2);
    _anlegen(ich, 1, inZwei, inZwei.add(const Duration(hours: 2)));
    for (var w = 0; w < 4; w++) {
      _anlegen(ich, 1, _tag(2 + 7 * w, 9), _tag(2 + 7 * w, 11), serieBis: _tag(23, 0));
    }
    _anlegen(8, 1, _tag(-1, 14), _tag(-1, 16, 30));
    _anlegen(9, 1, _tag(0, 7), _tag(0, 8, 30));
    _anlegen(8, 1, _tag(1, 18), _tag(1, 20));
    _anlegen(9, 2, _tag(1, 10), _tag(1, 12));
    // morgen frueh Reinigung in Waschkueche 1
    _sperrzeiten.add({
      'id': 1,
      'room_id': 1,
      'start_time': _tag(1, 7).toUtc().toIso8601String(),
      'end_time': _tag(1, 10).toUtc().toIso8601String(),
      'grund': 'Reinigung',
    });
  }

  Map<String, dynamic> _mitNamen(Map<String, dynamic> r) {
    final p = _personen[r['user_id']];
    final raum = _raeume.firstWhere((x) => x['id'] == r['room_id']);
    return {...r, 'user_name': p?.$1, 'wohnung': p?.$2, 'room_name': raum['name']};
  }

  DateTime _z(Object? v) => DateTime.parse('$v').toLocal();

  bool get _admin => gruppen.any((g) => const {'technik', 'präsident', 'praesident'}.contains(g));

  bool _modulAn = true;

  bool get _darfVerwalten => _admin || rechte['waschküche-admin'] == 'read' || rechte['waschküche-admin'] == 'write';
  bool get _darfAendern => _admin || rechte['waschküche-admin'] == 'write';

  static const _keinRecht = (status: 403, json: {'error': 'Kein Recht „Waschküche-Admin“'});
  static const _nurLesen = (status: 403, json: {'error': 'Nur ansehen: Ändern braucht das Recht „Waschküche-Admin“ mit Schreibrecht'});

  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    anfragen.add((methode: methode, pfad: pfad, koerper: koerper));
    final u = Uri.parse(pfad);
    final z = erzwungen.remove('$methode ${u.path}');
    if (z != null) return z;
    final k = koerper is Map ? koerper.cast<String, dynamic>() : const <String, dynamic>{};
    final offen = _reservationen.where((r) => r['cancelled'] != true);
    final weg = '$methode ${u.path}';

    if (weg.contains('/api/wasch/admin/') && !_darfVerwalten) return _keinRecht;
    if ((weg == 'POST /api/wasch/admin/billing/run' || weg == 'PUT /api/wasch/settings' || weg.startsWith('POST /api/wasch/rooms') ||
            weg.startsWith('PUT /api/wasch/rooms')) &&
        !_darfAendern) {
      return _darfVerwalten ? _nurLesen : _keinRecht;
    }

    switch (weg) {
      case 'GET /api/auth/me':
        return (
          status: 200,
          json: {
            'user': {
              'id': ich,
              'name': 'Erika Muster',
              'email': 'erika.muster@example.org',
              'wohnung': 'EG.1',
              'stweg': '3',
              'groups': gruppen,
              'permissions': rechte,
            },
          },
        );
      case 'GET /api/stweg/meine':
        return (status: 200, json: {'stwegs': [{'nr': 3, 'name': 'STWEG 3', 'rollen': ['eigentuemer', 'ausschuss']}, {'nr': 5, 'name': 'STWEG 5', 'rollen': ['bewohner']}]});
      case 'GET /api/stweg-modules':
        return (status: 200, json: {'3': _modulAn ? ['waschkueche'] : <String>[]});
      case 'POST /api/stweg-modules':
        _modulAn = k['active'] == true;
        return (status: 200, json: {'ok': true});
      case 'GET /api/wasch/rooms':
        return (status: 200, json: ohneRaeume ? <Object>[] : _raeume.where((r) => r['active'] == true).toList());
      case 'POST /api/wasch/rooms':
        final neu = <String, dynamic>{'id': _raeume.length + 1, 'active': true, ...k};
        _raeume.add(neu);
        return (status: 200, json: neu);
      case 'GET /api/wasch/reservations':
        final raum = int.tryParse(u.queryParameters['room_id'] ?? '');
        final von = DateTime.tryParse(u.queryParameters['from'] ?? '');
        final bis = DateTime.tryParse(u.queryParameters['to'] ?? '');
        return (
          status: 200,
          json: [
            for (final r in offen)
              if ((raum == null || r['room_id'] == raum) &&
                  (von == null || !_z(r['end_time']).isBefore(von)) &&
                  (bis == null || !_z(r['start_time']).isAfter(bis)))
                _mitNamen(r),
          ],
        );
      case 'GET /api/wasch/my/reservations':
        final j = jetzt();
        return (
          status: 200,
          json: [for (final r in offen) if (r['user_id'] == ich && _z(r['end_time']).isAfter(j)) _mitNamen(r)..remove('user_name')],
        );
      case 'POST /api/wasch/reservations':
        final von = DateTime.parse('${k['start_time']}');
        final bis = DateTime.parse('${k['end_time']}');
        final raum = k['room_id'] as int;
        bool frei(DateTime a, DateTime b) =>
            !offen.any((r) => r['room_id'] == raum && _z(r['start_time']).isBefore(b) && _z(r['end_time']).isAfter(a));
        if (k['recurring'] == true) {
          final ende = DateTime.parse('${k['recurring_until']}');
          var n = 0;
          for (var a = von, b = bis; !a.isAfter(ende); a = a.add(const Duration(days: 7)), b = b.add(const Duration(days: 7))) {
            if (frei(a, b)) {
              _anlegen(ich, raum, a, b, serieBis: ende);
              n++;
            }
          }
          return (status: 200, json: {'created': n, 'reservations': <Object>[]});
        }
        if (!frei(von, bis)) return (status: 409, json: {'error': 'Zeitraum überschneidet sich mit bestehender Reservierung'});
        final sp = _sperrzeiten.where((x) => x['room_id'] == raum && _z(x['start_time']).isBefore(bis) && _z(x['end_time']).isAfter(von));
        if (sp.isNotEmpty) return (status: 409, json: {'error': 'Gesperrt: ${sp.first['grund']}', 'sperrzeit': true});
        _anlegen(ich, raum, von, bis);
        return (status: 200, json: _reservationen.last);
      case 'GET /api/wasch/settings':
        return (status: 200, json: _einstellungen);
      case 'PUT /api/wasch/settings':
        for (final e in k.entries) {
          if (_einstellungen.containsKey(e.key)) _einstellungen[e.key] = '${e.value}';
        }
        return (status: 200, json: {'success': true});
      case 'GET /api/wasch/sperrzeiten':
        final raum = int.tryParse(u.queryParameters['room_id'] ?? '');
        final von = DateTime.tryParse(u.queryParameters['from'] ?? '');
        final bis = DateTime.tryParse(u.queryParameters['to'] ?? '');
        final j = jetzt();
        return (
          status: 200,
          json: [
            for (final x in _sperrzeiten)
              if ((raum == null || x['room_id'] == raum) &&
                  (von == null ? _z(x['end_time']).isAfter(j) : !_z(x['end_time']).isBefore(von)) &&
                  (bis == null || !_z(x['start_time']).isAfter(bis)))
                {...x, 'room_name': _raeume.firstWhere((r) => r['id'] == x['room_id'])['name']},
          ],
        );
      case 'POST /api/wasch/sperrzeiten':
        if (!_darfAendern) return _darfVerwalten ? _nurLesen : _keinRecht;
        if ('${k['grund'] ?? ''}'.trim().isEmpty) return (status: 400, json: {'error': 'Bitte einen Grund angeben', 'feld': 'grund'});
        final von = DateTime.parse('${k['start_time']}'), bis = DateTime.parse('${k['end_time']}');
        final treffer = [
          for (final r in offen)
            if (r['room_id'] == k['room_id'] && _z(r['start_time']).isBefore(bis) && _z(r['end_time']).isAfter(von)) r,
        ];
        final betroffen = [
          for (final r in treffer)
            {
              'id': r['id'],
              'start_time': r['start_time'],
              'end_time': r['end_time'],
              'wiederkehrend': r['recurring'] == true,
              'user_name': _personen[r['user_id']]?.$1,
              'wohnung': _personen[r['user_id']]?.$2,
            },
        ];
        if (k['vorschau'] == true) return (status: 200, json: {'vorschau': true, 'betroffen': betroffen});
        if (treffer.isNotEmpty && k['bestaetigt'] != true) {
          return (status: 409, json: {'error': 'Bitte bestätigen', 'bestaetigung_noetig': true, 'betroffen': betroffen});
        }
        _sperrzeiten.add({
          'id': _sperrzeiten.length + 10,
          'room_id': k['room_id'],
          'start_time': von.toUtc().toIso8601String(),
          'end_time': bis.toUtc().toIso8601String(),
          'grund': '${k['grund']}'.trim(),
        });
        for (final r in treffer) {
          r['cancelled'] = true;
        }
        final personen = {for (final r in treffer) r['user_id']};
        return (status: 200, json: {..._sperrzeiten.last, 'storniert': treffer.length, 'benachrichtigt': personen.length, 'betroffen': betroffen});
      case 'GET /api/wasch/admin/stats':
        return (
          status: 200,
          json: {
            'rooms': 2,
            'total_sessions': '14',
            'total_kwh': '23.40',
            'total_minutes': '1260',
            'total_cost': '7.02',
            'top_users': [
              {'name': 'Max Beispiel', 'wohnung': '1.OG links', 'sessions': '6', 'minutes': '540', 'cost': '3.10'},
              {'name': 'Erika Muster', 'wohnung': 'EG.1', 'sessions': '5', 'minutes': '450', 'cost': '2.52'},
              {'name': 'Lea Probe', 'wohnung': '2.OG rechts', 'sessions': '3', 'minutes': '270', 'cost': '1.40'},
            ],
          },
        );
      case 'GET /api/wasch/admin/sessions':
        final b = _tag(-3, 9);
        return (
          status: 200,
          json: [
            {'id': 2, 'name': 'Max Beispiel', 'wohnung': '1.OG links', 'room_name': 'Waschküche 1', 'started_at': b.toUtc().toIso8601String(),
             'duration_minutes': 95, 'energy_consumed': '1.82', 'cost': '0.55', 'status': 'completed'},
            {'id': 1, 'name': 'Erika Muster', 'wohnung': 'EG.1', 'room_name': 'Waschküche 2',
             'started_at': b.subtract(const Duration(days: 2)).toUtc().toIso8601String(),
             'duration_minutes': 80, 'energy_consumed': '1.40', 'cost': '0.42', 'status': 'completed'},
          ],
        );
      case 'GET /api/wasch/admin/costs':
        return (
          status: 200,
          json: [
            {'name': 'Max Beispiel', 'wohnung': '1.OG links', 'email': 'max.beispiel@example.org', 'sessions': '3', 'total_kwh': '5.10',
             'total_minutes': '270', 'total_cost': '1.53'},
            {'name': 'Erika Muster', 'wohnung': 'EG.1', 'email': 'erika.muster@example.org', 'sessions': '2', 'total_kwh': '2.80',
             'total_minutes': '160', 'total_cost': '0.84'},
          ],
        );
      case 'POST /api/wasch/admin/billing/run':
        final j = jetzt();
        final m = '${k['month'] ?? ''}';
        final laufend = '${j.year}-${j.month.toString().padLeft(2, '0')}';
        if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(m) || m.compareTo(laufend) >= 0) {
          return (status: 400, json: {'error': 'Abrechnen geht nur für vergangene Monate', 'feld': 'month'});
        }
        if (!_abgerechnet.add(m)) return (status: 409, json: {'error': '$m ist schon abgerechnet'});
        return (status: 200, json: {'success': true, 'month': m, 'anzahl': 2, 'message': 'Abrechnung $m: 2 Personen'});
    }

    // /api/wasch/rooms/:id, /api/wasch/reservations/:id[/series]
    final teile = u.pathSegments;
    if (methode == 'PUT' && teile.length == 4 && teile[2] == 'rooms') {
      final r = _raeume.firstWhere((x) => '${x['id']}' == teile[3], orElse: () => <String, dynamic>{});
      if (r.isEmpty) return (status: 404, json: {'error': 'Raum nicht gefunden'});
      if (!_admin && '${k['unifi_door_id'] ?? ''}' != '${r['unifi_door_id'] ?? ''}') {
        return (status: 403, json: {'error': 'Das Türschloss stellt die Technik ein'});
      }
      r.addAll(k);
      return (status: 200, json: r);
    }
    if (methode == 'DELETE' && teile.length == 4 && teile[2] == 'sperrzeiten') {
      if (!_darfAendern) return _darfVerwalten ? _nurLesen : _keinRecht;
      final vorher = _sperrzeiten.length;
      _sperrzeiten.removeWhere((x) => '${x['id']}' == teile[3]);
      return vorher == _sperrzeiten.length ? (status: 404, json: {'error': 'Sperrzeit nicht gefunden'}) : (status: 200, json: {'success': true});
    }
    if (methode == 'DELETE' && teile.length >= 4 && teile[2] == 'reservations') {
      final r = _reservationen.firstWhere((x) => '${x['id']}' == teile[3] && x['cancelled'] != true, orElse: () => <String, dynamic>{});
      if (r.isEmpty || (r['user_id'] != ich && !_admin)) return (status: 404, json: {'error': 'Reservierung nicht gefunden'});
      if (teile.length == 5 && teile[4] == 'series') {
        final j = jetzt();
        var n = 0;
        for (final x in _reservationen) {
          if (x['cancelled'] != true &&
              x['recurring'] == true &&
              x['user_id'] == r['user_id'] &&
              x['recurring_until'] == r['recurring_until'] &&
              !_z(x['start_time']).isBefore(j)) {
            x['cancelled'] = true;
            n++;
          }
        }
        return (status: 200, json: {'success': true, 'cancelled': n});
      }
      r['cancelled'] = true;
      return (status: 200, json: {'success': true});
    }
    return (status: 404, json: {'error': 'Nicht gefunden: $methode $pfad'});
  }
}
