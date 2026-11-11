#!/bin/bash
# Make WordPress use whatever host name it is accessed with (EC2 IP or Load Balancer DNS).
# Run this BEFORE creating the AMI, otherwise WordPress redirects to the original EC2 IP.
sudo sed -i "/^<?php/a define('WP_SITEURL', 'http://' . \$_SERVER['HTTP_HOST']);" /var/www/html/wp-config.php
sudo sed -i "/^<?php/a define('WP_HOME', 'http://' . \$_SERVER['HTTP_HOST']);" /var/www/html/wp-config.php
head -5 /var/www/html/wp-config.php
