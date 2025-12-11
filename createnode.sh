#!/bin/bash

# Minta input dari pengguna
echo "Masukkan nama lokasi: "
read location_name
echo "Masukkan deskripsi lokasi: "
read location_description
echo "Masukkan domain panel (contoh: panel.com): "
read domain
echo "Masukkan nama node: "
read node_name
echo "Masukkan RAM (dalam MB): "
read ram
echo "Masukkan disk space (dalam MB): "
read disk_space
echo "Masukkan LocID (ID lokasi): "
read locid
echo "Masukkan IP address untuk allocation: "
read ip_address
echo "Masukkan Port (contoh: 25565): "
read port
echo "Masukkan IP alias (boleh kosong): "
read ip_alias
echo "Masukan domain node (contoh: node.panel.com): "
read domain_node

# Ubah ke direktori pterodactyl
cd /var/www/pterodactyl || { echo "Direktori tidak ditemukan"; exit 1; }

echo "Membuat lokasi..."
php artisan p:location:make <<EOF
$location_name
$location_description
EOF

echo "Membuat node..."
php artisan p:node:make <<EOF
$node_name
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

echo "Membuat allocation..."
php artisan p:allocation:make <<EOF
$node_name
$ip_address
$port
$ip_alias
$domain_node
EOF

echo "Proses pembuatan node telah selesai."
exit 0
