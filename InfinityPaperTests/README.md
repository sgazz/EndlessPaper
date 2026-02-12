# InfinityPaperTests

Unit testovi za InfinityPaper (SessionPersistence, StoredSession encode/decode).

## Dodavanje test targeta u Xcode

Ako target **InfinityPaperTests** još ne postoji:

1. **File** → **New** → **Target**
2. Izaberi **Unit Testing Bundle**
3. **Product Name:** `InfinityPaperTests`
4. **Team** i **Project** ostavi kao za glavni target
5. Klikni **Finish**
6. U **Build Phases** → **Link Binary With Libraries** dodaj zavisnost od **InfinityPaper** (Target Dependency na InfinityPaper)
7. Uvuci `SessionPersistenceTests.swift` u InfinityPaperTests grupu (ili ostavi u folderu i uključi u target)

Testovi će se pokretati sa **⌘U** ili **Product** → **Test**.
