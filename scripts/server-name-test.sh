#!/bin/bash
# Run on each web server to create a test page that shows which server answered.
# Use a different name on every server (Web Server 1, Web Server 2, ...).
NAME="${1:-Web Server 1}"
echo "<?php echo \"Served by: ${NAME}\"; ?>" | sudo tee /var/www/html/server.php

# Then, from any machine, call the Load Balancer several times:
#   for i in {1..10}; do curl -s http://<ALB-DNS-name>/server.php; echo; done
