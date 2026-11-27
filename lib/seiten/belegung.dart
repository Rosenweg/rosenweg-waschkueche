// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../stand.dart';
import 'buchen.dart';
import 'haupt.dart';
import 'reservation_ansicht.dart';

/// Belegung eines Raums als Wochenraster (wie waschkueche.html):
/// Raum waehlen (bei mehreren), Woche blaettern, freie Zeit antippen oder
/// „Reservieren“ = neue Reservation; Block antippen = Angaben, eigene
/// stornieren.
class BelegungSeite extends StatefulWidget {
  const BelegungSeite({super.key, required this.stand, this.verwaltung = false});
  final WaschStand stand;

  /// Technik/Praesident: die API laesst auch Vergangenes und weit Voraus zu.
  final bool verwaltung;

  @override
  State<BelegungSeite> createState() => _BelegungSeiteState();
}

class _BelegungSeiteState extends State<BelegungSeite> {
  late DateTime _montag = montagVon(widget.stand.jetzt());
  List<Reservation>? _belegung;
  Object? _fehler;
  bool _laedt = false;
  int? _geladenFuer;

  WaschStand get _s => widget.stand;

  @override
  void initState() {
    super.initState();
    _s.addListener(_standGeaendert);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _standGeaendert();
    });
  }

  @override
  void dispose() {
    _s.removeListener(_standGeaendert);
    super.dispose();
  }

  void _standGeaendert() {
    final raum = _s.raum;
    if (raum != null && raum.id != _geladenFuer && !_laedt) _laden();
    if (mounted) setState(() {});
  }

  Future<void> _laden() async {
    final raum = _s.raum;
    if (raum == null) return;
    final montag = _montag;
    setState(() {
      _laedt = true;
      _fehler = null;
      _geladenFuer = raum.id;
    });
    try {
      final l = await _s.api.belegung(raum.id, montag, DateTime(montag.year, montag.month, montag.day + 7));
      if (!mounted || montag != _montag || raum.id != _s.raum?.id) return;
      setState(() => _belegung = l);
    } catch (e) {
      if (mounted) setState(() => _fehler = e);
    } finally {
      if (mounted) setState(() => _laedt = false);
    }
  }

  Future<void> _alles() async {
    await Future.wait([_laden(), _s.meineLaden()]);
  }

  void _woche(DateTime m) {
    setState(() {
      _montag = m;
      _belegung = null;
    });
    _laden();
  }

  Future<void> _reservieren([DateTime? beginn]) async {
    final raum = _s.raum;
    if (raum == null) return;
    final ok = await reservierenDialog(context, stand: _s, raum: raum, beginn: beginn, verwaltung: widget.verwaltung);
    if (ok) await _alles();
  }

  Future<void> _zeigen(Reservation r) async {
    final geaendert = await zeigeReservation(context, stand: _s, reservation: r, eigene: _s.meineIds.contains(r.id));
    if (geaendert) await _alles();
  }

  @override
  Widget build(BuildContext context) {
    final raeume = _s.raeume;
    if (raeume == null) {
      return _s.fehler != null ? FehlerAnzeige.aus(_s.fehler!, nochmals: _s.laden) : const LadeAnzeige();
    }
    if (raeume.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: Hinweis('Für dich ist keine Waschküche eingerichtet. Reservieren können die Bewohnerinnen und Bewohner '
              'einer Stockwerkeigentümergemeinschaft mit Waschküche (heute STWEG 3, Rosenweg 9). '
              'Stimmt das nicht, melde dich bei der Technik.'),
        ),
      );
    }
    final raum = _s.raum!;
    final meine = _s.meineIds;
    final eintraege = [
      for (final r in _belegung ?? const <Reservation>[])
        RasterEintrag<Reservation>(
          von: r.von,
          bis: r.bis,
          titel: meine.contains(r.id) ? 'Du' : (r.person ?? 'Reserviert'),
          untertitel: meine.contains(r.id) ? null : r.wohnung,
          art: meine.contains(r.id) ? RasterArt.eigen : RasterArt.fremd,
          daten: r,
        ),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _reservieren(),
        icon: const Icon(Icons.add),
        label: const Text('Reservieren'),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ErinnerungsLeiste(stand: _s),
        if (raeume.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<int>(
              segments: [for (final r in raeume) ButtonSegment(value: r.id, label: Text(r.name))],
              selected: {raum.id},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                _s.raumWaehlen(s.first);
                setState(() => _belegung = null);
              },
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(raum.ort == null ? raum.name : '${raum.name} · ${raum.ort}', style: Theme.of(context).textTheme.titleSmall),
          ),
        WochenKopf(montag: _montag, geaendert: _woche, jetzt: _s.jetzt),
        SizedBox(height: 3, child: _laedt ? const LinearProgressIndicator() : null),
        if (_fehler != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(child: Hinweis(fehlerText(_fehler!), art: HinweisArt.fehler)),
              TextButton(onPressed: _laden, child: const Text('Nochmals')),
            ]),
          ),
        Expanded(
          child: Wochenraster<Reservation>(
            key: ValueKey('${raum.id}-$_montag'),
            montag: _montag,
            eintraege: eintraege,
            jetzt: _s.jetzt,
            leerGetippt: _reservieren,
            eintragGetippt: (e) => _zeigen(e.daten!),
          ),
        ),
      ]),
    );
  }
}
