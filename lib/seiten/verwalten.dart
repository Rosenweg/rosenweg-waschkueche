// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../wasch_api.dart';

/// Verwaltung (wie stweg3/pages/waschkueche-admin.html): Uebersicht,
/// Raeume, Sperrzeiten, Nutzungen, Abrechnung, Einstellungen.
///
/// Wer: Technik/Praesident immer; sonst Seitenrecht „waschküche-admin“ –
/// lesen = ansehen, schreiben = Raeume, Preis und Abrechnung aendern. Die API
/// verlangt zusaetzlich Ausschuss oder Verwaltung der STWEG mit Waschkueche
/// und lehnt sonst mit einem Satz ab (steht dann hier). Die Tuer (UniFi
/// Access) stellt nur Technik/Praesident ein.
class VerwaltenSeite extends StatelessWidget {
  const VerwaltenSeite({super.key, required this.api, required this.schreiben, required this.tuerEinstellen, this.jetzt});
  final WaschApi api;
  final bool schreiben;
  final bool tuerEinstellen;
  final DateTime Function()? jetzt;

  @override
  Widget build(BuildContext context) {
    final heute = (jetzt ?? DateTime.now)();
    return DefaultTabController(
      length: 7,
      child: Column(children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Übersicht'),
            Tab(text: 'Räume'),
            Tab(text: 'Sperrzeiten'),
            Tab(text: 'Nutzungen'),
            Tab(text: 'Abrechnung'),
            Tab(text: 'Einstellungen'),
            Tab(text: 'Modul'),
          ],
        ),
        if (!schreiben)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Hinweis('Nur ansehen: Ändern braucht das Recht „Waschküche-Admin“ mit Schreibrecht.'),
          ),
        Expanded(
          child: TabBarView(children: [
            _Uebersicht(api: api),
            _Raeume(api: api, schreiben: schreiben, tuerEinstellen: tuerEinstellen),
            _Sperrzeiten(api: api, schreiben: schreiben, heute: heute),
            _Nutzungen(api: api, heute: heute),
            _Abrechnung(api: api, schreiben: schreiben, heute: heute),
            _Einstellungen(api: api, schreiben: schreiben),
            _Modul(api: api),
          ]),
        ),
      ]),
    );
  }
}

/// Laedt einmal (und mit Ziehen bzw. „Nochmals“ neu); zeigt Laden/Fehler.
class _Laden<T> extends StatefulWidget {
  const _Laden({super.key, required this.laden, required this.inhalt});
  final Future<T> Function() laden;
  final Widget Function(BuildContext context, T daten, Future<void> Function() neu) inhalt;

  @override
  State<_Laden<T>> createState() => _LadenState<T>();
}

class _LadenState<T> extends State<_Laden<T>> {
  T? _daten;
  Object? _fehler;
  bool _fertig = false;

  @override
  void initState() {
    super.initState();
    _neu();
  }

