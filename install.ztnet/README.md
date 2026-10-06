## ztnet installation script

This is the code and installation scripts running at install.ztnet.network.

### Installation Steps for Rocky Linux (and RHEL-Compatible Distributions)

1. Open a terminal window.
2. Install `curl` if it is not already installed:
   ```bash
   sudo dnf install -y curl
   ```
3. Ensure you have your Cloud Database (e.g. Supabase) connection string ready:
   ```text
   postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres?sslmode=require
   ```
4. Run the installation script:

   **!NOTE:** If your system does not have `sudo` installed, run as root directly without `sudo`:

   ```bash
   curl -s http://install.ztnet.network | sudo bash
   ```

5. When prompted, enter your server IP/domain and your PostgreSQL `DATABASE_URL`. The installer will automatically:
   - Configure NodeSource repository and install Node.js 20
   - Configure ZeroTier RPM repository and install `zerotier-one`
   - Test connectivity to your Cloud Database
   - Apply Prisma migrations and seed data
   - Build and deploy ZTnet to `/opt/ztnet`
   - Open ports in `firewalld` (`3000/tcp` for UI, `9993/udp` for ZeroTier)
   - Setup and start `ztnet.service`

### Running the Server (Development)

To run the server in development mode:

1. Install dependencies:
   ```bash
   npm install
   ```

2. Start development server:
   ```bash
   npm run start
   ```

3. Build production artifacts:
   ```bash
   npm run build
   ```
