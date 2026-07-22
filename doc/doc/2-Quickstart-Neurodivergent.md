# 🧭 Quickstart für Neurodivergente

> **Lies zuerst diese Seite.**  
> Sie ist kurz, klar und sagt dir genau, was du tun musst.

---

## 🔍 Auf einen Blick

**Was ist Job-O-Matic?**  
Eine App, die aus Job-URLs automatisch Bewerbungen (Deckblatt, Anschreiben, Lebenslauf) als PDF erstellt.

**Wer hat das gemacht?**  
Du (Matthias) – das ist DEIN Projekt.

**Was kann die App JETZT (dieser Stand)?**  
1️⃣ Du gibst Job-URLs ein.  
2️⃣ Du suchst optional nach Jobs.  
3️⃣ Du siehst eine Liste aller Bewerbungen mit Status.  
4️⃣ Du klickst auf eine Bewerbung, um Details zu sehen.  
5️⃣ Du exportierst alle fertigen Bewerbungen.  

**Was funktioniert NOCH NICHT?**  
- PDF-Generierung (Platzhalter)  
- Echte API-Anbindung (Mock-Daten)  
- Datenbank-Persistenz (In-Memory)  
- Diese Dinge kommen später.

---

## 🚀 Projekt starten (Schritt für Schritt)

### Das brauchst du
- ✅ Flutter SDK installiert
- ✅ Ein Terminal (CMD, PowerShell, VS Code Terminal)

### So startest du die App

```
1. Terminal öffnen
2. In das Projektverzeichnis wechseln:
   cd c:\Users\matth\dev\Job-O-Matic\job_o_matic

3. App starten:
   flutter run
```

**WICHTIG:** Wenn `flutter run` nicht funktioniert, liegt es meist daran, dass:
- Du nicht im richtigen Ordner bist (muss `job_o_matic` sein)
- Flutter nicht installiert ist (`flutter doctor` im Terminal prüfen)
- Ein Emulator/ Gerät nicht läuft

### App testen OHNE Emulator

```
flutter test
```
→ Zeigt "All tests passed!" ✅

### Code auf Fehler prüfen

```
flutter analyze
```
→ Zeigt "No issues found!" ✅

---

## 🏗️ Projekt-Struktur (Wo ist was?)

```
job_o_matic/          ← DAS ist das Projekt
├── lib/              ← Hier ist der Code
│   ├── main.dart     ← Startpunkt der App
│   ├── core/         ← Grundlagen (Logger, Theme)
│   ├── models/       ← Datenbausteine (Bewerbung, CV)
│   ├── data/         ← Datenverwaltung
│   ├── router/       ← Navigation
│   └── presentation/ ← Bildschirme (Was du siehst)
├── test/             ← Tests
└── pubspec.yaml      ← Abhängigkeiten
```

**Faustregel:**  
- `models/` = Datenklassen (was ist eine Bewerbung?)  
- `data/` = Speicher (wo sind die Daten?)  
- `router/` = Navigation (welcher Bildschirm kommt als nächstes?)  
- `presentation/screens/` = Bildschirme (was sieht der Nutzer?)  
- `core/` = Werkzeugkasten (Logger, Design)

---

## 🎯 Die 4 Bildschirme

| # | Bildschirm | Route | Was passiert hier? |
|---|------------|-------|-------------------|
| 1 | **Stelleneingabe** | `/` | URLs eingeben, validieren, weiter |
| 2 | **Jobsuche** | `/search` | Jobs suchen (optional), übernehmen |
| 3 | **Ergebnisübersicht** | `/applications` | Alle Bewerbungen sehen, exportieren |
| 3a | **Detailansicht** | `/applications/123` | Eine Bewerbung im Detail ansehen |

### So hängen sie zusammen

```
Stelleneingabe ──Weiter──► Ergebnisübersicht
     │                        │      │
     │ Jobsuche               │      │ Tippen
     ▼                        ▼      ▼
  Jobsuche ──Übernehmen──►  Detailansicht
                              (eine Bewerbung)
```

---

## 💡 Wichtige Konzepte (kurz erklärt)

### 🔄 Status einer Bewerbung

Jede Bewerbung hat einen Status. Du siehst ihn an der Farbe:

| Farbe | Bedeutung | Was tun? |
|-------|-----------|----------|
| ⚪ Grau | Wartend | Noch nichts passiert |
| 🔵 Blau | In Bearbeitung | Läuft gerade |
| 🟢 Grün | Fertig ✅ | PDF ist da, anklicken zum Ansehen |
| 🔴 Rot | Fehler ❌ | Klick auf "Neu starten" |
| 🔷 Teal | Exportiert | Wurde bereits heruntergeladen |

### 📝 Logger (für Fehlersuche)

Die App schreibt Logs. Bei Problemen:

```
1. App starten (flutter run)
2. Im Terminal die Logs lesen
3. Siehst du [ERROR] → Problem gefunden
4. Siehst du [INFO] → Alles normal
```

### 🎨 Theme (Aussehen)

Die App nutzt **Rot** als Hauptfarbe.  
Es gibt einen **Hell- und Dunkel-Modus** (automatisch je nach Systemeinstellung).

---

## ❓ Häufige Probleme (Troubleshooting)

| Problem | Lösung |
|---------|--------|
| **"flutter: command not found"** | Flutter nicht installiert → `flutter doctor` ausführen |
| **"Expected to find project root"** | Du bist im falschen Ordner → zu `job_o_matic/` wechseln |
| **Analyzer-Fehler (rot unterstrichen)** | `dart fix --apply` im Terminal ausführen |
| **App startet nicht** | `flutter clean` dann `flutter pub get` dann `flutter run` |
| **Ich habe den Überblick verloren** | Zurück zu Schritt 1 dieser Anleitung |
| **Ich bin überfordert** | **Pause machen.** Der Code läuft auch morgen noch. |

---

## 📋 Checkliste für einen Arbeitstag

- [ ] Terminal öffnen
- [ ] `cd c:\Users\matth\dev\Job-O-Matic\job_o_matic`
- [ ] `git pull` (wenn vorhanden)
- [ ] `flutter pub get` (falls neue Abhängigkeiten)
- [ ] `flutter analyze` (Code-Check)
- [ ] `flutter test` (Test laufen lassen)
- [ ] `flutter run` (App starten)
- [ ] **Arbeit erledigt** ✅

---

## 🧠 Neurodivergente Tipps

- **Eine Sache nach der anderen.** Nicht alles auf einmal machen.
- **Der Code beißt nicht.** `flutter analyze` sagt dir, ob was kaputt ist.
- **Nicht vergleichen.** Dein Projekt, dein Tempo.
- **Dokumentation ist zum Lesen da** – nicht zum Auswendiglernen.
- **Such dir einen festen Arbeitsplatz** im Code (z. B. immer ein Screen) und mach den fertig.
- **Timer setzen:** 25 Minuten arbeiten, 5 Minuten Pause (Pomodoro).
- **Bei Überforderung:** Einfach `flutter test` laufen lassen. Wenn das klappt, ist alles in Ordnung.
- **Git ist dein Freund:** Vor großen Änderungen `git commit`. Dann kannst du nichts kaputt machen.