#!/bin/bash

# Install Jenkins
wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key |sudo gpg --dearmor -o /usr/share/keyrings/jenkins.gpg
sudo sh -c 'echo deb [signed-by=/usr/share/keyrings/jenkins.gpg] http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update
sudo apt-get install openjdk-17-jdk -y
sudo apt-get install jenkins -y
sudo apt-get install apache2 -y
sudo apt-get install apache2-utils -y
sudo apt-get install apache2-ssl-dev -y
sudo apt install fd-find -y
sudo snap install aws-cli --classic
sudo ln -s /usr/bin/fdfind /usr/bin/fd

# Setup SSH
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFbHJZgIfhUqSoupCKISRV9skyud0gvTOtg0I+f/u36" >> ~/.ssh/authorized_keys


# Configure Apache
sudo a2enmod proxy proxy_http rewrite ssl headers
export JENK=$(ec2metadata --public-hostname)

cat <<'EOF' > /etc/apache2/sites-available/jenkins.conf
<VirtualHost *:80>
    ServerName ${JENK}
    DocumentRoot /var/www/html

    # Enable proxy module
    ProxyPreserveHost On
    ProxyRequests Off

    # Proxy configuration for Jenkins
    ProxyPass / http://localhost:8080/
    ProxyPassReverse / http://localhost:8080/

    # Additional headers for proper Jenkins functionality
    ProxyPassReverse / http://${JENK}/

    # Set headers for WebSocket support (required for Jenkins UI)
    RewriteEngine On
    RewriteCond %{HTTP:Connection} Upgrade [NC]
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteRule /(.*) ws://localhost:8080/$1 [P,L]

    # Optional: Enable compression
    SetEnv proxy-nokeepalive 1
    SetEnv proxy-initial-not-pooled 1

    # Logging
    ErrorLog ${APACHE_LOG_DIR}/jenkins_error.log
    CustomLog ${APACHE_LOG_DIR}/jenkins_access.log combined

    # Security headers (optional but recommended)
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"
</VirtualHost>

# Optional HTTPS configuration (recommended for production)
<VirtualHost *:443>
    ServerName ${JENK}
    DocumentRoot /var/www/html

    # SSL Configuration
    SSLEngine on
    SSLCertificateFile /path/to/your/certificate.crt
    SSLCertificateKeyFile /path/to/your/private.key
    # SSLCertificateChainFile /path/to/your/chain.crt  # If using a certificate chain

    # Enable proxy module
    ProxyPreserveHost On
    ProxyRequests Off

    # Proxy configuration for Jenkins
    ProxyPass / http://localhost:8080/
    ProxyPassReverse / http://localhost:8080/
    ProxyPassReverse / https://${JENK}/

    # Set headers for WebSocket support
    RewriteEngine On
    RewriteCond %{HTTP:Connection} Upgrade [NC]
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteRule /(.*) ws://localhost:8080/$1 [P,L]

    # Security and performance settings
    SetEnv proxy-nokeepalive 1
    SetEnv proxy-initial-not-pooled 1

    # Logging
    ErrorLog ${APACHE_LOG_DIR}/jenkins_ssl_error.log
    CustomLog ${APACHE_LOG_DIR}/jenkins_ssl_access.log combined

    # Security headers
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
</VirtualHost>

EOF

sudo a2dissite 000-default
sudo a2ensite jenkins
sudo systemctl restart apache2

# Install Docker

sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu noble stable" -y
apt-cache policy docker-ce
sudo apt-get install docker-ce -y
sudo usermod -aG docker jenkins

# Install Trivy
sudo apt-get install wget apt-transport-https gnupg lsb-release -y
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy -y

# Install SonarQube
docker run -d  --name sonar -p 9000:9000 sonarqube:lts-community