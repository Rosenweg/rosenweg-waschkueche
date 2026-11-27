// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../app.dart';
import '../erinnerung.dart';
import '../stand.dart';
import '../wasch_api.dart';
import 'belegung.dart';
import 'reservation_ansicht.dart';
import 'meine.dart';
import 'verwalten.dart';

/// Seitenrecht der Verwaltung, wie im Portal (Rechteverwaltung).
const verwaltenRecht = 'waschküche-admin';

/// Die App nach der Anmeldung. Bereiche – auf dem Handy unten, am Computer
/// links:
///
///  * Belegung: Wochenraster des Raums, freie Zeit antippen = reservieren
///  * Meine: eigene kommende Reservationen, stornieren (auch ganze Serie)
///  * Verwalten (nur mit „waschküche-admin“ lesen; Technik/Praesident
///    immer): Uebersicht, Raeume, Nutzungen, Abrechnung, Preis
///
/// Erinnerung ohne Push: beim Oeffnen und bei jeder Rueckkehr in die App
/// fragt sie die eigenen Termine ab, jede Minute rechnet sie den Hinweis
/// oben neu, kurz vor Beginn kommt eine Meldung (solange die App offen ist).
class Haupt extends StatefulWidget {
  const Haupt({super.key, required this.sitzung, this.jetzt});
  final RosenwegSitzung sitzung;

  /// Fuer Tests und Bildschirmfotos; sonst die Uhr.
  final DateTime Function()? jetzt;

  @override
  State<Haupt> createState() => _HauptState();
}

