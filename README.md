# ⚡ DOMjudge Local Orchestrator & Multi-Node Cluster

Production-grade, resilient local DOMjudge environment tailored for competitive programming contests. Includes multi-machine judging over LAN and 1-click disaster recovery standby server.

---

## 🚀 Quick Start (Main Server - PC 1)

1. **Configure Environment:**
   ```bash
   cp .env.example .env
   ```
2. **Start Contest:**
   ```bash
   ./start-contest.sh
   # Or for specific network: ./start-contest-wifi.sh | ./start-contest-ethernet.sh
   ```
3. **Access DOMjudge:**
   - Public / Teams: `http://<YOUR_IP>:8080`
   - Jury / Admin: `http://<YOUR_IP>:8080/jury` (User: `admin` / Password in `.env`)

---

## 🖥️ Using a 2nd PC as Extra Judges & Hot Standby Backup

You can connect a friend's PC on the same Wi-Fi / Ethernet LAN to:
1. **Parallelize Submissions:** Add 4+ judgehosts running on PC 2 directly connected to Main DOMserver.
2. **Disaster Recovery:** If PC 1 goes down, PC 2 can restore the latest snapshot and become the main server in ~20 seconds.

👉 **A complete plain-text guide is available in [PC2_SETUP_GUIDE.txt](file:///home/tbk/Projects/domjudge-local/PC2_SETUP_GUIDE.txt).**

### Quick Steps for PC 2:

```bash
# 1. Clone repository on PC 2
git clone https://github.com/MrTBK/<repo-name>.git
cd <repo-name>

# 2. Build multi-compiler judgehost image
docker build -t domjudge/judgehost:9.0.1-custom -f Dockerfile.judgehost .

# 3. Configure connection to PC 1
cd pc2-standby-and-judges
cp .env.example .env
# Set MAIN_SERVER_IP=<PC1_IP> and check passwords
```

#### To run PC 2 as Extra Judges:
```bash
./start-remote-judges.sh
```

#### In case PC 1 goes down (Emergency Failover):
```bash
./takeover-and-become-main-server.sh
```

---

## 🛡️ Backup & High Availability

- **Automated Hot Backup Daemon:**
  ```bash
  ./auto-backup.sh &
  ```
  Produces non-blocking transactional SQL dumps every 5 minutes in `backups/`.

- **Continuous Remote Backup Sync to PC 2:**
  ```bash
  ./sync-backup-to-remote.sh <user>@<PC2_IP>:~/path/to/pc2-standby-and-judges/backups/ &
  ```