  Future<void> _neu() async {
    setState(() => _fehler = null);
    try {
      final d = await widget.laden();
      if (mounted) {
        setState(() {
          _daten = d;
          _fertig = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _fehler = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fehler != null) return FehlerAnzeige.aus(_fehler!, nochmals: _neu);
    if (!_fertig) return const LadeAnzeige();
    return RefreshIndicator(onRefresh: _neu, child: widget.inhalt(context, _daten as T, _neu));
  }
}

// ── Uebersicht ──
class _Uebersicht extends StatelessWidget {
  const _Uebersicht({required this.api});
  final WaschApi api;

  @override
  Widget build(BuildContext context) => _Laden<Statistik>(
        laden: api.statistik,
        inhalt: (context, s, _) {
          Widget zahl(String titel, String wert, IconData i) => SizedBox(
                width: 170,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(i, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(wert, style: Theme.of(context).textTheme.headlineSmall),
                      Text(titel, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
              );
          return ListView(padding: const EdgeInsets.all(12), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              zahl('Aktive Räume', '${s.raeume}', Icons.local_laundry_service_outlined),
              zahl('Nutzungen gesamt', '${s.nutzungen}', Icons.repeat),
              zahl('Verbrauch gesamt', '${s.kwh.toStringAsFixed(2)} kWh', Icons.bolt),
              zahl('Einnahmen gesamt', franken(s.betrag), Icons.payments_outlined),
            ]),
            const SizedBox(height: 16),
            Abschnitt(
              titel: 'Am meisten genutzt',
              symbol: Icons.leaderboard_outlined,
              kind: s.oben.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('Noch keine Nutzungen.'))
                  : Column(children: [
                      for (var i = 0; i < s.oben.length; i++)
                        ListTile(
                          leading: CircleAvatar(child: Text('${i + 1}')),
                          title: Text(s.oben[i].person),
                          subtitle: s.oben[i].wohnung == null ? null : Text(s.oben[i].wohnung!),
                          trailing: Text('${s.oben[i].nutzungen} Nutzungen\n${s.oben[i].minuten} Min. · ${franken(s.oben[i].betrag)}',
                              textAlign: TextAlign.end),
                        ),
                    ]),
            ),
          ]);
        },
      );
}

// ── Raeume ──
class _Raeume extends StatefulWidget {
  const _Raeume({required this.api, required this.schreiben, required this.tuerEinstellen});
  final WaschApi api;
  final bool schreiben;
  final bool tuerEinstellen;

  @override
  State<_Raeume> createState() => _RaeumeState();
}

class _RaeumeState extends State<_Raeume> {
  var _stand = 0;

  Future<void> _bearbeiten([Raum? r]) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _RaumSeite(api: widget.api, raum: r, tuerEinstellen: widget.tuerEinstellen),
    ));
    if (ok == true) setState(() => _stand++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: widget.schreiben
            ? FloatingActionButton.extended(onPressed: _bearbeiten, icon: const Icon(Icons.add), label: const Text('Raum hinzufügen'))
            : null,
        body: _Laden<List<Raum>>(
          key: ValueKey(_stand),
          laden: widget.api.raeume,
          inhalt: (context, raeume, _) => ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 88), children: [
            if (raeume.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Hinweis('Keine Räume eingerichtet.')),
            for (final r in raeume)
              ListTile(
                leading: const Icon(Icons.local_laundry_service_outlined),
                title: Text(r.name),
                subtitle: Text([
                  r.ort ?? 'Kein Standort',
                  'Zähler: ${r.zaehler ?? 'nicht zugewiesen'}',
                  'Tür: ${r.tuer == null ? 'nicht eingestellt' : 'eingestellt'}',
                ].join('\n')),
                isThreeLine: true,
                trailing: widget.schreiben ? const Icon(Icons.edit_outlined) : null,
                onTap: widget.schreiben ? () => _bearbeiten(r) : null,
              ),
          ]),
        ),
      );
}

class _RaumSeite extends StatefulWidget {
  const _RaumSeite({required this.api, this.raum, required this.tuerEinstellen});
  final WaschApi api;
  final Raum? raum;
  final bool tuerEinstellen;

  @override
  State<_RaumSeite> createState() => _RaumSeiteState();
}

class _RaumSeiteState extends State<_RaumSeite> {
  late final _name = TextEditingController(text: widget.raum?.name);
  late final _ort = TextEditingController(text: widget.raum?.ort);
  late final _zaehler = TextEditingController(text: widget.raum?.zaehler);
  late final _tuer = TextEditingController(text: widget.raum?.tuer);

