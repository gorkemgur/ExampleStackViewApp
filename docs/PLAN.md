# DupeSpace — Duplicate Finder & Storage Analyzer (iOS)

Kişisel kullanım için, tek cihazda çalışan, tamamen on-device bir uygulama.
Fotoğraf/video/belge kopyalarını bulur, ne nerede yer kaplıyor gösterir,
seçili kopyaları silerek ne kadar kazanç sağlanacağını hesaplar.

## 0. Kararlar

| Konu | Karar |
|---|---|
| UI | SwiftUI, iOS 17+ (yeni app target `DupeSpace`) |
| Mevcut kod | `ExampleStackView` target'ına dokunulmaz |
| Kaynaklar | Photos (PhotoKit) + kullanıcının Files'tan seçtiği klasörler |
| Tespit | Exact (SHA-256) + benzer (dHash/pHash + Vision FeaturePrint) + video keyframe benzerliği |
| Silme | Otomatik "en iyi kopya" önerisi + manuel onay |
| Depolama | libsqlite3 üzerine ince bir indeks katmanı (harici bağımlılık yok) |
| Ağ | Yok. Hiçbir veri cihazdan çıkmaz. |

---

## 1. Platform gerçekleri (planın sınırlarını bunlar çiziyor)

iOS sandbox'ı nedeniyle **tüm cihaz dosya sistemi taranamaz**. Erişilebilenler:

1. **Photos kütüphanesi** — PhotoKit, tam erişim izniyle. Fotoğraf/video/Live Photo/burst.
2. **Kullanıcının seçtiği klasörler** — `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`
   ile seçilir, `bookmarkData` ile kalıcı erişim saklanır (iCloud Drive, On My iPhone, harici sürücü).
3. **Kendi app container'ımız** — kendi cache/indeks alanımız.

Erişilemeyenler — UI'da açıkça söylenecek:
- Diğer uygulamaların (WhatsApp, Instagram, Mail...) kapladığı alan. API yok.
- Sistem/OS alanı, "Other/System Data".
- Photos dışındaki keyfi dizinler.

Diğer kritik davranışlar:
- **Silinen fotoğraflar "Son Silinenler"e gider (30 gün).** Alan *anında* boşalmaz.
  Kazanç ekranında bu net yazılacak + "Son Silinenler'i boşalt" yönlendirmesi.
- **iCloud Fotoğraflar / Optimize Storage**: asset'in orijinali cihazda olmayabilir.
  `PHAssetResource` boyutu *orijinal* boyuttur; cihazda kapladığı yer daha az olabilir.
  Tarama varsayılan olarak `isNetworkAccessAllowed = false` (veri harcamaz),
  indirilmemiş asset'ler "bulutta" etiketiyle ayrı raporlanır.
- **Limited Photos access** ile anlamlı tarama yapılamaz; tam erişim istenecek.
- Boş alan ölçümü: `volumeAvailableCapacityForImportantUsage` *purgeable* alanı da içerir,
  gerçek boştan büyük çıkabilir; bunu tahmin olarak sunacağız.

---

## 2. Algoritmalar

### 2.1 Fotoğraflarda birebir kopya (exact)

Klasik 3 kademeli eleme — pahalı işi mümkün olan en az öğeye uygula:

```
Kademe 0  (bedava)  : (mediaType, pixelWidth, pixelHeight, resourceFileSize) ile grupla
                      → tekil kalan her şey elenir (tipik olarak %90+)
Kademe 1  (ucuz)    : partial hash = SHA256(ilk 64KB ‖ son 64KB ‖ fileSize)
Kademe 2  (pahalı)  : tam streaming SHA-256 (1MB chunk, PHAssetResourceManager)
```

- Boyut: `PHAssetResource` üzerinden; `requestData` ile stream ederken zaten sayılır.
- Aynı asset'in birden fazla resource'u olabilir (photo + adjustmentData + pairedVideo);
  kimlik için **orijinal** resource (`.photo` / `.video` / `.fullSizePhoto` yoksa ilki) kullanılır.
