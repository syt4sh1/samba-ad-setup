# NovaCode — Samba AD Setup Script

Automated setup script for a **Samba Active Directory** environment based on the fictional company **NovaCode** (M4 module — Sistemes Operatius en Xarxa).

Creates all Organizational Units, groups, users, shared directories and `smb.conf` resources in one shot. Assumes Samba AD is already installed and provisioned.

---

## Requirements

- Debian/Ubuntu server with **Samba AD already installed and provisioned**
- `winbind` and `nsswitch` integration enabled
- Root or `sudo` access
- Network connectivity (only needed to download the sample software file)

---

## What it does

| Part | Task |
|------|------|
| 1 | Creates **Organizational Units** (`Direccio`, `Oficines`, `Desenvolupament`, `Produccio`) |
| 2 | Creates **Groups** (`gDireccio`, `gOficines`, `gDesenvolupament`, `gProduccio`) |
| 3 | Creates **Users** (`uDirectora`, `uOficinista`, `uDesenvolupadora` + `*2` variants for access tests) |
| 4 | Adds each user to their corresponding group |
| 5 | Creates **shared directories** under `/var/NovaCode/` with correct Linux permissions |
| 6 | Writes the **`smb.conf`** shares (`software`, `produccio`, `comptabilitat`, `tresoreria`, `projectes`, `homes`) |
| 7 | Configures **`/etc/nsswitch.conf`** to include `winbind` |
| 8 | Restarts **Samba services** (`samba-ad-dc`, `smbd`, `winbind`) |

---

## Usage

```bash
# Clone or copy the script, then:
sudo bash setup_novacode_samba.sh
```

The script is **idempotent** — OUs, groups and users that already exist are skipped without error, so it is safe to re-run.

---

## Configuration

Edit the variables at the top of the script before running:

```bash
DOMAIN="novacode.local"       # FQDN of your domain
DC="DC=novacode,DC=local"     # Base DN
REALM="NOVACODE.LOCAL"        # Kerberos realm (uppercase)
PASSWORD="@ITB2025"           # Default password for all users
NOVACODE_DIR="/var/NovaCode"  # Root directory for company shares
SOFTWARE_DIR="/var/software"  # Path for the anonymous software share
SMB_CONF="/etc/samba/smb.conf"
```

---

## Domain Structure

```
novacode.local
├── OU=Direccio
│   ├── gDireccio
│   ├── uDirectora
│   └── uDirectora2
├── OU=Oficines
│   ├── gOficines
│   ├── uOficinista
│   └── uOficinista2
├── OU=Desenvolupament
│   ├── gDesenvolupament
│   ├── uDesenvolupadora
│   └── uDesenvolupadora2
└── OU=Produccio
    └── gProduccio
```

---

## Shared Resources

| Share | Path | Read | Write | Notes |
|-------|------|------|-------|-------|
| `software` | `/var/software` | Everyone (anonymous) | — | No auth required |
| `produccio` | `/var/NovaCode/cProduccio` | `gDireccio` | `gDesenvolupament` | |
| `comptabilitat` | `/var/NovaCode/cComptes` | `gDireccio`, `uDesenvolupadora` | `gOficines` | |
| `tresoreria` | `/var/NovaCode/cHisenda` | — | `gDireccio` | Exclusive to directors |
| `projectes` | `/var/NovaCode/cProjectes` | `gDireccio` | `gProduccio` | |
| `homes` | `/home/NovaCode/%S` | owner | owner | Per-user home directory |

---

## Testing (Exercici 4 — Comprovar els recursos)

### List visible shares from the server
```bash
smbclient -L localhost -U uDirectora%@ITB2025
```

### Write test — `uDirectora` → `tresoreria` (has write access)
```bash
smbclient //IP_SERVIDOR/tresoreria \
  -U "NOVACODE.LOCAL\uDirectora%@ITB2025" \
  -c "put /etc/hostname fitxer_prova.txt; ls"
```

### Read-only test — `uDesenvolupadora` → `comptabilitat` (read only)
```bash
smbclient //IP_SERVIDOR/comptabilitat \
  -U "NOVACODE.LOCAL\uDesenvolupadora%@ITB2025" \
  -c "ls; put /etc/hostname test.txt"
# ls → OK  |  put → NT_STATUS_ACCESS_DENIED
```

### Access denied test — `uOficinista` → `tresoreria` (no access)
```bash
smbclient //IP_SERVIDOR/tresoreria \
  -U "NOVACODE.LOCAL\uOficinista%@ITB2025" \
  -c "ls"
# → NT_STATUS_ACCESS_DENIED
```

### Permanent network drive on Windows 10

**Via GUI:** File Explorer → Right-click *This PC* → *Map network drive* → `\\IP_SERVIDOR\tresoreria` → tick *Reconnect at sign-in* → enter credentials `NOVACODE\uDirectora` / `@ITB2025`.

**Via `cmd.exe`:**
```cmd
net use Z: \\IP_SERVIDOR\tresoreria @ITB2025 /user:NOVACODE\uDirectora /persistent:yes
```

### Verify created files from the server
```bash
ls -la /var/NovaCode/cHisenda/
getfacl /var/NovaCode/cHisenda/
```

---

## Files

```
.
├── setup_novacode_samba.sh   # Main setup script
└── README.md                 # This file
```

---

## Notes

- A timestamped backup of the original `smb.conf` is created automatically before any changes are made.
- The `*2` user variants (`uDirectora2`, `uOficinista2`, `uDesenvolupadora2`) exist solely for the access-control exercises in P4.7.
- Directory permissions use the **setgid bit** (`2770`) so new files inherit the group owner automatically.
- If `winbind` is not yet running when the script executes, `chown` with domain user/group names will fall back to `root`. Re-run the script once `winbind` is active to fix ownership.