  @override
  void dispose() {
    for (final c in [_name, _ort, _zaehler, _tuer]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.raum == null ? 'Neuer Raum' : 'Raum bearbeiten')),
        body: RosenwegFormular(
          gespeichertText: 'Raum gespeichert.',
          gespeichert: () => Navigator.of(context).pop(true),
          // Neue Raeume gehoeren zu STWEG 3 (wie im Web; die API prueft die STWEG)
          speichern: () => widget.api.raumSpeichern(
            id: widget.raum?.id,
            name: _name.text.trim(),
            ort: _ort.text.trim(),
            zaehler: _zaehler.text.trim(),
            tuer: widget.tuerEinstellen ? _tuer.text.trim() : widget.raum?.tuer,
            stweg: widget.raum == null ? 3 : null,
          ),
          felder: [
            TextFeld(name: 'name', titel: 'Name', controller: _name, pflicht: true, hinweis: 'z. B. Waschküche 1'),
            TextFeld(name: 'location', titel: 'Standort', controller: _ort, hinweis: 'z. B. UG links'),
            TextFeld(name: 'energy_meter_id', titel: 'Energiezähler', controller: _zaehler, hinweis: 'Kennung aus dem Energie-Monitor, z. B. shelly-wasch1'),
            TextFeld(
              name: 'unifi_door_id',
              titel: 'Tür (UniFi Access)',
              controller: _tuer,
              aktiv: widget.tuerEinstellen,
              hinweis: widget.tuerEinstellen ? 'Kennung der Tür, leer = keine' : 'Die Tür stellt die Technik ein.',
            ),
          ],
        ),
      );
}

// ── Monat waehlen ──
class _MonatWahl extends StatelessWidget {
  const _MonatWahl({required this.monat, required this.geaendert, required this.heute});
  final DateTime monat;
  final ValueChanged<DateTime> geaendert;
  final DateTime heute;

