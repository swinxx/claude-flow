# Design: kimiflow — Pre-Build-Summary-Gate + native Phasen-Tasklist

- **Datum:** 2026-06-22
- **Status:** Design freigegeben (brainstorming) → bereit für `writing-plans`
- **Sprache:** Prosa Deutsch (Review-Sprache des Users); Code-Identifier, Pfade und Section-Namen bleiben Englisch (Konsistenz mit SKILL.md/reference.md).

## Problem / Ziel

Zwei UX-Lücken in kimiflow:

1. **Kein Pre-Build-Freigabe-Gate.** Ein normaler Full-Run hat User-Gates nur in **Phase 1** (Intent „Does this match?") und **Phase 7** (Commit). Zwischen **Phase 4** (Plan-Gate — interne Reviewer, binär) und **Phase 5** (Implement) plant und baut kimiflow durch, ohne den User vorher zu fragen. (`--prepare` stoppt nach Phase 4, ist aber ein Modus, kein Gate im Normallauf.)
2. **Keine native Tasklist.** Fortschritt wird nur in `.kimiflow/<slug>/STATE.md` (Datei) + farbigen Phasen-Markern getrackt. Das native Claude-Code-Tasklist-Widget (Glance-Übersicht „N tasks, M done") wird nicht genutzt.

**Ziel:** (A) ein projekt-lokal konfigurierbarer Pre-Build-Summary-Gate, (B) eine native Phasen-Tasklist. **Beide ändern die Engine NICHT** (Gates, Artefakte, Evidenz, Subagenten, Thresholds bleiben identisch) — reine Kontroll-/Sichtbarkeits-Ergänzungen.

## Entscheidungen (im Brainstorming festgelegt)

- **A-Platzierung:** neuer Schritt am Ende von Phase 4 (Plan ist da bereits vom Plan-Gate vetted), vor Phase 5. In `--prepare` ist es genau der Stop, der dort ohnehin passiert → vereinheitlicht.
- **A-Schalter:** **projekt-lokal** `.kimiflow/build-gate` mit Inhalt `on` oder `off`, **default `on`**.
  - **KEIN globaler Schalter** — die Self-contained-Regel (reference.md) erlaubt global nur `verbosity`; nichts gate-related aus `~/.claude`. Ein globaler build-gate würde sie verletzen.
  - **KEIN Per-Run-Flag** (YAGNI — projekt-lokaler Default genügt).
- **A-Inhalt der Summary:** Problem/Ziel · Entscheidungen · Plan/Design · Tests/Acceptance (`AC-N → test_name`) · Risiken · + Artefakt-Pfade. Bewusste Terse-Ausnahme analog zum Phase-7-Commit-Gate.
- **B-Mechanik:** `TaskCreate`/`TaskUpdate` auf **Phasen-Ebene**; **ergänzt** STATE.md + Marker, **ersetzt** nichts. Terse-Regel (e) wird präzisiert (Widget statt Prosa-Narration ist erlaubt).

## Design — Feature A: Pre-Build-Summary-Gate

**Trigger / Platzierung.** Neuer Schritt „Phase 4½" am Ende von Phase 4, nachdem das Plan-Gate geöffnet hat (0 offene BLOCKER/HIGH) und bevor Phase 5 startet. Greift nur, wenn der build-gate auf `on` steht (Default).

**Ablauf.**
1. Resolve den build-gate (s. „Schalter" unten). Steht er auf `off` → Schritt überspringen, direkt zu Phase 5.
2. Steht er auf `on` und die Session ist interaktiv → die strukturierte Summary drucken und **STOPPEN** mit der Frage „freigeben oder ändern?".
3. **OK / Freigabe** → Phase 5 (Implement). **„ändern"** → zurück in den Plan-Loop (Phase 3 überarbeiten → Phase 4 erneut). **Headless / keine interaktive Antwort** → wie ein offener Gate behandeln: nicht autonom bauen, sondern wie `--prepare` stoppen (STATE aktualisieren, Resume-Kommando ausgeben). (Konservativ: ohne Freigabe wird nicht gebaut.)

**Summary-Inhalt** (verdichtet aus den vorhandenen Artefakten, nicht neu recherchiert):
- **Problem/Ziel** — aus `INTENT.md` / `PROBLEM.md`
- **Entscheidungen** — Kernentscheidungen aus `RESEARCH.md` / dem Plan
- **Plan/Design** — Task-Breakdown + Architektur-Fit aus `PLAN.md`
- **Tests/Acceptance** — die Kriterien aus `ACCEPTANCE.md` inkl. der `AC-N → test_name`-Links
- **Risiken** — aus `RESEARCH.md` / `DIAGNOSIS.md`
- **+ Artefakt-Pfade** zum Aufklappen der Volldateien

**Verhältnis zur Terse-Output-Regel.** Dies ist eine bewusste, **eng begrenzte** Ausnahme — wie der Phase-7-Commit-Gate, der ebenfalls von der ≤6-Zeilen-Budget-Regel ausgenommen ist. Die Summary bleibt „strukturierte Zusammenfassung + Pfade"; **kein** Voll-Artefakt-Dump (Invariante (b) gilt weiter).

**Schalter (projekt-lokal, persistent, default `on`).**
- Speicherort: `.kimiflow/build-gate` am Git-Root, einzeilig `on` | `off`. Fehlt die Datei oder ist der Inhalt ungültig → `on` (Default, fail-safe Richtung „mehr Kontrolle").
- Gelesen/geschrieben über **einen getesteten Helper** (gleicher Stil wie `resolve-verbosity.sh`): entweder ein neues `hooks/resolve-build-gate.sh` oder eine Generalisierung — Entscheidung im Implementierungsplan. Mit Unit-Tests analog `test-resolve-verbosity.sh`.
- Setzbar über den `--settings`-Dialog (um eine build-gate-Frage erweitern; Scope hier **nur project**, kein global).

## Design — Feature B: Native Phasen-Tasklist

**Mechanik.** In **Phase 0** legt der Orchestrator die aktiven Phasen via `TaskCreate` als Tasks an (eine pro Phase). Beim Betreten einer Phase `TaskUpdate` → `in_progress`, beim Abschluss → `completed`. Ergebnis: das Glance-Widget „N tasks (M done, 1 in progress, …)".

**Granularität, scope-abhängig.**
- `trivial`: minimaler Satz (z. B. Implement/Fix · Verify · Commit) — kein voller Loop.
- `small` / `large`: die tatsächlich durchlaufenen Phasen.
- Subagenten führen ihre **eigenen** internen Tasklists; diese werden NICHT mit der Orchestrator-Phasenliste vermischt.

**Verhältnis zu Bestehendem — ergänzt, ersetzt nicht.**
- `STATE.md` bleibt die **dauerhafte, resume-fähige** Quelle (überlebt Sessions; die Tasklist ist ephemer pro Session). Keine Redundanz: STATE.md = Persistenz/Resume, Tasklist = Live-Glance.
- Farbige Phasen-Marker bleiben (Pro-Phase-Event-Zeile beim Betreten).
- Terse-Regel **(e)** „No STATE narration in chat" wird präzisiert: das **strukturierte Tasklist-Widget ist erlaubt** (es ist keine Prosa-Narration und ersetzt den Drang zu narrativem Status-Geschwätz). Verboten bleibt prosaisches Nacherzählen von Status/Recap-Tabellen.

## Betroffene Dateien (Orientierung für den Plan)

- **SKILL.md:**
  - Phase 0 — Tasklist anlegen (`TaskCreate` der aktiven Phasen); build-gate-Resolve neben dem Verbosity-Resolve.
  - Neuer Phase-4½-Schritt (Summary-Gate) inkl. headless-Verhalten.
  - Core-Principle (e) präzisieren (Tasklist-Widget erlaubt).
  - Terse-Output-Budget: Summary-Gate als Ausnahme nennen (wie Commit-Gate).
  - Modes / `argument-hint` / `--settings`-Beschreibung um build-gate ergänzen.
- **reference.md:**
  - Neuer Abschnitt „Pre-build summary gate" (Inhalt, Schalter, headless, `--prepare`-Verhältnis).
  - Neuer Abschnitt / Notiz „Phase task list".
  - Self-contained-Regel: Notiz, dass build-gate **projekt-lokal** lebt (konform — global bleibt verboten).
  - Display-verbosity `--settings`-Beschreibung um build-gate erweitern.
- **hooks/** — build-gate-Resolver (`resolve-build-gate.sh` o. ä.) + Unit-Tests.
- **CHANGELOG.md** — Eintrag (Version später, vermutlich 0.1.3).

## Tests

- **build-gate-Resolver (Unit, analog AC-14):** default `on`; project `off` → `off`; ungültiger Inhalt → `on`; set/read-Roundtrip; read-only-Modi persistieren nicht.
- **Gate-Verhalten + Tasklist** sind orchestrator-behavioral (kein Skript erzwingt sie) → im Implementierungsplan über UAT / manuelle Verifikation abdecken; Headless-Fall (kein Build ohne Freigabe) explizit prüfen.

## Risiken & Gegenmaßnahmen

- **Terse-Ausnahme als Freibrief** für lange Summaries → Bound: strukturiert, Pfade, kein Voll-Dump; im Skill explizit so formulieren.
- **Tasklist-Granularität** vermischt Orchestrator- und Subagent-Tasks → Regel: nur Orchestrator-Phasen in die Phasenliste.
- **Resolver: neues Skript vs. resolve-verbosity erweitern** → bewusste Plan-Entscheidung; Default-Tendenz: eigenes kleines `resolve-build-gate.sh` (klare Single-Responsibility, eigener Test), kein Aufblähen des Verbosity-Helpers.
- **Behavioral, nicht mechanisch:** der Summary-Gate hängt am Orchestrator-Befolgen (wie der Onboarding-Prompt vor `onboard-check`). Mildern durch imperative Formulierung („du MUSST stoppen, wenn build-gate==on ∧ interaktiv") und projekt-lokalen, fail-safe-`on`-Default.

## Out of Scope (YAGNI)

- Per-Run-Flag für den Gate.
- Globaler build-gate-Schalter.
- Konfigurierbare Summary-Sektionen / Styling der Tasklist.
- Änderung an Qualitäts-Gates, Thresholds oder Engine-Verhalten.

## Runde-2-Adaptionen (superpowers + ponytail)

In diesen Batch aufgenommen (kleine, qualitäts-neutrale Skill-Edits):

- **A3 — Caller-verified deletion gate (ponytail).** Jede Code-Löschung trägt einen Beleg von **null lebenden Callern** — ein `grep`/Suchlauf über `src` (und Tests), der nichts zurückgibt, der Änderung beigelegt. Löschung ohne Beleg = **BLOCKER** im Code-Review. Überlebt etwas den Grep, hält ein Reviewer es aber für load-bearing → auf eine kurze **do-NOT-touch**-Liste mit Begründung statt löschen. Erweitert Surgical-changes von „toten Code nennen" zu „mechanisch belegt löschen"; Anti-Halluzination für Löschungen.
- **A4 — `Consumes:`/`Produces:`-Interface-Block in PLAN.md-Tasks (superpowers).** Jeder Plan-Task nennt die Signaturen, die er von früheren Tasks nutzt (`Consumes:`) und die exakten Namen/Typen, auf die spätere bauen (`Produces:`). Ein worktree-Implementer sieht nur seinen Task — so lernt er Nachbar-Signaturen ohne geteilten Kontext.
- **A5 — Considered alternatives bei `large` (superpowers).** Bei `large`-Scope hält RESEARCH.md/PLAN.md 2–3 erwogene Ansätze + den Trade-off fest, der den gewählten begründet. small/trivial ausgenommen.

**In eigene Spec ausgelagert (unabhängiges Subsystem):** **Audit/Cleanup-Modus** — ein dritter Modus neben feature/fix mit der vollen ponytail lens (why-does-this-exist → caller-verified Slices → do-NOT-touch-Listen → `yagni`/`delete`/`shrink`/`stdlib`-Tags → Verify-Gate pro Slice). Zu groß zum Einfalten; eigenes Brainstorming.

**Verworfen (YAGNI):** Visual Companion (kimiflow ist nicht UI-Design-fokussiert); ein separates Design-Doc-für-`large` (der Pre-Build-Gate liefert den Review-Checkpoint schon).

## Lokalisierung

Die Summary erscheint in der **Sprache des Users** (kimiflow-Prinzip „reply in the user's language"); Code-Identifier, Pfade und Section-Namen bleiben Englisch.
