#!/bin/bash
# Amazon Linux 2023: install LAMP (Apache + PHP) and WordPress on EC2.
# The database runs on a separate Amazon RDS MySQL instance.
set -e

sudo dnf update -y
sudo dnf install -y httpd php php-fpm php-mysqlnd mariadb105 wget

sudo systemctl enable --now httpd
sudo systemctl enable --now php-fpm

cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
sudo cp -r wordpress/* /var/www/html/

sudo chown -R apache:apache /var/www/html
sudo find /var/www/html -type d -exec chmod 755 {} \;
sudo find /var/www/html -type f -exec chmod 644 {} \;

echo "Done. Open http://<EC2-public-IP>/ and finish the WordPress setup wizard."