  @override
  Widget build(BuildContext context) {
    final diesen = monat.year == heute.year && monat.month == heute.month;
    return Row(children: [
      IconButton(tooltip: 'Voriger Monat', icon: const Icon(Icons.chevron_left), onPressed: () => geaendert(DateTime(monat.year, monat.month - 1))),
      Expanded(child: Text(monatText(monat), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
      IconButton(
        tooltip: 'Nächster Monat',
        icon: const Icon(Icons.chevron_right),
        onPressed: diesen ? null : () => geaendert(DateTime(monat.year, monat.month + 1)),
      ),
    ]);
  }
}

// ── Nutzungen ──
class _Nutzungen extends StatefulWidget {
  const _Nutzungen({required this.api, required this.heute});
  final WaschApi api;
  final DateTime heute;

  @override
  State<_Nutzungen> createState() => _NutzungenState();
}

class _NutzungenState extends State<_Nutzungen> {
  late DateTime _monat = DateTime(widget.heute.year, widget.heute.month);

  @override
  Widget build(BuildContext context) => Column(children: [
        _MonatWahl(monat: _monat, heute: widget.heute, geaendert: (m) => setState(() => _monat = m)),
        Expanded(
          child: _Laden<List<Nutzung>>(
            key: ValueKey(_monat),
            laden: () => widget.api.nutzungen(monat: _monat),
            inhalt: (context, l, _) => ListView(children: [
              if (l.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Hinweis('Keine Nutzungen in diesem Monat.')),
              for (final n in l)
                ListTile(
                  title: Text('${n.person ?? '–'}${n.wohnung == null ? '' : ' (${n.wohnung})'}'),
                  subtitle: Text([
                    if (n.beginn != null) '${datumText(n.beginn!)} ${uhrText(n.beginn!)}',
                    ?n.raumName,
                    if (n.minuten != null) '${n.minuten} Min.',
                    if (n.kwh != null) '${n.kwh!.toStringAsFixed(2)} kWh',
                  ].join(' · ')),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(n.kosten == null ? '–' : franken(n.kosten!)),
                    Text(n.statusText, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
            ]),
          ),
        ),
      ]);
}

// ── Abrechnung ──
class _Abrechnung extends StatefulWidget {
  const _Abrechnung({required this.api, required this.schreiben, required this.heute});
  final WaschApi api;
  final bool schreiben;
  final DateTime heute;

  @override
  State<_Abrechnung> createState() => _AbrechnungState();
}

class _AbrechnungState extends State<_Abrechnung> {
  late DateTime _monat = DateTime(widget.heute.year, widget.heute.month);
  bool _sendet = false;

  /// Abrechnen geht fuer jeden vergangenen Monat, jeden nur einmal (die API
  /// antwortet sonst 409 „schon abgerechnet“). Standard: Vormonat.
  bool get _vergangen => _monat.isBefore(DateTime(widget.heute.year, widget.heute.month));

  @override
  void initState() {
    super.initState();
    _monat = DateTime(widget.heute.year, widget.heute.month - 1);
  }

  Future<void> _senden() async {
    final monat = _monat;
    final m = monatText(monat);
    if (!await frage(context, 'Abrechnung $m senden?',
        'Alle Personen mit Nutzungen im $m bekommen ihre Abrechnung per E-Mail. Ein Monat wird nur einmal abgerechnet; '
        'das lässt sich nicht zurücknehmen.',
        ja: 'Senden')) {
      return;
    }
    setState(() => _sendet = true);
    try {
      final text = await widget.api.abrechnungSenden(monat);
      if (mounted) zeigeMeldung(context, text ?? 'Abrechnung $m ausgeführt.');
    } catch (e) {
      if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    } finally {
      if (mounted) setState(() => _sendet = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _MonatWahl(monat: _monat, heute: widget.heute, geaendert: (m) => setState(() => _monat = m)),
        Expanded(
          child: _Laden<List<Kosten>>(
            key: ValueKey(_monat),
            laden: () => widget.api.kosten(_monat),
            inhalt: (context, l, _) {
              final kwh = l.fold<double>(0, (s, k) => s + k.kwh);
              final summe = l.fold<double>(0, (s, k) => s + k.betrag);
              return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                if (l.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Hinweis('Keine Nutzungen in diesem Monat.'))
                else ...[
                  ListTile(
                    title: Text('Gesamt: ${franken(summe)}', style: Theme.of(context).textTheme.titleMedium),
                    subtitle: Text('${kwh.toStringAsFixed(2)} kWh · ${l.length} ${l.length == 1 ? 'Person' : 'Personen'}'),
                  ),
                  const Divider(height: 1),
                  for (final k in l)
                    ListTile(
                      title: Text(k.person),
                      subtitle: Text([?k.wohnung, '${k.nutzungen} Nutzungen', '${k.minuten} Min.', '${k.kwh.toStringAsFixed(2)} kWh'].join(' · ')),
                      trailing: Text(franken(k.betrag)),
                    ),
                ],
                if (widget.schreiben && _vergangen)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _sendet || l.isEmpty ? null : _senden,
                        icon: _sendet
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_outlined),
                        label: Text('Abrechnung ${monatText(_monat)} per E-Mail senden'),
                      ),
                    ),
                  )
                else if (widget.schreiben)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Der laufende Monat lässt sich erst ab dem 1. des nächsten Monats abrechnen.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ]);
            },
          ),
        ),
      ]);
}

// ── Sperrzeiten ──
class _Sperrzeiten extends StatefulWidget {
  const _Sperrzeiten({required this.api, required this.schreiben, required this.heute});
  final WaschApi api;
  final bool schreiben;
  final DateTime heute;

  @override
  State<_Sperrzeiten> createState() => _SperrzeitenState();
}

class _SperrzeitenState extends State<_Sperrzeiten> {
  var _stand = 0;

