// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:rosenweg_waschkueche/app.dart';
import 'package:rosenweg_waschkueche/attrappe.dart';
import 'package:rosenweg_waschkueche/daten.dart';
import 'package:rosenweg_waschkueche/erinnerung.dart';
import 'package:rosenweg_waschkueche/seiten/haupt.dart';

// Mittwoch, 25.11.2026, 10:20
final _jetzt = DateTime(2026, 11, 25, 10, 20);
DateTime _uhr() => _jetzt;

Reservation _r(int id, DateTime von, DateTime bis) => Reservation(id: id, raumId: 1, von: von, bis: bis, raumName: 'Waschküche 1');

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  Future<Attrappe> zeigen(WidgetTester t, Size groesse, {Attrappe? attrappe}) async {
    t.view.physicalSize = groesse;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final a = attrappe ?? Attrappe(jetzt: _uhr);
    final s = RosenwegSitzung(appAngaben, transport: a);
    await s.starten();
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => Haupt(sitzung: s, jetzt: _uhr)));
    await t.pumpAndSettle();
    return a;
  }

  group('Erinnerung', () {
    test('laeuft, gleich, demnaechst, zu weit weg', () {
      expect(Erinnerung.fuer([_r(1, DateTime(2026, 11, 25, 10), DateTime(2026, 11, 25, 12))], _jetzt)!.text,
          'Deine Reservation läuft: Waschküche 1 bis 12:00.');
      final bald = Erinnerung.fuer([_r(2, DateTime(2026, 11, 25, 10, 30), DateTime(2026, 11, 25, 12))], _jetzt)!;
      expect(bald.art, ErinnerungsArt.bald);
      expect(bald.text, 'In 10 Minuten: Waschküche 1, 10:30–12:00.');
      expect(Erinnerung.fuer([_r(3, DateTime(2026, 11, 26, 8), DateTime(2026, 11, 26, 10))], _jetzt)!.text,
          'Morgen 08:00–10:00: Waschküche 1.');
      expect(Erinnerung.fuer([_r(4, DateTime(2026, 11, 28, 8), DateTime(2026, 11, 28, 10))], _jetzt), isNull);
      // vorbei zaehlt nicht, der naechste schon
      expect(
          Erinnerung.fuer([
            _r(5, DateTime(2026, 11, 25, 7), DateTime(2026, 11, 25, 9)),
            _r(6, DateTime(2026, 11, 25, 18), DateTime(2026, 11, 25, 20)),
          ], _jetzt)!
              .text,
          'Heute 18:00–20:00: Waschküche 1.');
    });

    test('Tagwort', () {
      expect(tagWort(DateTime(2026, 11, 27, 9), _jetzt), 'Übermorgen');
      expect(tagWort(DateTime(2026, 11, 30, 9), _jetzt), 'Mo 30.11.');
    });
  });

  test('Regeln wie die API', () {
    DateTime h(int t, int s, [int m = 0]) => DateTime(2026, 11, t, s, m);
    expect(Regeln.pruefen(h(25, 12), h(25, 14), jetzt: _jetzt), isNull);
    expect(Regeln.pruefen(h(25, 12), h(25, 12, 20), jetzt: _jetzt), 'Mindestens 30 Minuten.');
    expect(Regeln.pruefen(h(25, 12), h(25, 11), jetzt: _jetzt), 'Das Ende muss nach dem Beginn liegen.');
    expect(Regeln.pruefen(h(25, 6), h(25, 19), jetzt: _jetzt), 'Höchstens 12 Stunden am Stück.');
    expect(Regeln.pruefen(h(24, 8), h(24, 10), jetzt: _jetzt), 'Dieser Zeitpunkt ist schon vorbei.');
    expect(Regeln.pruefen(h(24, 8), h(24, 10), jetzt: _jetzt, verwaltung: true), isNull);
    expect(Regeln.pruefen(DateTime(2027, 3, 1, 8), DateTime(2027, 3, 1, 10), jetzt: _jetzt), 'Höchstens 90 Tage im Voraus.');
    expect(apiZeit(DateTime(2026, 11, 5, 8, 0)), '2026-11-05T08:00:00');
  });

  testWidgets('Handy: Belegung mit eigener Reservation, Erinnerung oben, Meine', (t) async {
    await zeigen(t, const Size(412, 860));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Verwalten'), findsOneWidget);
    // eigene heute 12:00–14:00 (in zwei Stunden), fremde heute 07:00–08:30
    expect(find.text('Heute 12:00–14:00: Waschküche 1.'), findsOneWidget);
    expect(find.text('12:00–14:00'), findsOneWidget);
    expect(find.text('Du'), findsOneWidget);
    expect(find.text('07:00–08:30'), findsOneWidget);

    await t.tap(find.text('Meine'));
    await t.pumpAndSettle();
    expect(find.text('12:00–14:00 · Waschküche 1'), findsOneWidget);
    expect(find.text('09:00–11:00 · Waschküche 1'), findsWidgets);
    expect(find.textContaining('jede Woche'), findsWidgets);
  });

  testWidgets('Fremde Reservation: Angaben mit Person, ohne Stornieren', (t) async {
    await zeigen(t, const Size(412, 860));
    // beim Oeffnen steht 09:00 oben (eine Stunde vor jetzt): hinauf scrollen
    await t.ensureVisible(find.text('07:00–08:30'));
    await t.pumpAndSettle();
    await t.tap(find.text('07:00–08:30'));
    await t.pumpAndSettle();
    expect(find.text('Lea Probe (2.OG rechts)'), findsOneWidget);
    expect(find.text('Stornieren'), findsNothing);
  });

  testWidgets('Reservieren: freie Zeit antippen, Formular schickt Ortszeit', (t) async {
    final a = await zeigen(t, const Size(412, 860));
    await t.tap(find.text('Reservieren'));
    await t.pumpAndSettle();
    // naechste volle Stunde (11:00) bis 13:00 – ueberschneidet die eigene ab 12:00
    expect(find.text('Dauer: 2 Std.'), findsOneWidget);
    await t.tap(find.byKey(const Key('formular-speichern')));
    await t.pumpAndSettle();
    expect(find.text('Zeitraum überschneidet sich mit bestehender Reservierung'), findsOneWidget);
    final post = a.anfragen.lastWhere((r) => r.methode == 'POST');
    expect(post.koerper, {'room_id': 1, 'start_time': '2026-11-25T11:00:00', 'end_time': '2026-11-25T13:00:00'});

    // jede Woche: belegte Wochen faellt die Serie aus, der Rest kommt
    await t.tap(find.text('Jede Woche'));
    await t.pumpAndSettle();
    expect(find.text('Letzter Termin *'), findsOneWidget);
    await t.tap(find.byKey(const Key('formular-speichern')));
    await t.pumpAndSettle();
    expect(find.text('Reservieren'), findsOneWidget, reason: 'Seite zu, FAB wieder da');
    expect(find.textContaining('Termine reserviert (Mittwochs 11:00–13:00)'), findsOneWidget);
    final serie = a.anfragen.lastWhere((r) => r.methode == 'POST').koerper as Map;
    expect(serie['recurring'], isTrue);
    expect(serie['recurring_until'], '2027-02-25');
  });

  testWidgets('Stornieren in Meine fragt nach', (t) async {
    final a = await zeigen(t, const Size(412, 860));
    await t.tap(find.text('Meine'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Stornieren').first);
    await t.pumpAndSettle();
    expect(find.text('Reservation stornieren?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Stornieren'));
    await t.pumpAndSettle();
    expect(a.anfragen.any((r) => r.methode == 'DELETE' && r.pfad == '/api/wasch/reservations/1'), isTrue);
    expect(find.text('Reservation storniert.'), findsOneWidget);
    expect(find.text('12:00–14:00 · Waschküche 1'), findsNothing);
  });

  testWidgets('Ohne Recht waschküche-admin: kein Verwalten', (t) async {
    await zeigen(t, const Size(412, 860), attrappe: Attrappe(jetzt: _uhr, rechte: const {}, gruppen: const ['stweg3-bewohner']));
    expect(find.text('Belegung'), findsWidgets);
    expect(find.text('Verwalten'), findsNothing);
  });

  testWidgets('Nur lesen: Verwalten ohne Aendern', (t) async {
    await zeigen(t, const Size(412, 860), attrappe: Attrappe(jetzt: _uhr, rechte: const {'waschküche-admin': 'read'}));
    await t.tap(find.text('Verwalten'));
    await t.pumpAndSettle();
    expect(find.textContaining('Nur ansehen'), findsOneWidget);
    expect(find.text('Max Beispiel'), findsOneWidget);
    await t.tap(find.text('Räume'));
    await t.pumpAndSettle();
    expect(find.text('Waschküche 2'), findsOneWidget);
    expect(find.text('Raum hinzufügen'), findsNothing);
  });

  testWidgets('Verwalten: Abrechnung fuer jeden vergangenen Monat, doppelt gesperrt', (t) async {
    final a = await zeigen(t, const Size(1280, 860));
    expect(find.byType(NavigationRail), findsOneWidget);
    await t.tap(find.text('Verwalten'));
    await t.pumpAndSettle();
    await t.tap(find.text('Abrechnung'));
    await t.pumpAndSettle();
    // Standard: Vormonat
    expect(find.text('Oktober 2026'), findsOneWidget);
    await t.tap(find.byTooltip('Voriger Monat'));
    await t.pumpAndSettle();
    await t.tap(find.text('Abrechnung September 2026 per E-Mail senden'));
    await t.pumpAndSettle();
    expect(find.text('Abrechnung September 2026 senden?'), findsOneWidget);
    await t.tap(find.text('Senden'));
    await t.pumpAndSettle();
    expect(a.anfragen.lastWhere((r) => r.pfad == '/api/wasch/admin/billing/run').koerper, {'month': '2026-09'});
    expect(find.text('Abrechnung 2026-09: 2 Personen'), findsOneWidget);
    // nochmals: die API lehnt ab, der Satz steht da
    await t.tap(find.text('Abrechnung September 2026 per E-Mail senden'));
    await t.pumpAndSettle();
    await t.tap(find.text('Senden'));
    await t.pumpAndSettle();
    expect(find.text('2026-09 ist schon abgerechnet'), findsOneWidget);
    // laufender Monat: kein Knopf
    await t.tap(find.byTooltip('Nächster Monat'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Nächster Monat'));
    await t.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.textContaining('per E-Mail senden'), findsNothing);
  });

  testWidgets('Sperrzeit: grau im Raster mit Grund', (t) async {
    final a = await zeigen(t, const Size(412, 860));
    await t.ensureVisible(find.text('Do 26.'));
    await t.pumpAndSettle();
    await t.tap(find.text('Do 26.'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Reinigung'));
    await t.pumpAndSettle();
    expect(find.text('Gesperrt'), findsOneWidget);
    await t.tap(find.text('Reinigung'));
    await t.pumpAndSettle();
    expect(find.textContaining('Gesperrt Donnerstag, 26.11.2026 07:00 bis 10:00: Reinigung.'), findsOneWidget);
    expect(a.anfragen.where((r) => r.pfad.startsWith('/api/wasch/sperrzeiten?room_id=1')).isNotEmpty, isTrue);
  });

  testWidgets('Verwalten: Sperrzeit anlegen und Einstellungen speichern', (t) async {
    final a = await zeigen(t, const Size(412, 860));
    await t.tap(find.text('Verwalten'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sperrzeiten'));
    await t.pumpAndSettle();
    expect(find.text('Reinigung'), findsOneWidget);
    // eine Reservation morgen 10–11 Uhr, die die Sperrzeit trifft
    await a.senden('POST', '/api/wasch/reservations', koerper: {'room_id': 1, 'start_time': '2026-11-26T10:00:00', 'end_time': '2026-11-26T11:00:00'});
    await t.tap(find.text('Sperren'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Grund *'), 'Wartung Trockner');
    await t.tap(find.byKey(const Key('formular-speichern')));
    // der Knopf dreht, solange die Rueckfrage offen ist: nicht auf Ruhe warten
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    // Vorschau: wen es trifft, nachfragen
    expect(find.text('1 Reservation stornieren?'), findsOneWidget);
    expect(find.text('Erika Muster (EG.1)'), findsOneWidget);
    await t.tap(find.text('Sperren und stornieren'));
    await t.pumpAndSettle();
    final posts = [for (final r in a.anfragen) if (r.methode == 'POST' && r.pfad == '/api/wasch/sperrzeiten') r.koerper as Map];
    expect(posts.first['vorschau'], isTrue);
    expect(posts.last, {'room_id': 1, 'start_time': '2026-11-26T08:00:00', 'end_time': '2026-11-26T12:00:00', 'grund': 'Wartung Trockner', 'bestaetigt': true});
    expect(find.text('Wartung Trockner'), findsOneWidget);

    await t.ensureVisible(find.text('Einstellungen'));
    await t.pumpAndSettle();
    await t.tap(find.text('Einstellungen'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Reservieren höchstens so viele Tage im Voraus *'), '30');
    await t.tap(find.text('Automatisch abrechnen'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('formular-speichern')));
    await t.pumpAndSettle();
    final put = a.anfragen.lastWhere((r) => r.methode == 'PUT' && r.pfad == '/api/wasch/settings').koerper as Map;
    expect(put, {'cost_per_kwh': '0.30', 'reservation_max_days': 30, 'reservation_max_per_user': 120, 'auto_billing': false});
  });

  testWidgets('Verwalten: Modul Waschküche je STWEG schalten (nur Ausschuss-STWEG)', (t) async {
    final a = await zeigen(t, const Size(412, 860));
    await t.tap(find.text('Verwalten'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Modul'));
    await t.tap(find.text('Modul'));
    await t.pumpAndSettle();
    expect(find.text('STWEG 3'), findsOneWidget);
    expect(find.text('STWEG 5'), findsNothing);
    await t.tap(find.text('STWEG 3'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ausschalten'));
    await t.pumpAndSettle();
    final post = a.anfragen.lastWhere((r) => r.methode == 'POST' && r.pfad == '/api/stweg-modules').koerper as Map;
    expect(post, {'stweg': 3, 'module': 'waschkueche', 'active': false});
  });

  test('Regeln: Tage aus den Einstellungen, Sperrzeit', () {
    final s = Sperrzeit(id: 1, raumId: 1, von: DateTime(2026, 11, 26, 7), bis: DateTime(2026, 11, 26, 10), grund: 'Reinigung');
    expect(Regeln.pruefen(DateTime(2026, 12, 30, 8), DateTime(2026, 12, 30, 10), jetzt: _jetzt, maxTage: 30), 'Höchstens 30 Tage im Voraus.');
    expect(Regeln.pruefen(DateTime(2026, 11, 26, 9), DateTime(2026, 11, 26, 11), jetzt: _jetzt, sperren: [s]), 'Gesperrt: Reinigung.');
    expect(Regeln.pruefen(DateTime(2026, 11, 26, 10), DateTime(2026, 11, 26, 12), jetzt: _jetzt, sperren: [s]), isNull);
    expect(Einstellungen.aus({'reservation_max_days': '30', 'auto_billing': 'false'}).maxTage, 30);
    expect(Einstellungen.aus(const {}).autoAbrechnung, isTrue);
  });

  testWidgets('Technik: Tuer einstellbar; Ausschuss nicht', (t) async {
    await zeigen(t, const Size(412, 860));
    await t.tap(find.text('Verwalten'));
    await t.pumpAndSettle();
    await t.tap(find.text('Räume'));
    await t.pumpAndSettle();
    await t.tap(find.text('Waschküche 2'));
    await t.pumpAndSettle();
    expect(find.text('Die Tür stellt die Technik ein.'), findsOneWidget);
  });

  testWidgets('Ohne Waschkueche: verstaendlicher Hinweis', (t) async {
    await zeigen(t, const Size(412, 860), attrappe: Attrappe(jetzt: _uhr, rechte: const {}, ohneRaeume: true));
    expect(find.textContaining('Für dich ist keine Waschküche eingerichtet'), findsOneWidget);
  });

  test('Kennung, Ordner und Logo passen zusammen', () {
    expect(appAngaben.kennung, 'ch.rosenweg4303.waschkueche');
    expect(appAngaben.gruppe, RosenwegGruppe.bewohner);
    expect(File('assets/logo/${appAngaben.ordner}-512.png').existsSync(), isTrue);
    expect(File('assets/logo/${appAngaben.ordner}-klein.png').existsSync(), isTrue);
  });
}
