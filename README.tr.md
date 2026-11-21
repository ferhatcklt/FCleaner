<p align="center"><img src="Resources/AppIcon.png" width="140" alt="FCleaner simgesi"></p>

<h1 align="center">FCleaner</h1>

<p align="center">
  <b>Sistemi bozmamak için tasarlanmış, ücretsiz ve açık kaynak Mac temizleyici.</b><br>
  Kilitli özellik yok, "Pro'ya geç" yok, veri toplama yok.
</p>

<p align="center"><a href="README.md">English</a></p>

## Özellikler

**Temizlik**
- **Flash Temizlik:** Tek tıkla yalnızca *Önerilen* öğeleri (önbellek, log, derleme artığı) temizler.
- **Sistem Çöpü:** Uygulama önbellekleri, loglar, Xcode / npm / Gradle / pip artıkları, iOS Simülatörü cihazları, iOS güncelleme dosyaları, eski kurulum dosyaları, Mail ekleri, iOS yedekleri, Çöp Sepeti.
- **Büyük Dosyalar** ve **Kopya Dosyalar:** Kopyalar SHA-256 içerik karşılaştırmasıyla bulunur, her gruptan en az bir kopya korunur.
- **Silme Geçmişi:** FCleaner'ın sildiği her şey listelenir. Çöp Sepeti'ndekiler tek tıkla geri yüklenir.

**Uygulamalar**
- **Uygulama Kaldırıcı:** Uygulamayı `~/Library` ve `/Library` altındaki bütün izleriyle siler: destek dosyaları, önbellekler, ayarlar, kapsayıcılar, kayıtlı durum, arka plan servisleri, yardımcı araçlar, çökme raporları, geçici önbellekler. Başka bir yüklü uygulamaya ait veriye dokunmaz.
- **Başlangıç Öğeleri:** Açılışta çalışan üçüncü parti arka plan servisleri.

**Araç Takımı**
- **Bellek:** RAM'i neyin kullandığı (uygulama başına, yardımcı işlemler gruplanmış), bellek baskısı, takas. *RAM'i Boşalt* önbelleği temizler, isterseniz seçtiğiniz uygulamaları kapatır ve sonunda neyin boşaldığını, neyin kapatıldığını raporlar.
- **Disk Analizcisi:** Tek ekranda açılıp kapanan klasör ağacı. Boyutlar, yüzdeler ve klavyeyle gezinme.
- **Dosya Parçalayıcı:** Bırakılan dosyaların üzerine rastgele veri yazar, sonra siler.
- **Bakım:** Time Machine yerel anlık görüntüleri, DNS önbelleği, Spotlight'ı yeniden dizinleme, "Birlikte Aç" menüsü onarımı, Quick Look ve yazı tipi önbellekleri, Dock ve Finder'ı yeniden başlatma.
- **Menü çubuğu monitörü:** Disk ve RAM durumu bir bakışta, menü çubuğundan Flash Temizlik.
- **Kendi kendini güncelleme:** GitHub Releases üzerinden, imza doğrulamalı.

## Koruma sistemi

Hiçbir şey silinmeden önce her dosya sınıflandırılır:

| Seviye | Örnekler | Davranış |
|---|---|---|
| 🟢 **Önerilen** | önbellekler, loglar, derleme artıkları | Otomatik seçilir. Flash Temizlik yalnızca bunları siler |
| 🟠 **Gözden Geçir** | indirilenler, büyük dosyalar, uygulama verileri | Elle seçilmesi gerekir |
| 🔒 **Kritik** | Anahtar Zinciri, iCloud Drive, iPhone yedekleri, Mesajlar, Mail, Fotoğraflar, tarayıcı profilleri, parola yöneticileri, kripto cüzdanlar, SSH/GPG anahtarları, Apple uygulama verileri ve bunlardan birini içeren her klasör | **Kilitli.** Touch ID veya Mac parolasıyla kilit açılmadan seçilemez ve silinemez. Kilit 5 dakika sonra kendiliğinden kapanır |

Bunlara ek olarak sistem konumları (`/System`, `/usr`, `/Library` kökü, `~/Documents`, disklerin kendisi, başka kullanıcıların klasörleri vb.) kilit açık olsa bile **asla** silinemez. Ayarlar → Hariç Tutulanlar'a eklediğiniz klasörleri de FCleaner ne gösterir ne siler.

- Parçalayıcı ve Çöp Sepeti'ni boşaltma dışında her şey **Çöp Sepeti'ne taşınır**, yani geri alınabilir.
- Her silmeden önce onay istenir ve her silme Silme Geçmişi'ne kaydedilir.
- Yönetici gerektiren işlemlerde macOS'un kendi parola penceresi kullanılır. Parolanız FCleaner'a ulaşmaz.
- Tek ağ isteği GitHub'a yapılan güncelleme denetimidir (kapatılabilir).

Tüm kurallar tek dosyada: [`Services/Safety.swift`](Sources/FCleaner/Services/Safety.swift). Bütün silme işlemleri tek bir fonksiyondan geçer: [`Services/FileSystem.swift`](Sources/FCleaner/Services/FileSystem.swift) içindeki `Trasher.remove`. İkisi de testlerle korunuyor.

## Kurulum

[Releases](https://github.com/ferhatcklt/FCleaner/releases/latest) sayfasından son `FCleaner-x.y.z.zip` dosyasını indirin, açın ve **FCleaner.app**'i Uygulamalar klasörüne taşıyın.

> Sürümler henüz notarize edilmiyor. İlk açılışta uygulamaya sağ tıklayıp **Aç**'ı seçin. macOS yine engellerse **Sistem Ayarları → Gizlilik ve Güvenlik**'te **Yine de Aç**'a tıklayın.

Tüm özellikler için **Tam Disk Erişimi** verin. Genel Bakış'taki *Hızlı Kurulum* düğmesi doğru ayar sayfasını açar, FCleaner'ı listeye sürüklemeniz yeterli.

## Kaynaktan derleme

macOS 14+ ve Xcode 16+ gerekir.

```bash
git clone https://github.com/ferhatcklt/FCleaner.git
cd FCleaner
./scripts/build-app.sh      # → build/FCleaner.app
swift test                  # testleri çalıştırır
```

`build-app.sh` uygulamayı anahtar zincirindeki ilk *Apple Development* sertifikasıyla imzalar, böylece Tam Disk Erişimi izni yeniden derlemelerden sonra da korunur. Sertifika yoksa ad-hoc imza kullanır. Başka bir sertifika için `SIGN_IDENTITY=<hash>` verin.

Yeni sürüm yayınlamak için: `./scripts/release.sh 0.2.0`

## Katkı

Hata bildirimleri ve pull request'ler memnuniyetle karşılanır, bkz. [CONTRIBUTING.md](CONTRIBUTING.md). Güvenlik açıklarını [SECURITY.md](SECURITY.md)'deki gibi gizli olarak bildirin.

## Lisans

[MIT](LICENSE) © 2026 [FCApps](https://fcapps.com.tr) ve FCleaner katkıcıları