  Future<void> _neu() async {
    final raeume = await widget.api.raeume();
    if (!mounted) return;
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _SperrSeite(api: widget.api, raeume: raeume, heute: widget.heute),
    ));
    if (ok == true) setState(() => _stand++);
  }

  Future<void> _aufheben(Sperrzeit s) async {
    if (!await frage(context, 'Sperrzeit aufheben?', 'Danach kann in dieser Zeit wieder reserviert werden (${s.grund}).',
        ja: 'Aufheben', gefaehrlich: true)) {
      return;
    }
    try {
      await widget.api.sperreAufheben(s.id);
      if (!mounted) return;
      zeigeMeldung(context, 'Sperrzeit aufgehoben.');
      setState(() => _stand++);
    } catch (e) {
      if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: widget.schreiben
            ? FloatingActionButton.extended(onPressed: _neu, icon: const Icon(Icons.block), label: const Text('Sperren'))
            : null,
        body: _Laden<List<Sperrzeit>>(
          key: ValueKey(_stand),
          laden: () => widget.api.sperrzeiten(),
          inhalt: (context, l, _) => ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 88), children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('In einer Sperrzeit kann niemand reservieren; die Belegung zeigt sie grau mit dem Grund.'),
            ),
            if (l.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Hinweis('Keine kommenden Sperrzeiten.')),
            for (final s in l)
              ListTile(
                leading: const Icon(Icons.block),
                title: Text(s.grund),
                subtitle: Text('${s.raumName ?? 'Waschküche'} · ${_zeitraum(s.von, s.bis)}'),
                trailing: widget.schreiben
                    ? IconButton(tooltip: 'Aufheben', icon: const Icon(Icons.delete_outline), onPressed: () => _aufheben(s))
                    : null,
              ),
          ]),
        ),
      );
}

/// „Mo 30.11. 08:00–12:00“ bzw. „Mo 30.11. 08:00 – Di 1.12. 12:00“
String _zeitraum(DateTime a, DateTime b) {
  String tag(DateTime d) => '${wochentageKurz[d.weekday - 1]} ${d.day}.${d.month}.';
  final gleich = a.year == b.year && a.month == b.month && a.day == b.day;
  return gleich ? '${tag(a)} ${uhrText(a)}–${uhrText(b)}' : '${tag(a)} ${uhrText(a)} – ${tag(b)} ${uhrText(b)}';
}

class _SperrSeite extends StatefulWidget {
  const _SperrSeite({required this.api, required this.raeume, required this.heute});
  final WaschApi api;
  final List<Raum> raeume;
  final DateTime heute;

  @override
  State<_SperrSeite> createState() => _SperrSeiteState();
}

class _SperrSeiteState extends State<_SperrSeite> {
  late int? _raum = widget.raeume.isEmpty ? null : widget.raeume.first.id;
  late DateTime _vonTag = DateTime(widget.heute.year, widget.heute.month, widget.heute.day + 1);
  TimeOfDay _von = const TimeOfDay(hour: 8, minute: 0);
  late DateTime _bisTag = _vonTag;
  TimeOfDay _bis = const TimeOfDay(hour: 12, minute: 0);
  final _grund = TextEditingController();

  @override
  void dispose() {
    _grund.dispose();
    super.dispose();
  }

  DateTime _um(DateTime t, TimeOfDay z) => DateTime(t.year, t.month, t.day, z.hour, z.minute);

  Future<void> _speichern() async {
    final von = _um(_vonTag, _von), bis = _um(_bisTag, _bis);
    if (_raum == null) throw ApiFehler(400, 'Bitte eine Waschküche wählen.', null);
    if (!bis.isAfter(von)) throw ApiFehler(400, 'Das Ende muss nach dem Beginn liegen.', null);
    final grund = _grund.text.trim();
    // Erst zeigen, wen es trifft: diese Reservationen werden storniert
    final betroffen = await widget.api.sperrVorschau(_raum!, von, bis, grund);
    if (betroffen.isNotEmpty && mounted && !await _nachfragen(betroffen)) {
      throw ApiFehler(0, 'Abgebrochen – nichts gesperrt.', null);
    }
    final (storniert, benachrichtigt) = await widget.api.sperren(_raum!, von, bis, grund);
    if (mounted) {
      zeigeMeldung(
        context,
        storniert == 0
            ? 'Gesperrt.'
            : 'Gesperrt. $storniert ${storniert == 1 ? 'Reservation' : 'Reservationen'} storniert, '
                '$benachrichtigt ${benachrichtigt == 1 ? 'Person' : 'Personen'} benachrichtigt.',
      );
    }
  }