- Live Photo = still + video çifti; ikisi birden eşleşirse kopya sayılır.

### 2.2 Fotoğraflarda benzer kopya (near-duplicate)

Birebir olmayan ama "aynı kare" olanlar: burst çekimleri, WhatsApp/Telegram yeniden
sıkıştırmaları, ekran görüntüsü tekrarları, düzenlenmiş kopyalar, farklı çözünürlükte kayıtlar.

**Aşama A — ucuz imza (tüm kütüphane):**
- Görüntü `PHImageManager` ile 32×32 gri thumbnail olarak çekilir (`.fastFormat`, opportunistic kapalı).
- **dHash (64-bit)**: 9×8 gri matris, yatay komşu farkları → 64 bit.
- **pHash (64-bit)**: 32×32 gri → 2B DCT → sol-üst 8×8 (DC hariç) → medyan eşiği → 64 bit.
- Her ikisi de DB'ye yazılır. Maliyet: asset başına ~1-3 ms + thumbnail decode.

**Aşama B — aday bulma (O(n) yerine O(n·k)):**
- 64-bit hash 4×16-bit banda bölünür (multi-index hashing). Hamming ≤ 3 aranıyorsa,
  güvercin yuvası ilkesiyle en az bir bant birebir eşleşmek zorunda → bant başına hash tablosu.
