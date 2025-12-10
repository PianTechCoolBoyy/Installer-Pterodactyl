#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

validate_input() {
    if [[ -z "$1" ]]; then
        log_error "Input tidak boleh kosong!"
        exit 1
    fi
}

validate_number() {
    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        log_error "Input harus berupa angka!"
        exit 1
    fi
}

validate_domain() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Format domain tidak valid!"
        exit 1
    fi
}

check_pterodactyl() {
    if [[ ! -d "/var/www/pterodactyl" ]]; then
        log_error "Pterodactyl tidak ditemukan di /var/www/pterodactyl"
        log_info "Pastikan Anda sudah menginstal panel Pterodactyl terlebih dahulu"
        exit 1
    fi
}

check_dependencies() {
    if ! command -v php &> /dev/null; then
        log_error "PHP tidak ditemukan!"
        exit 1
    fi
    
    if ! command -v mysql &> /dev/null; then
        log_error "MySQL tidak ditemukan!"
        exit 1
    fi
}

clear
log_info "=== Script Pembuatan Node Pterodactyl ==="
echo ""

check_dependencies
check_pterodactyl

log_info "Masukkan informasi lokasi dan node:"
echo ""

echo "Masukkan nama lokasi:"
read location_name
validate_input "$location_name"

echo "Masukkan deskripsi lokasi:"
read location_description
validate_input "$location_description"

echo "Masukkan domain (contoh: node.domain.com):"
read domain
validate_input "$domain"
validate_domain "$domain"

echo "Masukkan nama node:"
read node_name
validate_input "$node_name"

echo "Masukkan RAM (dalam MB, contoh: 2048 untuk 2GB):"
read ram
validate_input "$ram"
validate_number "$ram"

echo "Masukkan jumlah maksimum disk space (dalam MB):"
read disk_space
validate_input "$disk_space"
validate_number "$disk_space"

echo "Masukkan Locid (ID lokasi, biasanya 1):"
read locid
validate_input "$locid"
validate_number "$locid"

echo ""
log_warning "Konfirmasi pengaturan:"
echo "────────────────────────────"
echo "Nama Lokasi     : $location_name"
echo "Deskripsi       : $location_description"
echo "Domain          : $domain"
echo "Nama Node       : $node_name"
echo "RAM             : $ram MB"
echo "Disk Space      : $disk_space MB"
echo "Locid           : $locid"
echo "────────────────────────────"
echo ""

read -p "Apakah data di atas sudah benar? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log_info "Proses dibatalkan"
    exit 0
fi

cd /var/www/pterodactyl || {
    log_error "Gagal masuk ke direktori /var/www/pterodactyl"
    exit 1
}

log_info "Membuat lokasi baru..."
if ! php artisan p:location:make <<EOF > /tmp/ptero_location.log 2>&1
$location_name
$location_description
EOF
then
    log_error "Gagal membuat lokasi"
    cat /tmp/ptero_location.log
    exit 1
fi
log_success "Lokasi berhasil dibuat"

LOCATION_ID=$(php artisan p:location:list --format=json | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
if [[ -n "$LOCATION_ID" ]]; then
    log_info "Location ID: $LOCATION_ID"
else
    log_warning "Tidak dapat mendapatkan Location ID"
fi

log_info "Membuat node baru..."
if ! php artisan p:node:make <<EOF > /tmp/ptero_node.log 2>&1
$node_name
$location_description
$locid
https
$domain
yes
no
no
$ram
$ram
$disk_space
$disk_space
100
8080
2022
/var/lib/pterodactyl/volumes
EOF
then
    log_error "Gagal membuat node"
    cat /tmp/ptero_node.log
    exit 1
fi
log_success "Node berhasil dibuat"

log_info "Mengambil informasi node..."
NODE_INFO=$(php artisan p:node:list --format=json 2>/dev/null | grep -A5 "$node_name" || true)
if [[ -n "$NODE_INFO" ]]; then
    log_info "Informasi Node:"
    echo "$NODE_INFO" | head -10
fi

log_info "Mengambil token node..."
TOKEN=$(php artisan p:node:configuration $node_name 2>/dev/null | grep -o "token: .*" | cut -d' ' -f2 || true)
if [[ -n "$TOKEN" ]]; then
    log_success "Token Node: $TOKEN"
    echo "Token Node: $TOKEN" > /tmp/ptero_node_token.txt
    log_info "Token disimpan di /tmp/ptero_node_token.txt"
else
    log_warning "Tidak dapat mengambil token node secara otomatis"
    log_info "Gunakan perintah: php artisan p:node:configuration $node_name"
fi

log_info "Membuat allocation untuk node..."
ALLOCATION_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
if [[ -n "$ALLOCATION_IP" ]]; then
    if php artisan p:allocation:make --node="$node_name" --ip="$ALLOCATION_IP" --port=25565-25570 --alias="Minecraft" > /tmp/ptero_allocation.log 2>&1; then
        log_success "Allocation berhasil dibuat untuk IP: $ALLOCATION_IP"
    else
        log_warning "Gagal membuat allocation otomatis"
        log_info "Buat allocation manual dengan: php artisan p:allocation:make --node=$node_name"
    fi
fi

log_info "Mengupdate environment..."
if [[ -f ".env" ]]; then
    if grep -q "APP_URL" .env; then
        sed -i "s|APP_URL=.*|APP_URL=https://$domain|" .env
        log_success "APP_URL diupdate ke https://$domain"
    fi
fi

log_info "Mengoptimasi aplikasi..."
php artisan config:cache > /dev/null 2>&1
php artisan view:cache > /dev/null 2>&1
log_success "Cache dioptimasi"

echo ""
log_success "=== PROSES SELESAI ==="
echo ""
log_info "Detail Node yang dibuat:"
echo "────────────────────────────"
echo "Nama Lokasi     : $location_name"
echo "Nama Node       : $node_name"
echo "Domain          : $domain"
echo "RAM             : $ram MB"
echo "Disk Space      : $disk_space MB"
echo "Port Wings      : 8080"
echo "Port SFTP       : 2022"
echo "Volume Path     : /var/lib/pterodactyl/volumes"
echo "────────────────────────────"
echo ""
if [[ -n "$TOKEN" ]]; then
    log_info "Token Node: $TOKEN"
    echo "Salin token untuk konfigurasi Wings"
fi
echo ""
log_info "Langkah selanjutnya:"
echo "1. Install Wings di server node dengan token di atas"
echo "2. Konfigurasi firewall untuk port 8080, 2022, dan 25565-25570"
echo "3. Tambahkan lebih banyak allocation jika diperlukan"
echo ""

read -p "Tampilkan log lengkap? (y/n): " show_log
if [[ "$show_log" == "y" || "$show_log" == "Y" ]]; then
    echo ""
    log_info "Log Pembuatan Lokasi:"
    cat /tmp/ptero_location.log
    echo ""
    log_info "Log Pembuatan Node:"
    cat /tmp/ptero_node.log
    echo ""
    if [[ -f "/tmp/ptero_allocation.log" ]]; then
        log_info "Log Pembuatan Allocation:"
        cat /tmp/ptero_allocation.log
    fi
fi

rm -f /tmp/ptero_location.log /tmp/ptero_node.log /tmp/ptero_allocation.log 2>/dev/null

log_success "Script selesai dijalankan!"