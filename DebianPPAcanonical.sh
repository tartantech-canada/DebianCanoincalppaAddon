#!/bin/bash
set -e

# ==========================================
# CONFIGURATION & BRANCH SELECTION
# Default: "stable" (automatically targets current & future stable releases)
# Alternative options: "testing", "unstable"
# ==========================================
DEBIAN_RELEASE="${1:-stable}"
TARGET_DIR="/opt/custom-debian-os"
ARCH="amd64"
MIRROR="http://deb.debian.org/debian"

echo "[*] ========================================================"
echo "[*] Building Hybrid OS Base: Debian (${DEBIAN_RELEASE})"
echo "[*] Target Root Directory: ${TARGET_DIR}"
echo "[*] ========================================================"

# 1. Bootstrap Base System
echo "[*] Starting debootstrap..."
sudo debootstrap --arch=${ARCH} ${DEBIAN_RELEASE} ${TARGET_DIR} ${MIRROR}

# 2. Bind Virtual Filesystems
echo "[*] Mounting essential virtual filesystems..."
sudo mount --bind /dev ${TARGET_DIR}/dev
sudo mount --bind /dev/pts ${TARGET_DIR}/dev/pts
sudo mount --bind /proc ${TARGET_DIR}/proc
sudo mount --bind /sys ${TARGET_DIR}/sys

# 3. Resolve Initial Ubuntu Channel Dynamically
if [ -f /etc/os-release ]; then
    . /etc/os-release
    UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"
else
    UBUNTU_CODENAME="noble"
fi
echo "[*] Initial Ubuntu component codename resolved as: ${UBUNTU_CODENAME}"

# 4. Chroot Configuration and Package Provisioning
echo "[*] Entering chroot environment for system configuration..."
sudo chroot ${TARGET_DIR} /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive

# Configure Official Debian Sources
cat <<EOT > /etc/apt/sources.list
deb ${MIRROR} ${DEBIAN_RELEASE} main contrib non-free non-free-firmware
deb-src ${MIRROR} ${DEBIAN_RELEASE} main contrib non-free non-free-firmware
EOT

# Add security updates repository automatically if targeting the stable branch
if [ "${DEBIAN_RELEASE}" = "stable" ]; then
    echo "deb http://security.debian.org/debian-security stable-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list
fi

# Setup Advanced APT Pinning to protect core libraries during branch upgrades
cat <<EOT > /etc/apt/preferences.d/hybrid-pinning
Package: *
Pin: release o=Debian
Pin-Priority: 900

Package: *
Pin: release a=testing
Pin-Priority: 800

Package: *
Pin: release a=unstable
Pin-Priority: 700

Package: *
Pin: release o=Ubuntu
Pin-Priority: 100
EOT

# Update package lists and install core framework dependencies
apt-get update
apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    gnupg \
    dirmngr \
    software-properties-common \
    pciutils \
    usbutils \
    hwdata \
    systemd-sysv \
    network-manager \
    curl

# Add Canonical Archive GPG Keys & Universe Repository for drivers/firmware
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 871920D1991BC93C

echo "deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME} main restricted universe multiverse" > /etc/apt/sources.list.d/ubuntu-universe.list
apt-get update

# Install Strict Core GNOME Desktop Environment
apt-get install -y --no-install-recommends \
    gdm3 \
    gnome-shell \
    gnome-session \
    gnome-terminal \
    nautilus \
    xdg-user-dirs-gtk

# Install Essential GNOME Productivity Apps & GNOME Software Store
apt-get install -y --no-install-recommends \
    gnome-text-editor \
    gnome-calculator \
    gnome-system-monitor \
    eog \
    file-roller \
    gnome-software \
    gnome-software-plugin-deb \
    packagekit

# Install Canonical Hardware Drivers & Firmware Management Stack
apt-get install -y \
    fwupd \
    fwupd-signed \
    firmware-updater \
    ubuntu-drivers-common \
    software-properties-gtk

# 5. Inject Automated Canonical Layer Upgrade Utility
cat << 'EOT' > /usr/local/bin/upgrade-ubuntu-layer
#!/bin/bash
if [ "\$EUID" -ne 0 ]; then
  echo "[-] Please run as root (sudo upgrade-ubuntu-layer)."
  exit 1
fi

echo "[*] Querying Canonical meta-release stream for the newest release..."
LATEST_CODENAME=\$(curl -s https://changelogs.ubuntu.com/meta-release | grep -m 1 "Codename: " | awk '{print \$2}')

if [ -z "\$LATEST_CODENAME" ]; then
    echo "[-] Error: Could not fetch the latest Ubuntu release codename. Check internet connectivity."
    exit 1
fi

echo "[+] Latest detected Ubuntu release codename: \${LATEST_CODENAME}"
echo "[*] Updating repository source configuration..."

echo "deb http://archive.ubuntu.com/ubuntu/ \${LATEST_CODENAME} main restricted universe multiverse" > /etc/apt/sources.list.d/ubuntu-universe.list

apt-get update
echo "[+] Canonical repository layer successfully upgraded to \${LATEST_CODENAME}!"
EOT

chmod +x /usr/local/bin/upgrade-ubuntu-layer

# Enable System Services
systemctl enable gdm3
systemctl enable fwupd.service
systemctl enable NetworkManager

echo "[*] Custom OS configuration inside chroot complete."
EOF

# 6. Cleanup Mounts Safely
echo "[*] Cleaning up virtual filesystem mounts..."
sudo umount ${TARGET_DIR}/dev/pts
sudo umount ${TARGET_DIR}/dev
sudo umount ${TARGET_DIR}/proc
sudo umount ${TARGET_DIR}/sys

echo "[*] ========================================================"
echo "[*] Build Successful!"
echo "[*] Ready root filesystem located at: ${TARGET_DIR}"
echo "[*] ========================================================"
