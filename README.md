# grobing-code

Kod aplikacji **Grobing** (Flutter, Android, local-first). Projekt powstał świeżym `flutter create`
na przypiętej wersji SDK (ISSUE-002), **nie** jako kopia innego projektu.

- Agenci i reguły: `../grobing-agents/` (tam otwierasz sesje, `/pm`).
- Dokumentacja i decyzje: `../grobing-vault/`.
- ⚠️ **Żadnych danych rodziny w tym repo** — ani bazy, ani kopii, ani eksportów, ani zdjęć prawdziwych
  osób. Dane żyją w aplikacji na telefonie. `.gitignore` obok to pierwsza linia obrony, nie jedyna.

## Wersja Fluttera — przypięta

Flutter na tej maszynie jest **współdzielony z inną, wydaną aplikacją autora**, więc globalnego SDK
się nie aktualizuje bez decyzji (ADR-002).

- **Jeden sposób:** `pubspec.yaml` → `environment.flutter: 3.41.1`. Każde `flutter pub get`
  (a więc `run`, `test`, `build`) na innej wersji **odmawia** z komunikatem
  *„Because grobing requires Flutter SDK version 3.41.1, version solving failed."*
- Zadeklarowana wartość żyje w `../grobing-agents/.claude/rules/project-config.example.md`
  (`flutter_version_pinned`). **Zmiana wersji = obie linie w jednej paczce** + datowana linia w ADR-002.
- Czego to nie daje: dwóch wersji obok siebie. Gdy druga aplikacja będzie potrzebowała nowszego
  Fluttera, ten projekt przestanie się budować — wtedy decyzja: podbić wersję albo dołożyć menedżer
  wersji (FVM).

## Uruchomienie

```sh
flutter pub get
flutter analyze
flutter test
flutter run            # debug — emulator albo telefon testowy
```

## Baza danych

SQLite przez `drift` (ADR-005 w vaulcie). Paczka `sqlite3` **dołącza własny SQLite** (build hooks), więc
`VACUUM INTO`, na którym stoi kopia (ADR-004), nie zależy od wersji Androida. Przy pierwszym budowaniu
hook pobiera gotową bibliotekę z wydań `sqlite3.dart` na GitHubie i sprawdza jej SHA-256 zapisane w
paczce. Później korzysta z `.dart_tool/`, więc build offline działa dopiero po pierwszym udanym buildzie.

- **Gdzie leży:** `grobing.db` i katalog `media/` w katalogu wsparcia aplikacji (prywatny magazyn,
  `path_provider`). Schemat: `lib/data/database.dart`.
- **`drift` i `drift_dev` są przypięte parą** (`pubspec.yaml`, komentarz): przypięty Flutter trzyma
  `analyzer` na 10.x. Zmiana jednej bez drugiej psuje generowanie kodu i weryfikator migracji.
- **Po każdej zmianie tabel:**

  ```sh
  dart run build_runner build --delete-conflicting-outputs   # database.g.dart
  ```

  Pliki `*.g.dart` commitujesz razem ze zmianą.
- **Zmiana schematu = migracja, nigdy „usuń i stwórz od nowa”** (NFR-003):
  1. podbij `schemaVersion` w `GrobingDatabase`;
  2. `dart run drift_dev make-migrations`: zapisuje schemat nowej wersji w `drift_schemas/grobing/`
     i generuje testy migracji w `test/drift/grobing/`;
  3. dopisz krok w `onUpgrade` i uruchom testy.

  Wersja bez kroku migracji kończy się błędem przy otwarciu bazy, zamiast skasować dane.
- **Odcisk danych** (ekran „Stan danych”, `lib/data/data_state.dart`) jest miarą dla kopii i
  odtworzenia (NFR-002). Liczy się z **treści**, nie z pliku: tabele po nazwie, wiersze po wszystkich
  kolumnach, wartości w stałym kodowaniu, potem pliki zdjęć po ścieżce. `VACUUM INTO` go nie zmienia.
  **Zmiana tej definicji unieważnia wszystkie wcześniej zapisane odciski.**
- **Wymyślone dane** (`lib/dev/`) są dostępne tylko w buildzie debug: przycisk na ekranie „Stan danych”.
  W buildzie release tego kodu nie ma.

## Podpis wydania

Aktualizacja wchodzi na telefon tylko wtedy, gdy jest podpisana **tym samym kluczem** co zainstalowana
wersja ([Sign your app](https://developer.android.com/studio/publish/app-signing)). Inny klucz = trzeba
odinstalować aplikację, a **odinstalowanie kasuje bazę**.

> ⚠️ **Na telefonie z prawdziwymi danymi instaluj wyłącznie build release** (`flutter run --release`
> albo `flutter build apk --release`). Przejście z buildu debug na release też wymaga odinstalowania.

1. **Klucz tworzy autor sam** — `keytool` pyta o hasła, więc nie przechodzą przez żadną sesję ani
   historię. Katalog: `release_keystore_dir` z `../grobing-agents/.claude/rules/project-config.md`
   (lokalny, poza każdym drzewem projektu):

   ```powershell
   keytool -genkey -v -keystore <release_keystore_dir>\grobing-release.jks -storetype JKS `
     -keyalg RSA -keysize 2048 -validity 10000 -alias grobing
   ```

2. **`android/key.properties`** (gitignorowany — nigdy do repo). W `storeFile` ukośniki `/`, bo `\` jest
   w tym formacie znakiem ucieczki:

   ```properties
   storePassword=<hasło magazynu>
   keyPassword=<hasło klucza>
   keyAlias=grobing
   storeFile=<release_keystore_dir z ukośnikami />/grobing-release.jks
   ```

3. **Kopia klucza** (`.jks` + hasła) w zaszyfrowanym miejscu autora, tym samym co kopia notatek
   (NT-001) — nie na tym samym dysku.

Bez `android/key.properties` build release **kończy się błędem** — nigdy nie podpisuje się po cichu
kluczem debug (`android/app/build.gradle.kts`).

## Tożsamość aplikacji

Nazwa pakietu i root widget są zapisane w
`../grobing-agents/.claude/rules/project-config.example.md` (*Product invariants*) — agenci ich nie
wymyślają. **Nazwy pakietu nie zmienia się nigdy**: inna nazwa to dla Androida inna aplikacja, która nie
widzi bazy poprzedniej.
