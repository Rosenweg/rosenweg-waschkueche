// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../wasch_api.dart';

/// Verwaltung (wie stweg3/pages/waschkueche-admin.html): Uebersicht,
/// Raeume, Nutzungen, Abrechnung, Preis.
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
      length: 5,
      child: Column(children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Übersicht'),
            Tab(text: 'Räume'),
            Tab(text: 'Nutzungen'),
            Tab(text: 'Abrechnung'),
            Tab(text: 'Preis'),
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
            _Nutzungen(api: api, heute: heute),
            _Abrechnung(api: api, schreiben: schreiben, heute: heute),
            _Preis(api: api, schreiben: schreiben),
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

  /// Die Anlage rechnet immer den Vormonat ab (runMonthlyBilling), jeden
  /// Monat nur einmal – der Knopf steht darum nur beim Vormonat.
  DateTime get _vormonat => DateTime(widget.heute.year, widget.heute.month - 1);

  Future<void> _senden() async {
    final m = monatText(_vormonat);
    if (!await frage(context, 'Abrechnung $m senden?',
        'Alle Personen mit Nutzungen im $m bekommen ihre Abrechnung per E-Mail. Ein Monat wird nur einmal abgerechnet; '
        'das lässt sich nicht zurücknehmen.',
        ja: 'Senden')) {
      return;
    }
    setState(() => _sendet = true);
    try {
      final text = await widget.api.abrechnungSenden(_vormonat);
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
                if (widget.schreiben && _monat == _vormonat)
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
                    child: Text('Per E-Mail abrechnen lässt sich nur der Vormonat (${monatText(_vormonat)}).',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ]);
            },
          ),
        ),
      ]);
}

// ── Preis ──
class _Preis extends StatelessWidget {
  const _Preis({required this.api, required this.schreiben});
  final WaschApi api;
  final bool schreiben;

  @override
  Widget build(BuildContext context) => _Laden<String?>(
        laden: api.preisProKwh,
        inhalt: (context, preis, neu) => _PreisFormular(api: api, schreiben: schreiben, preis: preis),
      );
}

class _PreisFormular extends StatefulWidget {
  const _PreisFormular({required this.api, required this.schreiben, this.preis});
  final WaschApi api;
  final bool schreiben;
  final String? preis;

  @override
  State<_PreisFormular> createState() => _PreisFormularState();
}

class _PreisFormularState extends State<_PreisFormular> {
  late final _preis = TextEditingController(text: widget.preis);

  @override
  void dispose() {
    _preis.dispose();
    super.dispose();
  }

  static String? _pruefen(String? v) {
    final t = (v ?? '').trim().replaceAll(',', '.');
    final z = double.tryParse(t);
    if (z == null || z < 0 || z > 10) return 'Bitte einen Preis wie 0.30 eingeben.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final felder = [
      TextFeld(
        name: 'cost_per_kwh',
        titel: 'Preis pro kWh',
        controller: _preis,
        vorText: 'CHF ',
        pflicht: true,
        aktiv: widget.schreiben,
        tastatur: const TextInputType.numberWithOptions(decimal: true),
        pruefen: _pruefen,
        hinweis: 'Gilt für die Kosten jeder neuen Nutzung (Verbrauch × Preis).',
      ),
      const Hinweis('Türen und UniFi Access stellt die Technik in Rosenweg Zutritt ein.'),
    ];
    if (!widget.schreiben) {
      return ListView(padding: const EdgeInsets.all(16), children: [for (final f in felder) Padding(padding: const EdgeInsets.only(bottom: 16), child: f)]);
    }
    return RosenwegFormular(
      fragenBeimVerlassen: false,
      gespeichertText: 'Preis gespeichert.',
      speichern: () => widget.api.preisSpeichern(_preis.text.trim().replaceAll(',', '.')),
      felder: felder,
    );
  }
}
