// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../erinnerung.dart';
import '../stand.dart';

/// Neue Reservation (einmal oder jede Woche). true = reserviert.
///
/// Handy: ganze Seite; Computer: Dialog. [beginn] = angetippte Zeit im
/// Raster (Ende zwei Stunden spaeter, wie im Web).
Future<bool> reservierenDialog(
  BuildContext context, {
  required WaschStand stand,
  required Raum raum,
  DateTime? beginn,
  bool verwaltung = false,
  List<Sperrzeit> sperren = const [],
}) async {
  final seite = ReservierenSeite(stand: stand, raum: raum, beginn: beginn, verwaltung: verwaltung, sperren: sperren);
  final ok = Fensterklasse.von(context).istBreit
      ? await showDialog<bool>(
          context: context,
          builder: (_) => Dialog(
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720), child: seite),
          ),
        )
      : await Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => seite));
  return ok ?? false;
}

class ReservierenSeite extends StatefulWidget {
  const ReservierenSeite({super.key, required this.stand, required this.raum, this.beginn, this.verwaltung = false, this.sperren = const []});
  final WaschStand stand;
  final Raum raum;
  final DateTime? beginn;
  final bool verwaltung;

  /// Sperrzeiten der gezeigten Woche (Vorpruefung; die API prueft selbst).
  final List<Sperrzeit> sperren;

  @override
  State<ReservierenSeite> createState() => _ReservierenSeiteState();
}

class _ReservierenSeiteState extends State<ReservierenSeite> {
  late Raum _raum = widget.raum;
  late DateTime _tag;
  late TimeOfDay _von;
  late TimeOfDay _bis;
  bool _woechentlich = false;
  late DateTime _serieBis;

  DateTime get _jetzt => widget.stand.jetzt();

  @override
  void initState() {
    super.initState();
    final j = _jetzt;
    var b = widget.beginn;
    if (b == null) {
      // naechste volle Stunde, spaet abends morgen um 8
      final n = DateTime(j.year, j.month, j.day, j.hour + 1);
      b = n.hour >= 6 && n.hour <= 20 && n.day == j.day ? n : DateTime(j.year, j.month, j.day + 1, 8);
    }
    _tag = DateTime(b.year, b.month, b.day);
    _von = TimeOfDay(hour: b.hour, minute: b.minute);
    // zwei Stunden, hoechstens bis 22 Uhr (ausser es bliebe zu wenig)
    var e = b.add(const Duration(hours: 2));
    final spaet = DateTime(b.year, b.month, b.day, 22);
    if (e.isAfter(spaet) && spaet.difference(b) >= Regeln.minDauer) e = spaet;
    _bis = TimeOfDay(hour: e.hour, minute: e.minute);
    _serieBis = DateTime(_tag.year, _tag.month + 3, _tag.day);
  }

  DateTime _um(TimeOfDay z) => DateTime(_tag.year, _tag.month, _tag.day, z.hour, z.minute);
  DateTime get _beginn => _um(_von);

  /// Ende; 00:00 = Mitternacht am Ende des Tages.
  DateTime get _ende => _bis.hour == 0 && _bis.minute == 0 ? DateTime(_tag.year, _tag.month, _tag.day + 1) : _um(_bis);

  String? get _problem => Regeln.pruefen(_beginn, _ende,
      jetzt: _jetzt,
      verwaltung: widget.verwaltung,
      serieBis: _woechentlich ? _serieBis : null,
      maxTage: widget.stand.einstellungen.maxTage,
      sperren: [for (final s in widget.sperren) if (s.raumId == _raum.id) s]);

  Future<void> _speichern() async {
    final p = _problem;
    if (p != null) throw ApiFehler(400, p, null);
    final n = await widget.stand.api.reservieren(_raum.id, _beginn, _ende, serieBis: _woechentlich ? _serieBis : null);
    // Erlaubnis fuer die Erinnerung erst jetzt, wo es eine gibt (Android 13+, iOS, macOS)
    if (widget.stand.erinnerungen) unawaited(Benachrichtigung.erlaubnisFragen());
    if (!mounted) return;
    final zeit = '${uhrText(_beginn)}–${uhrText(_ende)}';
    zeigeMeldung(
      context,
      _woechentlich
          ? (n == 1 ? '1 Termin reserviert.' : '$n Termine reserviert (${wochentageLang[_beginn.weekday - 1]}s $zeit).')
          : 'Reserviert: ${tagWort(_beginn, _jetzt)} $zeit, ${_raum.name}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final raeume = widget.stand.raeume ?? [widget.raum];
    final heute = DateTime(_jetzt.year, _jetzt.month, _jetzt.day);
    final problem = _problem;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reservieren')),
      body: RosenwegFormular(
        speichernText: 'Reservieren',
        gespeichertText: null,
        fragenBeimVerlassen: false,
        speichern: _speichern,
        gespeichert: () => Navigator.of(context).pop(true),
        felder: [
          if (raeume.length > 1)
            AuswahlFeld<int>(
              titel: 'Waschküche',
              optionen: {for (final r in raeume) r.id: r.name},
              wert: _raum.id,
              geaendert: (v) => setState(() => _raum = raeume.firstWhere((r) => r.id == v, orElse: () => _raum)),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_laundry_service_outlined),
              title: Text(_raum.name),
              subtitle: _raum.ort == null ? null : Text(_raum.ort!),
            ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Einmal'), icon: Icon(Icons.event)),
              ButtonSegment(value: true, label: Text('Jede Woche'), icon: Icon(Icons.repeat)),
            ],
            selected: {_woechentlich},
            onSelectionChanged: (s) => setState(() => _woechentlich = s.first),
          ),
          DatumFeld(
            titel: _woechentlich ? 'Erster Termin' : 'Tag',
            wert: _tag,
            pflicht: true,
            erstes: widget.verwaltung ? DateTime(2020) : heute,
            letztes: widget.verwaltung ? DateTime(2100) : heute.add(Duration(days: widget.stand.einstellungen.maxTage)),
            geaendert: (v) => setState(() => _tag = v ?? _tag),
          ),
          Row(children: [
            Expanded(child: ZeitFeld(titel: 'Von', wert: _von, pflicht: true, geaendert: (v) => setState(() => _von = v ?? _von))),
            const SizedBox(width: 12),
            Expanded(child: ZeitFeld(titel: 'Bis', wert: _bis, pflicht: true, geaendert: (v) => setState(() => _bis = v ?? _bis))),
          ]),
          if (_woechentlich)
            DatumFeld(
              titel: 'Letzter Termin',
              wert: _serieBis,
              pflicht: true,
              erstes: _tag,
              letztes: widget.verwaltung ? DateTime(2100) : heute.add(Regeln.maxSerie),
              hinweis: 'Wochen, in denen die Zeit schon belegt ist, lässt die Serie aus.',
              geaendert: (v) => setState(() => _serieBis = v ?? _serieBis),
            ),
          Text(
            problem ?? 'Dauer: ${dauerText(_ende.difference(_beginn))}',
            style: t.textTheme.bodyMedium?.copyWith(color: problem == null ? t.colorScheme.onSurfaceVariant : t.colorScheme.error),
          ),
        ],
      ),
    );
  }
}