  Future<bool> _nachfragen(List<Betroffen> l) async {
    final n = l.length;
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$n ${n == 1 ? 'Reservation' : 'Reservationen'} stornieren?'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Die Sperrzeit storniert diese Reservationen (bei Serien nur diese Termine). '
                'Die Personen bekommen eine E-Mail mit Grund und Zeitraum.'),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final b in l)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(b.woechentlich ? Icons.repeat : Icons.event_busy_outlined),
                    title: Text('${b.person ?? '–'}${b.wohnung == null ? '' : ' (${b.wohnung})'}'),
                    subtitle: Text(_zeitraum(b.von, b.bis)),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sperren und stornieren'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Zeit sperren')),
        body: RosenwegFormular(
          speichernText: 'Sperren',
          gespeichertText: null,
          speichern: _speichern,
          gespeichert: () => Navigator.of(context).pop(true),
          felder: [
            AuswahlFeld<int>(
              name: 'room_id',
              titel: 'Waschküche',
              pflicht: true,
              optionen: {for (final r in widget.raeume) r.id: r.name},
              wert: _raum,
              geaendert: (v) => setState(() => _raum = v),
            ),
            Row(children: [
              Expanded(child: DatumFeld(titel: 'Von (Tag)', wert: _vonTag, pflicht: true, geaendert: (v) => setState(() {
                    final alt = _vonTag;
                    _vonTag = v ?? _vonTag;
                    if (_bisTag == alt || _bisTag.isBefore(_vonTag)) _bisTag = _vonTag;
                  }))),
              const SizedBox(width: 12),
              Expanded(child: ZeitFeld(titel: 'Uhrzeit', wert: _von, pflicht: true, geaendert: (v) => setState(() => _von = v ?? _von))),
            ]),
            Row(children: [
              Expanded(child: DatumFeld(titel: 'Bis (Tag)', wert: _bisTag, pflicht: true, erstes: _vonTag, geaendert: (v) => setState(() => _bisTag = v ?? _bisTag))),
              const SizedBox(width: 12),
              Expanded(child: ZeitFeld(titel: 'Uhrzeit', wert: _bis, pflicht: true, geaendert: (v) => setState(() => _bis = v ?? _bis))),
            ]),
            TextFeld(name: 'grund', titel: 'Grund', controller: _grund, pflicht: true, hinweis: 'z. B. Reinigung, Wartung Waschmaschine', pruefen: Pruefen.hoechstens(200)),
            const Hinweis('Reservationen in dieser Zeit werden storniert (bei Serien nur diese Termine) und die Personen '
                'per E-Mail benachrichtigt. Vorher zeigt die App, wen es trifft.'),
          ],
        ),
      );
}

// ── Einstellungen ──
class _Einstellungen extends StatelessWidget {
  const _Einstellungen({required this.api, required this.schreiben});
  final WaschApi api;
  final bool schreiben;

  @override
  Widget build(BuildContext context) => _Laden<Einstellungen>(
        laden: api.einstellungen,
        inhalt: (context, e, _) => _EinstellungenFormular(api: api, schreiben: schreiben, e: e),
      );
}

class _EinstellungenFormular extends StatefulWidget {
  const _EinstellungenFormular({required this.api, required this.schreiben, required this.e});
  final WaschApi api;
  final bool schreiben;
  final Einstellungen e;

  @override
  State<_EinstellungenFormular> createState() => _EinstellungenFormularState();
}

class _EinstellungenFormularState extends State<_EinstellungenFormular> {
  late final _preis = TextEditingController(text: widget.e.preisProKwh);
  late final _tage = TextEditingController(text: '${widget.e.maxTage}');
  late final _offen = TextEditingController(text: '${widget.e.maxOffen}');
  late bool _auto = widget.e.autoAbrechnung;