- Daha geniş eşik (≤ 12) için **BK-tree** (metrik: Hamming) ile aralık sorgusu.
- Aday üretimi: dHash ≤ 10 **veya** pHash ≤ 10. (İkisi farklı hatalara duyarlı; birleşim recall'i artırır.)

**Aşama C — doğrulama (sadece adaylar):**
- `VNGenerateImageFeaturePrintRequest` → `VNFeaturePrintObservation.computeDistance`.
- Eşikler (kalibrasyon gerekir, başlangıç değerleri):
  - `distance < 0.20` → neredeyse kesin aynı kare
  - `0.20 – 0.45` → benzer, kullanıcıya "benzer" rozetiyle gösterilir, **otomatik seçilmez**
  - `> 0.45` → reddedilir
- Ek sinyaller skorlamaya girer: `creationDate` farkı < 5 sn, aynı `burstIdentifier`,
  aynı en-boy oranı, EXIF aynı cihaz/lens.

**Aşama D — kümeleme:**
- Adaylar bir graf oluşturur (kenar = benzerlik eşiği geçen çift).
- **Union-Find** ile bağlı bileşenler → gruplar. (Tam klik aramıyoruz; zincir etkisini sınırlamak
  için bileşen içi ortalama mesafe eşiği aşarsa grup ikiye bölünür.)
- Birebir kopyalar her zaman ayrı, "exact" etiketli alt-grup.

### 2.3 Videolarda benzerlik

```
Ön eleme : |duration farkı| ≤ 0.5 sn  ve  aynı en-boy oranı
Exact    : fileSize eşit → partial hash → tam SHA-256
Benzer   : AVAssetImageGenerator ile normalize edilmiş 9 zaman damgasından
           (0.05, 0.15, ... 0.85, 0.95) kare örnekle → her kareye pHash
           → dizi karşılaştırma: ortalama Hamming ≤ 8 ve hiçbir kare > 16
```
- `requestedTimeToleranceBefore/After = .zero` **kullanılmaz** (çok yavaş);
  ±0.5 sn tolerans ile keyframe'e snap edilir — kısa videolarda kaydırma riskine karşı
  dizi karşılaştırmasında ±1 kare kayma denenir.
- `generateCGImagesAsynchronously` tek geçişte tüm zaman damgalarını üretir.
- Transcode edilmiş kopyalar (farklı bitrate/çözünürlük) bu yolla yakalanır.

### 2.4 Belgeler / Files klasörleri

```
Kademe 0 : dosya boyutu ile grupla (FileManager.enumerator, .fileSizeKey)
Kademe 1 : SHA256(ilk 64KB ‖ son 64KB ‖ size)
Kademe 2 : tam streaming SHA-256
Ek       : "yakın isim" sezgisi — "rapor.pdf" / "rapor (1).pdf" / "rapor copy 2.pdf"
           farklı içerikte bile olsa "gözden geçir" listesine düşer (silinmez, sadece işaret)
```
- iCloud placeholder'lar (`.isUbiquitousItemKey` + indirilmemiş) atlanır, ayrı raporlanır.
- Silmede `NSFileCoordinator` ile koordineli `removeItem`.
- `.startAccessingSecurityScopedResource()` / `stop...` her erişim etrafında dengelenir.

### 2.5 "En iyi kopya"yı seçme (hangisi kalsın)

Grup içindeki her öğe puanlanır, **en yüksek puanlı korunur**, gerisi önceden işaretlenir:

| Sinyal | Ağırlık |
|---|---|
| Favori / bir albümde | +1000 (asla otomatik silinmez) |
| Düzenlenmiş (adjustmentData var) | +300 |
| Piksel sayısı (en yüksek) | +200 |
| Dosya boyutu (en büyük) | +100 |
| Live Photo (still-only kopyaya karşı) | +150 |
| Orijinal kaynak (`sourceType == .typeUserLibrary`) | +80 |
| En eski `creationDate` | +50 |
| Ekran görüntüsü olması | −100 |
| Konum/EXIF metadata zengin | +40 |

Kural: **grupta en az bir öğe her zaman korunur**; UI bunu kilitli gösterir,
kullanıcı isterse değiştirir. "Benzer" (exact olmayan) gruplarda hiçbir şey
önceden işaretlenmez — sadece öneri rozeti gösterilir.

### 2.6 Kazanç hesabı

```
potansiyel_kazanç = Σ (silinecek öğelerin resource boyutları)
```
- Live Photo'da still + video ikisi de sayılır.
- Bulutta olup cihazda olmayan asset'ler **ayrı** toplanır ("iCloud'da yer açar, cihazda değil").
- Fotoğraf silmeleri için: "30 gün sonra boşalır veya Son Silinenler'i şimdi boşalt".
- Dosya silmeleri: anında boşalır.
- Silme öncesi/sonrası gerçek boş alan ölçülüp gösterilir (doğrulama).

---

## 3. Mimari

```
DupeSpace/
├─ App/                  SwiftUI giriş, routing, izin akışı
├─ Features/
│  ├─ Overview/          Depolama özeti, kategori treemap
│  ├─ Scan/              Tarama ilerlemesi, iptal/duraklat
│  ├─ Duplicates/        Grup listesi, grup detayı, seçim
│  ├─ Cleanup/           Onay ekranı, silme, sonuç raporu
│  └─ Folders/           Files klasör yönetimi (bookmark'lar)
├─ Core/
│  ├─ Index/             SQLite şeması, repository, migration
│  ├─ Hashing/           SHA256 stream, dHash, pHash (DCT), Hamming
│  ├─ Matching/          BKTree, MultiIndexHash, UnionFind, clustering
│  ├─ Sources/           PhotoSource, FileSource (ortak `AssetSource` protokolü)
│  ├─ Media/             Thumbnail, FeaturePrint, video keyframe
│  ├─ Scoring/           KeeperScorer
│  └─ Runtime/           ThrottledTaskRunner (termal/pil), BGTask
└─ Tests/                Saf mantık birim testleri (hash, BK-tree, union-find, scorer)
```

`AssetSource` protokolü sayesinde Photos ve Files aynı pipeline'dan geçer;
ileride yeni kaynak eklemek tek tip uyumu.

### İndeks şeması (SQLite)

```sql
CREATE TABLE asset (
  id TEXT PRIMARY KEY,            -- PHAsset.localIdentifier veya bookmark+path hash
  source INTEGER NOT NULL,        -- 0=photos 1=file
  kind INTEGER NOT NULL,          -- 0=image 1=video 2=document
  path TEXT,                      -- files için göreli yol
  bytes INTEGER NOT NULL,
  width INTEGER, height INTEGER, duration REAL,
  created_at REAL, modified_at REAL,
  subtypes INTEGER,               -- screenshot/live/burst bayrakları
  burst_id TEXT,
  is_local INTEGER,               -- cihazda mı, bulutta mı
  quick_hash BLOB,                -- partial SHA-256
  full_hash BLOB,                 -- tam SHA-256
  dhash INTEGER, phash INTEGER,   -- 64-bit
  feature_print BLOB,             -- opsiyonel, sadece adaylar için
  content_version TEXT,           -- modificationDate+bytes → değişiklik tespiti
  indexed_at REAL
);
CREATE INDEX idx_bytes ON asset(bytes);
CREATE INDEX idx_full  ON asset(full_hash);
CREATE TABLE dhash_band (band INTEGER, value INTEGER, asset_id TEXT);  -- multi-index
CREATE TABLE group_member (group_id TEXT, asset_id TEXT, score REAL, is_keeper INTEGER);
CREATE TABLE ignored_pair (a TEXT, b TEXT);   -- "bunlar kopya değil" kullanıcı kararı
```

`content_version` sayesinde **ikinci tarama artımlıdır**: değişmemiş asset yeniden hash'lenmez.
`PHPhotoLibraryChangeObserver` ile silinen/eklenenler indeksten senkronlanır.

### Performans bütçesi (hedef: 50.000 asset'lik kütüphane)

| Aşama | Hedef |
|---|---|
| Metadata indeksleme | < 30 sn |
| Kademe 0 gruplama | < 2 sn |
| dHash+pHash (thumbnail decode dahil) | ~6-10 dk ilk tarama, sonraki taramalar saniyeler |
| Exact tam hash | sadece aday gruplara, tipik < 1 dk |
| FeaturePrint doğrulama | sadece adaylara, < 1 dk |

- `TaskGroup` ile sınırlı eşzamanlılık: `min(4, activeProcessorCount)`.
- `ProcessInfo.thermalState >= .serious` veya `isLowPowerModeEnabled` → eşzamanlılık 1'e düşer,
  `.critical` → tarama duraklatılır, kullanıcıya bildirilir.
- Uygulama arka plana alınırsa `BGProcessingTaskRequest` ile devam
  (`requiresExternalPower = true`, `requiresNetworkConnectivity = false`).
- Bellek: asset verisi hiçbir zaman tam olarak belleğe alınmaz (chunk stream), thumbnail'lar autorelease pool içinde.

---

## 4. Fazlar

### Faz 0 — İskelet (yarım gün)
- `DupeSpace` SwiftUI app target'ı + `project.yml` (XcodeGen) / pbxproj.
- Info.plist: `NSPhotoLibraryUsageDescription`, BGTaskScheduler identifier'ları.
- Modül klasörleri, `AssetSource` protokolü, boş SwiftUI iskeleti, test target.
- **Çıktı:** derlenen boş uygulama.

### Faz 1 — Depolama özeti (1 gün)
- Disk kapasitesi / boş alan.
- Photos kütüphanesi envanteri: adet + toplam byte; kategori kırılımı
  (fotoğraf, video, ekran görüntüsü, Live Photo, burst, panorama, slo-mo).
- En büyük 100 öğe, yıllara göre dağılım, "cihazda / bulutta" ayrımı.
- Erişilemeyen alan için dürüst açıklama kartı.
- **Çıktı:** tarama olmadan bile faydalı bir "ne nerede" ekranı.

### Faz 2 — Exact duplicate motoru (1-2 gün)
- SQLite indeks + migration.
- Kademe 0/1/2 hash pipeline'ı, artımlı tarama.
- Union-Find gruplama, KeeperScorer.
- Grup listesi UI + grup detayı (yan yana karşılaştırma).
- **Çıktı:** birebir kopyalar bulunur ve listelenir. En yüksek güven, sıfır yanlış pozitif.

### Faz 3 — Silme akışı (yarım gün)
- Seçim durumu, "kazanç" canlı toplamı.
- `PHAssetChangeRequest.deleteAssets` toplu silme (sistem onayı bir kez).
- Son Silinenler uyarısı, silme öncesi/sonrası boş alan doğrulaması.
- Geri alınamaz işlem için net onay ekranı + silinenlerin listesini dışa aktarma (JSON log).
- **Çıktı:** uçtan uca çalışan temizlik döngüsü.

### Faz 4 — Benzer fotoğraf tespiti (2 gün)
- dHash/pHash implementasyonu + birim testleri (sentetik resize/JPEG/parlaklık varyasyonları).
- Multi-index hash + BK-tree aday üretimi.
- Vision FeaturePrint doğrulama, eşik kalibrasyonu.
- "Benzer" grupları ayrı sekme; burst grupları özel gösterim.
- `ignored_pair` — "bunlar kopya değil" kararı kalıcı.
- **Çıktı:** asıl kazancın geldiği özellik.

### Faz 5 — Video benzerliği (1 gün)
- Keyframe örnekleme + pHash dizisi + kayma toleranslı karşılaştırma.
- Video grupları için süre/çözünürlük/bitrate karşılaştırmalı detay ekranı.
- **Çıktı:** en yüksek byte kazancı (videolar en büyük dosyalar).

### Faz 6 — Files / belgeler (1 gün)
- Klasör seçici + security-scoped bookmark yönetimi (ekle/kaldır/yenile).
- Dosya tarama pipeline'ı, yakın-isim sezgisi.
- Koordineli silme.
- **Çıktı:** iCloud Drive / On My iPhone kapsama dahil.

### Faz 7 — Cila (1 gün)
- Artımlı yeniden tarama, `PHPhotoLibraryChangeObserver`.
- Arka plan tarama (BGProcessingTask).
- Termal/pil kısıtlama, iptal/duraklat.
- Boş/hata/izin durumları, erişilebilirlik, Dynamic Type.
- **Çıktı:** günlük kullanıma hazır.

---

## 5. Riskler ve azaltmalar

| Risk | Azaltma |
|---|---|
| Yanlış pozitif → değerli fotoğraf silinir | Benzer gruplarda otomatik seçim yok; grupta en az 1 öğe kilitli; favoriler asla seçilmez; silme öncesi tam ekran karşılaştırma; silinenlerin JSON logu |
| Tarama çok yavaş / cihaz ısınır | Kademeli eleme, artımlı tarama, termal kısıtlama, duraklat/devam |
| iCloud'dan indirme veri yakar | Varsayılan `isNetworkAccessAllowed = false`; indirme açıkça kullanıcı onayıyla |
| `PHAssetResource` boyutu KVC (`"fileSize"`) ile okunuyor — resmi olmayan API | Fallback: `requestData` sırasında byte sayımı; sadece kişisel kullanım |
| Silme sonrası alan boşalmıyor gibi görünüyor | Son Silinenler açıklaması + doğrulama ölçümü |
| Limited Photos erişimi | Tam erişim olmadan tarama başlatılmaz, neden açıkça anlatılır |

## 6. Test stratejisi

Derleyici olmayan ortamda (CI) çalıştırılabilir saf mantık testleri:
- `SHA256Stream` — chunk sınırlarında doğruluk.
- `dHash`/`pHash` — bilinen görüntü matrisleri, resize/parlaklık altında kararlılık.
- `Hamming`, `BKTree` (aralık sorgusu doğruluğu), `MultiIndexHash` (recall garantisi).
- `UnionFind` + kümeleme bölme kuralı.
- `KeeperScorer` — her sinyal için tablo testleri, "en az bir keeper" değişmezi.
- `SavingsCalculator` — Live Photo çifti, bulut/yerel ayrımı.

Cihazda manuel doğrulama: bilinen bir kopya seti (aynı fotoğrafın 3 varyantı) ile recall/precision ölçümü.

## 7. Gizlilik

Ağ isteği yok. Analitik yok. Tüm indeks app container'ında. Bu bir kişisel araç.
