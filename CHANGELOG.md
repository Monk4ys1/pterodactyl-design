# Changelog

Alle nennenswerten Aenderungen an Nebula werden hier festgehalten.
Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/).

## [2.0.0] – 2026-08-24

Vollstaendige Neugestaltung der Oberflaeche und ein deutlich groesserer
Funktionsumfang. Bestehende Einstellungen werden uebernommen; neue Optionen
kommen mit ihren Standardwerten dazu.

### Neu gestaltet
- **Seitenschiene statt Kopfleiste.** Navigation, Serverliste mit Live-Status,
  angeheftete Server und Kontobereich am linken Rand; zwei Breiten, mobil
  ausfahrbar. Die Eintraege der Panel-Navigation werden gespiegelt, damit auch
  kuenftige Eintraege automatisch erscheinen.
- **Kopfleiste** mit Pfadanzeige, Serverstatus, Adresse und UUID zum Kopieren,
  Laufzeit und Uhr.
- **Material und Tiefe**: Flaechen aus Verlauf plus Rahmenlicht statt flacher
  Fuellfarbe, durchscheinende Ebenen fuer Navigation, Meldungen und Overlays,
  weiche Uebergaenge statt harter Trennlinien.
- **Typoskala** mit groessenabhaengiger Laufweite und Zeilenhoehe sowie
  durchgehenden Tabellenziffern fuer Messwerte.
- **Bewegung**: Rueckmeldung auf dem Druck statt beim Loslassen, Kurven, die
  kritisch gedaempfte Federn nachbilden.

### Neue Funktionen
- **Serveruebersicht** auf dem Dashboard: Kacheln mit Live-Auslastung,
  Statusanzeige und Schnellsteuerung, darueber Kennzahlen ueber alle Server.
- **Kurzbefehle** je Server, die ueber die bereits bestehende Wings-Verbindung
  gesendet werden.
- **Schwebende Mini-Konsole** mit eigener Eingabezeile, frei verschiebbar
  (1:1 am Zeiger, mit Gummiband an den Raendern) und in der Groesse aenderbar.
- **Fokusmodus**, der Schiene und Kopfleiste zuruecktreten laesst.
- **Anheften und Markieren** von Servern (Farbe und Kuerzel), sichtbar in
  Schiene, Kacheln und Palette.
- **Schluesselwort-Waechter** fuer die Konsole (Text oder /muster/i).
- **Auslastungswarnungen** fuer CPU und Arbeitsspeicher mit Haltezeit und
  Entwarnung.
- **Diagramme ueberarbeitet**: zuruecktretendes Raster, Fadenkreuz mit
  Sprechblase, Min/Mittel/Max und CSV-Export. Die Serienfarben sind fest
  vergeben und auf Farbfehlsichtigkeit geprueft.
- **Befehlspalette** mit Treffer-Hervorhebung, Statuspunkten, zuletzt besuchten
  Servern und den Kurzbefehlen des aktuellen Servers.
- **Einstellungen in Reitern** (Design, Layout, Module, Warnungen, Konsole,
  Daten) statt einer langen Liste.
- Neues Preset **Carbon**; **Midnight** entfaellt.
- Zusaetzliche Tastenkuerzel: Schiene (Strg+B), Mini-Konsole
  (Strg+Umschalt+D), Fokusmodus (Strg+Umschalt+Z).

### Behoben
- Die Hintergrundebene lag hinter dem deckenden Body-Hintergrund und war
  dadurch unsichtbar. Die Grundfarbe liegt jetzt auf `<html>`.
- Ein zu weit gefasster Selektor traf die Navigationsleiste und verschob deren
  Inhalt.
- Eine geaenderte Auslastungsschwelle wurde erst nach dem naechsten
  Unterschreiten wieder scharf; sie gilt jetzt sofort.
- Der DOM-Tagger markierte die eigenen Uebersichtskacheln als Panel-Zeilen und
  blendete sie damit aus.

### Testumgebung
- Der Testserver sucht sich einen freien Port, statt einen festen zu belegen –
  haengengebliebene Laeufe koennen sich nicht mehr gegenseitig stoeren.
- Der Nachbau spiegelt gesendete Kommandos zurueck, sodass geprueft wird, dass
  Kurzbefehle wirklich auf der Leitung landen.
- Rund 70 Pruefungen, unter anderem Ziehen der Mini-Konsole, Waechter,
  Schwellwerte und mobiles Layout.

## [1.0.0] – 2026-08-24

### Neu
- Vollstaendige optische Ueberarbeitung der Client-Oberflaeche (Navigation,
  Sub-Navigation, Karten, Tabellen, Formulare, Modals, Konsole, Login).
- Eigenes Design fuer den Adminbereich (AdminLTE) inklusive Seitenleiste,
  Boxen, Reitern, Tabellen, Formularen und CodeMirror.
- Acht Farbpresets (Nebula, Ocean, Forest, Ember, Rose, Solar, Midnight, Mono)
  sowie eine frei waehlbare Akzentfarbe.
- Hell-, Dunkel- und Automatikmodus.
- Command-Palette (`Strg + K`) mit Serversuche, Seitenwechsel, Power-Aktionen
  und Designumschaltung.
- Live-Graphen fuer CPU, Arbeitsspeicher, Netzwerk und Festplatte, gespeist aus
  dem mitgelesenen Wings-Datenstrom.
- Konsolen-Werkzeugleiste: Volltextsuche mit Hervorhebung, Log-Level-Filter,
  Zeitstempel, Zeilenzaehler, Kopieren, Download als `.log`, Vollbild.
- Serverleiste mit Adresse, Node, UUID (je zum Kopieren) und Laufzeit.
- Statusmeldungen als Toast, Statuspunkt im Favicon, Statussymbol im Seitentitel,
  optionale Desktop-Hinweise, optionaler Signalton, Absturzerkennung.
- Tastenkuerzel inklusive Uebersicht (`Strg + /`).
- Einstellungs-Drawer mit Live-Vorschau, Export und Import.
- Ein-Befehl-Installer mit automatischer Panel-Erkennung, Backup,
  Deinstallation, Selbstdiagnose (`nebula doctor`) und Wiederherstellung.
- Browsergestuetzte Testumgebung unter `tests/`.

[2.0.0]: https://github.com/Monk4ys1/pterodactyl-design/releases/tag/v2.0.0
[1.0.0]: https://github.com/Monk4ys1/pterodactyl-design/releases/tag/v1.0.0