  @override
  void dispose() {
    for (final c in [_preis, _tage, _offen]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? Function(String?) _ganz(int min, int max) => (v) {
        final n = int.tryParse((v ?? '').trim());
        return n == null || n < min || n > max ? 'Ganze Zahl von $min bis $max.' : null;
      };

  static String? _preisPruefen(String? v) {
    final z = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
    return z == null || z < 0 || z > 10 ? 'Bitte einen Preis wie 0.30 eingeben.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final felder = <Widget>[
      TextFeld(
        name: 'cost_per_kwh',
        titel: 'Preis pro kWh',
        controller: _preis,
        vorText: 'CHF ',
        pflicht: true,
        aktiv: widget.schreiben,
        tastatur: const TextInputType.numberWithOptions(decimal: true),
        pruefen: _preisPruefen,
        hinweis: 'Gilt für die Kosten jeder neuen Nutzung (Verbrauch × Preis).',
      ),
      TextFeld(
        name: 'reservation_max_days',
        titel: 'Reservieren höchstens so viele Tage im Voraus',
        controller: _tage,
        pflicht: true,
        aktiv: widget.schreiben,
        tastatur: TextInputType.number,
        pruefen: _ganz(1, 365),
      ),
      TextFeld(
        name: 'reservation_max_per_user',
        titel: 'Offene Reservationen je Person höchstens',
        controller: _offen,
        pflicht: true,
        aktiv: widget.schreiben,
        tastatur: TextInputType.number,
        pruefen: _ganz(1, 500),
        hinweis: 'Eine wöchentliche Serie zählt mit jedem Termin.',
      ),
      SchalterFeld(
        name: 'auto_billing',
        titel: 'Automatisch abrechnen',
        erklaerung: 'Am 1. jedes Monats um 08:00 den Vormonat per E-Mail abrechnen.',
        wert: _auto,
        geaendert: widget.schreiben ? (v) => setState(() => _auto = v) : (_) {},
      ),
      const Hinweis('Türen und UniFi Access stellt die Technik in Rosenweg Zutritt ein.'),
    ];
    if (!widget.schreiben) {
      return ListView(padding: const EdgeInsets.all(16), children: [for (final f in felder) Padding(padding: const EdgeInsets.only(bottom: 16), child: f)]);
    }
    return RosenwegFormular(
      fragenBeimVerlassen: false,
      gespeichertText: 'Einstellungen gespeichert.',
      speichern: () => widget.api.einstellungenSpeichern(Einstellungen(
        preisProKwh: _preis.text.trim().replaceAll(',', '.'),
        maxTage: int.parse(_tage.text.trim()),
        maxOffen: int.parse(_offen.text.trim()),
        autoAbrechnung: _auto,
      )),
      felder: felder,
    );
  }
}


// ── Modul Waschkueche je STWEG ──
// Der Schalter stand frueher in „STWEG-Module“ (Website). Wer schalten darf, entscheidet die API:
// Technik/Praesident jede STWEG, der Ausschuss die eigene (POST /api/stweg-modules).
class _Modul extends StatefulWidget {
  const _Modul({required this.api});
  final WaschApi api;

  @override
  State<_Modul> createState() => _ModulState();
}

class _ModulState extends State<_Modul> {
  List<ModulStweg>? _liste;
  Object? _fehler;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _fehler = null);
    try {
      final l = await widget.api.modulStwegs();
      if (mounted) setState(() => _liste = l);
    } catch (e) {
      if (mounted) setState(() => _fehler = e);
    }
  }

  Future<void> _schalten(ModulStweg m, bool an) async {
    if (!an && !await frage(context, 'Waschküche ausschalten?', 'Die Waschküche von ${m.name} ist dann für die Bewohner nicht mehr buchbar.', ja: 'Ausschalten', gefaehrlich: true)) return;
    try {
      await widget.api.modulSetzen(m.nr, an);
      await _laden();
    } catch (e) {
      if (mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fehler != null) return FehlerAnzeige.aus(_fehler!, nochmals: _laden);
    final l = _liste;
    if (l == null) return const LadeAnzeige();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Waschküche je STWEG ein- oder ausschalten. Ausschuss: die eigene STWEG; Technik und Präsident: alle.'),
        const SizedBox(height: 8),
        if (l.isEmpty) const Hinweis('Du darfst das Modul für keine STWEG schalten.'),
        for (final m in l) SwitchListTile(title: Text(m.name), value: m.aktiv, onChanged: (v) => _schalten(m, v)),
      ],
    );
  }
}
