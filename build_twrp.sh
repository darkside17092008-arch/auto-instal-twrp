Siap. Karena kamu build via Cirrus (Docker) dan nggak bisa nambah file manual, aku bikin solusi yang full-otomatis: semua perbaikan device tree (rename file yang salah, injeksi flags OrangeFox, enable key navigation, coba load modul touchscreen dari vendor_boot) dilakukan langsung oleh script build_twrp.sh saat runtime.

Di bawah ini 2 hal yang bisa langsung kamu copy-paste:
- .cirrus.yaml (tetap Ubuntu 18.04 seperti punyamu)
- build_twrp.sh (versi baru yang auto-patch device tree dan support non-touch + coba perbaiki touch Omnivision TCM SPI)

Catatan penting:
- Target Android 11: MANIFEST_BRANCH fox_11.0
- Target output: boot.img (karena BOARD_USES_RECOVERY_AS_BOOT := true)
- Chip: MediaTek MT6761
- Non-touch navigation: aktif via recovery.keys + OF_USE_KEY_HANDLER
- Touchscreen fix: TW_LOAD_VENDOR_BOOT_MODULES := true (biar recovery coba load semua modul di vendor_boot). Jika nama modul tepat, bisa juga dimuat via TW_LOAD_VENDOR_MODULES (aku kasih fallback injeksi percobaan).

1) .cirrus.yaml
Ganti file kamu dengan ini (sama basisnya, cuma lebih rapih dan tetap di 18.04):

```yaml
task:
  name: Build OrangeFox X6512 (boot.img)
  container:
    image: ubuntu:18.04
    cpu: 8
    memory: 32G
  environment:
    MANIFEST_BRANCH: fox_11.0
    DEVICE_TREE: https://github.com/manusia251/twrp-test.git
    DEVICE_BRANCH: main
    DEVICE_CODENAME: X6512
    TARGET_RECOVERY_IMAGE: boot
    DEBIAN_FRONTEND: noninteractive
  install_script:
    # Fix sources.list for Docker minimal image
    - echo "deb http://archive.ubuntu.com/ubuntu bionic main restricted" > /etc/apt/sources.list
    - echo "deb http://archive.ubuntu.com/ubuntu bionic-updates main restricted" >> /etc/apt/sources.list
    - echo "deb http://archive.ubuntu.com/ubuntu bionic universe" >> /etc/apt/sources.list
    - echo "deb http://archive.ubuntu.com/ubuntu bionic-updates universe" >> /etc/apt/sources.list
    - echo "deb http://archive.ubuntu.com/ubuntu bionic multiverse" >> /etc/apt/sources.list
    - echo "deb http://archive.ubuntu.com/ubuntu bionic-updates multiverse" >> /etc/apt/sources.list
    - echo "deb http://security.ubuntu.com/ubuntu bionic-security main restricted" >> /etc/apt/sources.list
    - echo "deb http://security.ubuntu.com/ubuntu bionic-security universe" >> /etc/apt/sources.list
    - echo "deb http://security.ubuntu.com/ubuntu bionic-security multiverse" >> /etc/apt/sources.list

    # Update package lists
    - apt-get update

    # Base tools
    - apt-get install -y software-properties-common apt-utils wget ca-certificates curl

    # Enable i386 arch (beberapa dep 32-bit)
    - dpkg --add-architecture i386
    - apt-get update

    # AOSP deps
    - apt-get install -y git gnupg flex bison gperf build-essential zip zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig

    # Additional tools
    - apt-get install -y libssl-dev bc python python3 rsync ccache lzop pngcrush schedtool libncurses5-dev nano vim

    # Java 8 (OrangeFox R11/Android 11 nyaman pakai ini)
    - apt-get install -y openjdk-8-jdk

    # repo tool
    - curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo
    - chmod +x /usr/local/bin/repo

  script:
    # Java 8 env
    - export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
    - export PATH=$JAVA_HOME/bin:$PATH

    # Git identity
    - git config --global user.name "manusia251"
    - git config --global user.email "darkside@gmail.com"

    # Ccache
    - export USE_CCACHE=1
    - export CCACHE_COMPRESS=1
    - export CCACHE_DIR="/tmp/ccache"
    - export CCACHE_MAX_SIZE=50G

    # Debug info
    - echo "Current directory files:" && ls -la

    # Pastikan script ada
    - if [ -f build_twrp.sh ]; then chmod +x build_twrp.sh; else echo "build_twrp.sh not found!"; ls -la; exit 1; fi

    # Show env
    - echo "Env: DEVICE_TREE=$DEVICE_TREE DEVICE_BRANCH=$DEVICE_BRANCH DEVICE_CODENAME=$DEVICE_CODENAME MANIFEST_BRANCH=$MANIFEST_BRANCH TARGET_RECOVERY_IMAGE=$TARGET_RECOVERY_IMAGE"

    # Build OFOX (boot.img)
    - bash build_twrp.sh "$DEVICE_TREE" "$DEVICE_BRANCH" "$DEVICE_CODENAME" "$MANIFEST_BRANCH" "$TARGET_RECOVERY_IMAGE"

  artifacts:
    path: output/**/*
  timeout_in: 120m
```

