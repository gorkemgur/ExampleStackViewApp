# Neden bu app? — Apple'ın yaptığından farkı

## Apple bugün ne veriyor

**Fotoğraflar → Araçlar → Kopyalar**: fotoğraf kütüphanesindeki birebir ve birebire yakın
kopyaları bulur, "birleştir" der. Kapalı kutu: neyi neden eşleştirdiğini göstermez, hangisini
koruyacağını seçtirmez, **kaç GB kazanacağını söylemez**, kütüphane dışına bakmaz.

**Ayarlar → iPhone Depolama**: uygulama başına boyut, "büyük ekleri gözden geçir". Kopya
tespiti yok, fotoğraf içi analiz yok.

Aradaki boşluk şu: Apple sana *kopya listesi* veriyor. Senin gerçek sorun cümlen ise
**"10 GB yer açmam lazım, en az neyi kaybederek açarım?"**

## Bu app'in ana fikri: pişmanlık sıralı yer bütçesi

Ana ekran bir liste değil, bir **hedef**. "12 GB lazım" dersin; app o hedefe ulaşan en ucuz
silme setini **pişmanlık riskine göre sıralayarak** kurar ve sana katman katman gösterir:

| Katman | Ne kaybedersin | Örnek |
|---|---|---|
| 0 — Sıfır kayıp | Hiçbir şey. Bayt bayt aynı dosya. | Aynı fotoğrafın 3 kopyası |
| 1 — Sıfır kayıp | Hiçbir şey. Daha iyisi kalıyor. | WhatsApp'tan dönen 1280px kopya, 4032px orijinal dururken |
| 2 — Çok düşük | Aynı anın daha bulanık kareleri | Burst'ün 11 karesinden en netini tut |
| 3 — Düşük | Eski, albümsüz, favorisiz ekran görüntüleri | 2019'daki dekont ekran görüntüsü |
| 4 — Kullanıcı kararı | Benzer ama aynı değil | Aynı manzaranın 4 farklı çekimi |

Slider'ı 12 GB'a çekersin, app "Katman 0 ve 1 yeter: 9.4 GB. Katman 2'den 6 seri daha
eklersen 13.1 GB" der. Bunu hiçbir yerleşik özellik yapmıyor.

## Farkı yaratan beş şey

1. **Kazanç önce gelir.** Her ekran "bu ne kadar yer" ile başlar. Apple hiç söylemez.
   Üstelik dürüst bölünmüş: *hemen boşalan*, *Son Silinenler'den sonra boşalan*,
   *sadece iCloud'da yer açan*.

2. **Neden eşleşti, görünür.** Yan yana karşılaştırma + piksel farkı ısı haritası +
   "hangi metrikte ne kadar fark var" tablosu. Kapalı kutu yok; kullanıcı kendi gözüyle
   doğrular.

3. **Hangisi kalacak, senin kararın.** Skorlama kuralları açık ve ekranda:
   favori/albüm > düzenlenmiş > en yüksek çözünürlük > en büyük dosya > en eski tarih.
   İstediğin an keeper'ı değiştirirsin.

4. **Geri dönüş garantisi.** Silmeden önce, silinecek dosyaların **orijinal baytları** senin
   seçtiğin bir klasöre dışa aktarılabilir; yanına ne silindiğini yazan bir manifest konur.
   Yanlış bir karar telafi edilebilir olur — Apple'da "Son Silinenler" 30 gün sonra biter.

5. **Kütüphane dışını da görür.** Files'tan verdiğin klasörler (iCloud Drive, On My iPhone,
   harici disk) aynı motordan geçer; aynı dosyanın hem Fotoğraflar'da hem Drive'da durduğunu
   yakalar.

## Değişmez kural

Bu app hiçbir koşulda:

- doğrudan karşılaştırılmamış bir öğeyi silmeyi önermez (star clustering; `DuplicateClusterer`),
- bir grubun tüm üyelerini silmeyi önermez (`CleanupValidator`),
- favori veya albümdeki bir öğeyi kendiliğinden işaretlemez (`CleanupPlanner`),
- benzer (birebir olmayan) grupta hiçbir şeyi önceden işaretlemez.

Bu dördü teoride değil, `DupeCore`'da testle sabitlenmiş durumda. Silme çağrısı yapılmadan
önce seçim, UI'dan bağımsız olarak sıfırdan yeniden doğrulanır.
