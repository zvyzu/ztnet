# Context & Domain Model: ZTnet Installer Migration (Rocky Linux & Cloud DB)

## 1. Domain Glossary
- **ZTnet**: Web-based controller and user interface for ZeroTier networks, built with Next.js (TypeScript) and Prisma ORM.
- **ZeroTier One (`zerotier-one`)**: Low-level network virtualization service daemon running on port 9993/UDP, managing virtual interfaces and network controllers.
- **ztmkworld**: Custom binary compiled per architecture (`amd64`, `arm64`) used by ZTnet to manage planetary and root server definitions.
- **Cloud Database (Supabase / External PostgreSQL)**: Remote PostgreSQL instance accessed via standard PostgreSQL connection URI (`DATABASE_URL`), replacing the previously bundled local PostgreSQL server.
- **Prisma Migration (`prisma migrate deploy`)**: Prisma ORM schema synchronization tool applied directly against the target database during deployment.
- **Enterprise Linux (EL) / Rocky Linux**: RHEL-compatible Linux distribution utilizing `dnf`/`rpm` package manager, `systemd`, `firewalld`, and `SELinux`.

## 2. Component Architecture Overview
```
+-----------------------------------------------------------+
|                       Rocky Linux Host                    |
|                                                           |
|  [ZeroTier One Daemon] <---> [ztmkworld binary]           |
|         ^                                                 |
|         | (Local controller API)                          |
|         v                                                 |
|  [ZTnet Next.js Service (port 3000)]                      |
|         |                                                 |
|         +-- Prisma Client (Native / RHEL OpenSSL 3.0)     |
+---------|-------------------------------------------------+
          |
          | Encrypted SSL connection (DATABASE_URL)
          v
+-----------------------------------------------------------+
|          Cloud Database (Supabase / Remote Postgres)      |
+-----------------------------------------------------------+
```

## 3. Installer State Flow
1. **Pre-flight Checks**:
   - Check EUID == 0 (root/sudo).
   - Verify OS is Rocky Linux / RHEL-family via `/etc/os-release`.
   - Map architecture (`uname -m` -> `amd64`/`arm64`).
   - Memory warning check.
2. **Package Provisioning (`dnf`)**:
   - Install base tools: `git`, `curl`, `jq`, `openssl`, `tar`, `findutils`.
   - Setup NodeSource repo & install Node.js 20.
   - Setup ZeroTier RPM repo (`/etc/yum.repos.d/zerotier.repo`) & install `zerotier-one`.
3. **Database Configuration**:
   - Check existing or prompt for `DATABASE_URL` (Supabase connection string).
   - Validate network reachability of database host & port via Node.js before running migrations.
4. **ZTnet Build & Deployment**:
   - Clone / fetch ZTnet repo to `/tmp/ztnet/repo`.
   - Install npm dependencies.
   - Run `npx prisma migrate deploy` and `npx prisma db seed` with cloud `DATABASE_URL`.
   - Build Next.js application (`npm run build`).
   - Copy artifacts to `/opt/ztnet`.
   - Install `ztmkworld` binary to `/usr/local/bin/ztmkworld`.
5. **Service & Network Security**:
   - Generate `/etc/systemd/system/ztnet.service`.
   - Configure `firewalld` (ports 3000/tcp, 9993/udp).
   - Configure SELinux policies if enforcing.
   - Start and enable `ztnet` service.