class _HauptState extends State<Haupt> {
  late final WaschStand _stand = WaschStand(
    WaschApi(widget.sitzung.api),
    jetzt: widget.jetzt,
    // geteilte Telefone: die Person wechselt – keine Erinnerung fuer die vorige
    erinnerungen: !widget.sitzung.geteiltesTelefon && !attrappe,
  );
  StreamSubscription<String>? _angetippt;
  String _geplant = '';
  Timer? _uhr;
  AppLifecycleListener? _leben;
  int _minuten = 0;
  final _gemeldet = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.sitzung.rechte.laden().ignore();
      _stand.laden();
    });
    _stand.addListener(_meldenWennBald);
    _stand.addListener(_erinnerungenPlanen);
    _angetippt = Benachrichtigung.angetippt.listen(_oeffnen);
    Benachrichtigung.startZiel().then((z) {
      if (z != null) _oeffnen(z);
    });
    _uhr = Timer.periodic(const Duration(minutes: 1), (_) {
      // alle 5 Minuten die eigenen Termine neu (z. B. im Web storniert)
      if (++_minuten % 5 == 0) {
        _stand.meineLaden();
      } else {
        _stand.ticken();
      }
    });
    _leben = AppLifecycleListener(onResume: _stand.meineLaden);
  }

  @override
  void dispose() {
    _uhr?.cancel();
    _leben?.dispose();
    _stand.removeListener(_meldenWennBald);
    _stand.removeListener(_erinnerungenPlanen);
    _angetippt?.cancel();
    _stand.dispose();
    super.dispose();
  }

  /// Nach jeder Aenderung der eigenen Termine die Benachrichtigungen neu
  /// planen (nur wenn sich etwas geaendert hat, nicht bei jedem Ticken).
  Future<void> _erinnerungenPlanen() async {
    if (!_stand.erinnerungen || _stand.raeume == null) return;
    final zeichen = [for (final r in _stand.meine) '${r.id}@${r.von.millisecondsSinceEpoch}'].join(',');
    if (zeichen == _geplant) return;
    _geplant = zeichen;
    await Benachrichtigung.einrichten(appAngaben);
    await erinnerungenAbgleichen(_stand.meine, await AppSpeicher.app('hintergrund'), jetzt: _stand.jetzt());
  }

  /// Benachrichtigung angetippt (`meine/<id>`): die Reservation zeigen.
  Future<void> _oeffnen(String ziel) async {
    final id = int.tryParse(ziel.startsWith('meine/') ? ziel.substring(6) : '');
    if (id == null) return;
    if (_stand.raeume == null) await _stand.laden();
    final r = [for (final x in _stand.meine) if (x.id == id) x];
    if (r.isEmpty || !mounted) return;
    await zeigeReservation(context, stand: _stand, reservation: r.first, eigene: true);
  }

  /// Einmal je Termin: „In 10 Minuten: Waschküche 1, 14:00–16:00.“
  void _meldenWennBald() {
    final e = _stand.erinnerung;
    if (e == null || e.art != ErinnerungsArt.bald || !_gemeldet.add(e.reservation.id)) return;
    if (mounted) zeigeMeldung(context, e.text);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sitzung;
    return ListenableBuilder(
      listenable: s.rechte,
      builder: (context, _) {
        final r = s.rechte.stand;
        final verwalten = r?.zugriff(verwaltenRecht) ?? Zugriff.keiner;
        return RosenwegGeruest(
          titel: Text(s.app.name),
          logo: Padding(
            padding: const EdgeInsets.all(10),
            child: FarbLogo(sitzung: s, klein: true),
          ),
          // das Raster braucht die Breite (sieben Tage)
          maxBreite: 1100,
          aktionen: [_Menue(sitzung: s)],
          ziele: [
            GeruestZiel(
              titel: 'Belegung',
              symbol: Icons.calendar_view_week_outlined,
              gewaehltSymbol: Icons.calendar_view_week,
              seite: (_) => BelegungSeite(stand: _stand, verwaltung: r?.alles ?? false),
            ),
            GeruestZiel(
              titel: 'Meine',
              symbol: Icons.event_available_outlined,
              gewaehltSymbol: Icons.event_available,
              seite: (_) => MeineSeite(stand: _stand),
            ),
            if (verwalten.mindestens(Zugriff.lesen))
              GeruestZiel(
                titel: 'Verwalten',
                symbol: Icons.tune_outlined,
                gewaehltSymbol: Icons.tune,
                seite: (_) => VerwaltenSeite(
                  api: _stand.api,
                  schreiben: verwalten.mindestens(Zugriff.schreiben),
                  tuerEinstellen: r?.alles ?? false,
                  jetzt: widget.jetzt,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Menue oben rechts: Anmeldung (echter Stand), Ueber, Abmelden (nicht auf
/// geteilten Telefonen – dort meldet Rosenweg Geraet ab).
class _Menue extends StatelessWidget {
  const _Menue({required this.sitzung});
  final RosenwegSitzung sitzung;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Mehr',
        onSelected: (w) async {
          switch (w) {
            case 'anmeldung':
              await zeigeAnmeldung(context, sitzung);
            case 'ueber':
              await zeigeUeber(context, sitzung.app);
            case 'abmelden':
              if (await frage(context, 'Abmelden?', 'Danach musst du dich neu anmelden.', ja: 'Abmelden')) {
                // keine Erinnerungen und keine Abfrage mehr fuer diese Person
                await erinnerungenEntfernen(await AppSpeicher.app('hintergrund'));
                await HintergrundAbfrage.abmelden(sitzung.app);
                await sitzung.abmelden();
              }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'anmeldung', child: Text('Anmeldung: ${sitzung.name ?? 'angemeldet'}')),
          PopupMenuItem(value: 'ueber', child: Text('Über ${sitzung.app.name}')),
          if (!sitzung.geteiltesTelefon) const PopupMenuItem(value: 'abmelden', child: Text('Abmelden')),
        ],
      );
}

/// Hinweis oben: laufender oder naechster eigener Termin (bis 36 Stunden).
class ErinnerungsLeiste extends StatelessWidget {
  const ErinnerungsLeiste({super.key, required this.stand});
  final WaschStand stand;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: stand,
        builder: (context, _) {
          final e = stand.erinnerung;
          if (e == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Semantics(
              liveRegion: true,
              child: Hinweis(e.text, art: e.art == ErinnerungsArt.demnaechst ? HinweisArt.info : HinweisArt.gut),
            ),
          );
        },
      );
}