2) build_twrp.sh
Ganti isi script kamu dengan ini. Script ini:
- Sync source OrangeFox R11 (fox_11.0)
- Clone device tree kamu
- Auto-fix nama file (AndroidProducts.mk, Android.mk, BoardConfig.mk) kalau salah
- Inject flags OrangeFox + MTK + AB + non-touch navigation + percobaan load modul touchscreen dari vendor_boot
- Buat recovery.keys untuk navigasi tombol
- Build bootimage dan salin hasil ke ./output

```bash
#!/usr/bin/env bash
set -euo pipefail

# Args
DEVICE_TREE_URL="${1:-https://github.com/manusia251/twrp-test.git}"
DEVICE_TREE_BRANCH="${2:-main}"
DEVICE_CODENAME="${3:-X6512}"
MANIFEST_BRANCH="${4:-fox_11.0}"
BUILD_TARGET="${5:-boot}"
VENDOR_NAME="infinix"

# OFOX meta
export FOX_VERSION="R11.1_1"
export FOX_BUILD_TYPE="Stable"
export OF_MAINTAINER="manusia251"

echo "========================================"
echo "Build OrangeFox"
echo "----------------------------------------"
echo "Manifest Branch  : ${MANIFEST_BRANCH}"
echo "Device Tree URL  : ${DEVICE_TREE_URL}"
echo "Device Branch    : ${DEVICE_TREE_BRANCH}"
echo "Device Codename  : ${DEVICE_CODENAME}"
echo "Build Target     : ${BUILD_TARGET}image"
echo "========================================"

WORKDIR="$(pwd)"
BUILD_TOP="${WORKDIR}/orangefox"

mkdir -p "${BUILD_TOP}"
cd "${BUILD_TOP}"

# Git identity
git config --global user.name "manusia251"
git config --global user.email "darkside@gmail.com"

# 1) Sync source OrangeFox
echo "--- Clone OrangeFox sync repo ---"
if [ ! -d sync_repo ]; then
  git clone https://gitlab.com/OrangeFox/sync.git -b "${MANIFEST_BRANCH}" sync_repo
fi
cd sync_repo
echo "--- Start syncing ---"
if [ -f "./orangefox_sync.sh" ]; then
  bash ./orangefox_sync.sh --branch "${MANIFEST_BRANCH}" --path .. --no-repo-check
elif [ -f "./sync.sh" ]; then
  bash ./sync.sh --branch "${MANIFEST_BRANCH}" --path ..
else
  echo "ERROR: sync script not found in OrangeFox/sync"
  exit 1
fi
cd ..

# 2) Clone device tree
D_PATH="device/${VENDOR_NAME}/${DEVICE_CODENAME}"
mkdir -p device/${VENDOR_NAME}
if [ -d "${D_PATH}/.git" ]; then
  echo "--- Device tree already exists, pulling latest ---"
  (cd "${D_PATH}" && git fetch origin "${DEVICE_TREE_BRANCH}" && git checkout "${DEVICE_TREE_BRANCH}" && git pull)
else
  echo "--- Cloning device tree: ${DEVICE_TREE_URL} (${DEVICE_TREE_BRANCH}) ---"
  git clone --depth=1 -b "${DEVICE_TREE_BRANCH}" "${DEVICE_TREE_URL}" "${D_PATH}"
fi

# 3) Auto-fix file names & inject configs
echo "--- Auto-fix device tree structure & configs ---"

# Fix common wrong filenames (case-sensitive)
[ -f "${D_PATH}/androidproduct.mk" ] && [ ! -f "${D_PATH}/AndroidProducts.mk" ] && mv "${D_PATH}/androidproduct.mk" "${D_PATH}/AndroidProducts.mk" || true
[ -f "${D_PATH}/android.mk" ] && [ ! -f "${D_PATH}/Android.mk" ] && mv "${D_PATH}/android.mk" "${D_PATH}/Android.mk" || true
[ -f "${D_PATH}/boardconfgi.mk" ] && [ ! -f "${D_PATH}/BoardConfig.mk" ] && mv "${D_PATH}/boardconfgi.mk" "${D_PATH}/BoardConfig.mk" || true

# Ensure AndroidProducts.mk exists with combos
if [ ! -f "${D_PATH}/AndroidProducts.mk" ]; then
  cat > "${D_PATH}/AndroidProducts.mk" <<EOF
LOCAL_PATH := \$(call my-dir)
PRODUCT_MAKEFILES := \\
    \$(LOCAL_DIR)/omni_${DEVICE_CODENAME}.mk
COMMON_LUNCH_CHOICES := \\
    omni_${DEVICE_CODENAME}-user \\
    omni_${DEVICE_CODENAME}-userdebug \\
    omni_${DEVICE_CODENAME}-eng
EOF
fi

# Ensure Android.mk exists
if [ ! -f "${D_PATH}/Android.mk" ]; then
  cat > "${D_PATH}/Android.mk" <<EOF
LOCAL_PATH := \$(call my-dir)
ifeq (\$(TARGET_DEVICE),${DEVICE_CODENAME})
include \$(call all-subdir-makefiles,\$(LOCAL_PATH))
endif
EOF
fi

# Ensure omni_<codename>.mk exists minimal (kalau belum ada)
if [ ! -f "${D_PATH}/omni_${DEVICE_CODENAME}.mk" ]; then
  cat > "${D_PATH}/omni_${DEVICE_CODENAME}.mk" <<EOF
\$(call inherit-product, \$(SRC_TARGET_DIR)/product/full_base_telephony.mk)
\$(call inherit-product, \$(SRC_TARGET_DIR)/product/aosp_base.mk)
\$(call inherit-product, \$(SRC_TARGET_DIR)/product/full_base.mk)
\$(call inherit-product, ${D_PATH}/device.mk)

PRODUCT_DEVICE := ${DEVICE_CODENAME}
PRODUCT_NAME := omni_${DEVICE_CODENAME}
PRODUCT_BRAND := Infinix
PRODUCT_MODEL := Infinix ${DEVICE_CODENAME}
PRODUCT_MANUFACTURER := Infinix
EOF
fi

# Ensure BoardConfig.mk exists
if [ ! -f "${D_PATH}/BoardConfig.mk" ]; then
  touch "${D_PATH}/BoardConfig.mk"
fi

# Append OrangeFox + MTK + AB + input flags (biarkan override nilai sebelumnya)
cat >> "${D_PATH}/BoardConfig.mk" <<'EOF'

# ==== [AUTO PATCH BY CI - ORANGEFOX] ====
ALLOW_MISSING_DEPENDENCIES := true

# Platform
TARGET_BOARD_PLATFORM := mt6761

# A/B dan recovery-as-boot
AB_OTA_UPDATER := true
BOARD_USES_RECOVERY_AS_BOOT := true

# Boot image header v2
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)

# OrangeFox build
FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER := 1
OF_PATCH_AVB20 := 1

# Navigasi tanpa touchscreen
OF_USE_KEY_HANDLER := 1
# Jangan matiin layar
TW_NO_SCREEN_TIMEOUT := true
TW_NO_SCREEN_BLANK := true

# Coba auto-load modules dari vendor_boot (Android 11)
TW_LOAD_VENDOR_BOOT_MODULES := true
# Jika butuh spesifik modul, uncomment dan sesuaikan salah satu di bawah sesuai nama modul di /vendor/lib/modules atau vendor_boot:
# TW_LOAD_VENDOR_MODULES := "omnivision_tcm.ko"
# TW_LOAD_VENDOR_MODULES := "omnivision_tcm_spi.ko"
# TW_LOAD_VENDOR_MODULES := "ovt_tcm.ko"

# Layar & backlight
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_MAX_BRIGHTNESS := 255
TW_DEFAULT_BRIGHTNESS := 120

# Resolusi (720x1600 kira-kira)
OF_SCREEN_W := 720
OF_SCREEN_H := 1600
OF_STATUS_H := 80
OF_STATUS_INDENT_LEFT := 48
OF_STATUS_INDENT_RIGHT := 48

# Meta OFOX
OF_MAINTAINER := "manusia251"
FOX_VERSION := "R11.1_1"
FOX_BUILD_TYPE := "Stable"
# ==== [END AUTO PATCH] ====
EOF

# recovery.keys untuk volume/power nav
mkdir -p "${D_PATH}/recovery/root/etc"
cat > "${D_PATH}/recovery/root/etc/recovery.keys" <<'EOF'
114
115
116
158
102
EOF
# 114=Vol Down, 115=Vol Up, 116=Power, 158=Back, 102=Home (fallback)

# Optional: proper fstab path check (biarkan jika sudah ada)
if [ -f "${D_PATH}/recovery/root/system/etc/recovery.fstab" ]; then
  if ! grep -q "TARGET_RECOVERY_FSTAB" "${D_PATH}/BoardConfig.mk"; then
    echo 'TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab' >> "${D_PATH}/BoardConfig.mk"
  fi
elif [ -f "${D_PATH}/recovery/root/etc/recovery.fstab" ]; then
  if ! grep -q "TARGET_RECOVERY_FSTAB" "${D_PATH}/BoardConfig.mk"; then
    echo 'TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/etc/recovery.fstab' >> "${D_PATH}/BoardConfig.mk"
  fi
fi

# 4) Build
echo "--- Source build env ---"
source build/envsetup.sh
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C

echo "--- lunch omni_${DEVICE_CODENAME}-eng ---"
lunch omni_${DEVICE_CODENAME}-eng

echo "--- make ${BUILD_TARGET}image ---"
mka ${BUILD_TARGET}image

# 5) Copy output
RESULT_DIR="${BUILD_TOP}/out/target/product/${DEVICE_CODENAME}"
OUTPUT_DIR="${WORKDIR}/output"
mkdir -p "${OUTPUT_DIR}"

echo "--- Collecting artifacts ---"
# Prioritas boot.img (karena recovery-as-boot), juga zip/img lain kalau ada
for f in boot.img recovery.img *.zip OrangeFox-*.zip OrangeFox-*.img; do
  if [ -f "${RESULT_DIR}/$f" ]; then
    cp -fv "${RESULT_DIR}/$f" "${OUTPUT_DIR}/" || true
  fi
done

echo "--- Artifacts in output/ ---"
ls -lh "${OUTPUT_DIR}"
echo "DONE."
```

