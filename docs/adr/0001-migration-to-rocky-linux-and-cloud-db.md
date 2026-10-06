# ADR 0001: Migrasi Installer ZTnet ke Rocky Linux dan Cloud Database (Supabase)

## Status
**Accepted** (Disetujui melalui Grilling Interview)

## Konteks
Installer awal ([ztnet.sh](file:///f:/Development/ztnet/install.ztnet/bash/ztnet.sh)) dirancang untuk Debian dan Ubuntu dengan bundel instalasi lokal database PostgreSQL. Pengguna membutuhkan migrasi lingkungan ke **Rocky Linux (Enterprise Linux / RHEL family)** serta beralih dari database lokal ke **Cloud Database** (contoh: Supabase PostgreSQL).

## Keputusan Arsitektural (Decisions)

1. **Target Distribusi OS**:
   - Eksklusif untuk **Rocky Linux dan RHEL-family** (Rocky Linux 9/8, AlmaLinux, RHEL).
   - Package manager beralih sepenuhnya ke `dnf` dan pengecekan paket menggunakan `rpm -q`.
   - Deteksi OS menggunakan `/etc/os-release` (`ID=rocky`, `ID_LIKE=*rhel*`).
   - Pemetaan arsitektur `x86_64 -> amd64` dan `aarch64 -> arm64` untuk binary pendukung `ztmkworld`.

2. **Cloud Database (Supabase / Remote PostgreSQL)**:
   - Menghapus instalasi paket `postgresql` & `postgresql-contrib` serta logika pembuatan user/database lokal.
   - Mengambil input interaktif `DATABASE_URL` (direct/session connection string) dari pengguna jika belum ada di `/opt/ztnet/.env`.
   - Melakukan validasi konektivitas soket TCP/TLS secara otomatis via Node.js sebelum menjalankan `prisma migrate deploy` dan `prisma db seed`.
   - Menghindari kegagalan deployment tanpa memerlukan instalasi client heavy CLI `psql`.

3. **Instalasi ZeroTier di Rocky Linux**:
   - Menambahkan repositori resmi ZeroTier RPM ke `/etc/yum.repos.d/zerotier.repo` yang disesuaikan dengan versi EL (`8` atau `9`).
   - Memasang `zerotier-one` versi `$ZEROTIER_VERSION` (fallback ke latest versi repositori bila spesifik tidak tersedia) melalui `dnf`.
   - Mengaktifkan dan memulai layanan `zerotier-one` via `systemctl`.

4. **Node.js Runtime**:
   - Memasang Node.js v20 LTS menggunakan repository resmi NodeSource RPM (`https://rpm.nodesource.com/setup_20.x`).

5. **Keamanan Jaringan, Firewall & SELinux**:
   - Secara otomatis mendeteksi dan membuka port `3000/tcp` (ZTnet Web UI) dan `9993/udp` (ZeroTier One) pada `firewalld` jika aktif (`firewall-cmd --permanent --add-port=...`).
   - Menyesuaikan kebijakan SELinux (seperti `setsebool -P httpd_can_network_connect 1`) jika status SELinux aktif/enforcing.

6. **Uninstaller**:
   - Menyesuaikan mode uninstall (`-u`) untuk menghapus layanan `ztnet`, paket `zerotier-one` via `dnf`, dan direktori `/opt/ztnet` tanpa menyentuh Cloud Database.

7. **Resolusi Artefak Standalone (`server.js`) & Systemd WorkingDirectory**:
   - Menetapkan `SKIP_ENV_VALIDATION=1` dan menjalankan `prisma generate` sebelum `npm run build` untuk mencegah kegagalan kompilasi saat build.
   - Menambahkan deteksi otomatis keberadaan `server.js` jika Next.js Output File Tracing meletakkannya di subfolder bersarang, lalu meratakannya ke root `/opt/ztnet/`.
   - Mengatur `WorkingDirectory=/opt/ztnet` pada unit service systemd agar aset statis dan path runtime terbaca dengan benar.
   - Memastikan installer gagal secara eksplisit jika `server.js` tidak terbentuk alih-alih menyalakan service yang rusak.

## Konsekuensi
- Installer tidak lagi memerlukan resource RAM dan disk tinggi untuk menjalankan PostgreSQL lokal di VM/host yang sama.
- Pengguna bertanggung jawab memastikan database Supabase/Cloud PostgreSQL aktif dan kredensial valid sebelum instalasi.
- Skrip sepenuhnya kompatibel dengan standar enterprise Linux RHEL/Rocky Linux.