Penjelasan singkat kenapa ini efektif:
- Sinkronisasi source OrangeFox R11 via repo resmi (fox_11.0) cocok untuk Android 11.
- Karena kamu target boot.img (recovery-as-boot), script otomatis build mka bootimage.
- Non-touch navigation diaktifkan via:
  - OF_USE_KEY_HANDLER := 1
  - File recovery/root/etc/recovery.keys (VolUp/VolDown/Power/Back/Home)
  - Disable screen timeout/blank di recovery
- Fix touchscreen Omnivision TCM SPI:
  - TW_LOAD_VENDOR_BOOT_MODULES := true agar recovery mencoba load modul dari vendor_boot (umum untuk Android 11 ke atas).
  - Disiapkan fallback TW_LOAD_VENDOR_MODULES yang bisa kamu uncomment + ganti nama modul kalau kamu tahu persis .ko di vendor.
- Auto-fix nama file di device tree kalau salah penamaan (AndroidProducts.mk, Android.mk, BoardConfig.mk) supaya lunch omni_X6512-eng pasti terdaftar.

Kalau touch masih mati:
- Buka output boot.img di ponsel, lalu logcat dmesg dari recovery: cari "tcm" atau "omnivision". Cek modul mana yang ada di /vendor/lib/modules atau vendor_boot.ko list. Lalu di BoardConfig.mk (yang di-patch otomatis), uncomment dan ganti TW_LOAD_VENDOR_MODULES dengan nama tepat, misal:
  - TW_LOAD_VENDOR_MODULES := "omnivision_tcm.ko"
  - atau "omnivision_tcm_spi.ko" atau "ovt_tcm.ko" (tergantung ROM kamu)
- Jika device tree punya path brightness berbeda, ganti TW_BRIGHTNESS_PATH sesuai sysfs yang benar.

Kalau butuh, aku bisa bantu mapping modul pas kamu upload dmesg dari recovery.
