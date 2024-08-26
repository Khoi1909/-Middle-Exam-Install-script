#!/bin/bash
#!/bin/zsh
# Kiểm tra hệ điều hành
check_os() {
    if [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/arch-release ]; then
        OS="arch"
    elif [ -f /etc/redhat-release ]; then
        if grep -q "CentOS" /etc/redhat-release; then
            echo "CentOS không được hỗ trợ."
            exit 1
        else
            OS="redhat"
        fi
    else
        echo "Hệ điều hành không được hỗ trợ."
        exit 1
    fi
}

# Cài đặt Apache
install_apache() {
    echo "=========================="
    echo "Cài đặt Apache..."
    if [ "$OS" == "debian" ]; then
        sudo apt update
        sudo apt install -y apache2
        sudo systemctl start apache2
        sudo systemctl enable apache2
    elif [ "$OS" == "arch" ]; then
        sudo pacman -Syu --noconfirm apache
        sudo systemctl start httpd
        sudo systemctl enable httpd
    elif [ "$OS" == "redhat" ]; then
        sudo yum install -y httpd
        sudo systemctl start httpd
        sudo systemctl enable httpd
    fi
}

# Cài đặt PHP
install_php() {
    echo "=========================="
    echo "Cài đặt PHP..."
    if [ "$OS" == "debian" ]; then
        sudo apt install -y php libapache2-mod-php php-mysql
        sudo systemctl restart apache2
    elif [ "$OS" == "arch" ]; then
        sudo pacman -S --noconfirm php php-apache
        sudo sed -i 's/#LoadModule mpm_prefork_module/LoadModule mpm_prefork_module/' /etc/httpd/conf/httpd.conf
        sudo sed -i 's/#LoadModule php_module/LoadModule php_module/' /etc/httpd/conf/httpd.conf
        sudo sed -i 's/#Include conf\/extra\/php_module.conf/Include conf\/extra\/php_module.conf/' /etc/httpd/conf/httpd.conf
        sudo systemctl restart httpd
    elif [ "$OS" == "redhat" ]; then
        sudo yum install -y php php-mysqlnd
        sudo systemctl restart httpd
    fi
}

# Cài đặt MariaDB/MySQL
install_mariadb() {
    echo "=========================="
    echo "Cài đặt MariaDB..."
    if [ "$OS" == "debian" ]; then
        sudo apt install -y mariadb-server mariadb-client
        sudo systemctl start mariadb
        sudo systemctl enable mariadb
    elif [ "$OS" == "arch" ]; then
        sudo pacman -S --noconfirm mariadb
        sudo mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
        sudo systemctl start mariadb
        sudo systemctl enable mariadb
    elif [ "$OS" == "redhat" ]; then
        sudo yum install -y mariadb-server mariadb
        sudo systemctl start mariadb
        sudo systemctl enable mariadb
    fi

    echo "Thiết lập mật khẩu root cho MariaDB..."
    sudo mysql_secure_installation
}

# Cấu hình Virtual Host
configure_virtualhost() {
    echo "=========================="
    echo "Cấu hình Virtual Host cho $1..."
    if [ "$OS" == "debian" ]; then
        sudo mkdir -p /var/www/$1/public_html
        sudo chown -R $USER:$USER /var/www/$1/public_html

        cat <<EOL | sudo tee /etc/apache2/sites-available/$1.conf
<VirtualHost *:80>
    ServerAdmin admin@$1
    DocumentRoot "/var/www/$1/public_html"
    ServerName $1
    ServerAlias www.$1
    ErrorLog "\${APACHE_LOG_DIR}/$1-error.log"
    CustomLog "\${APACHE_LOG_DIR}/$1-access.log" combined
</VirtualHost>
EOL

        sudo a2ensite $1.conf
        sudo systemctl restart apache2
    elif [ "$OS" == "arch" ]; then
        sudo mkdir -p /srv/http/$1/public_html
        sudo chown -R $USER:$USER /srv/http/$1/public_html

        cat <<EOL | sudo tee /etc/httpd/conf/extra/$1.conf
<VirtualHost *:80>
    ServerAdmin admin@$1
    DocumentRoot "/srv/http/$1/public_html"
    ServerName $1
    ServerAlias www.$1
    ErrorLog "/var/log/httpd/$1-error_log"
    CustomLog "/var/log/httpd/$1-access_log" common
</VirtualHost>
EOL

        echo "Include conf/extra/$1.conf" | sudo tee -a /etc/httpd/conf/httpd.conf
        sudo systemctl restart httpd
    elif [ "$OS" == "redhat" ]; then
        sudo mkdir -p /var/www/$1/public_html
        sudo chown -R $USER:$USER /var/www/$1/public_html

        cat <<EOL | sudo tee /etc/httpd/conf.d/$1.conf
<VirtualHost *:80>
    ServerAdmin admin@$1
    DocumentRoot "/var/www/$1/public_html"
    ServerName $1
    ServerAlias www.$1
    ErrorLog "/var/log/httpd/$1-error_log"
    CustomLog "/var/log/httpd/$1-access_log" common
</VirtualHost>
EOL

        sudo systemctl restart httpd
    fi
}

# Cài đặt Wordpress
install_wordpress() {
    echo "=========================="
    echo "Cài đặt Wordpress cho $1..."
    if [ "$OS" == "debian" ]; then
        cd /var/www/$1/public_html
    elif [ "$OS" == "arch" ]; then
        cd /srv/http/$1/public_html
    elif [ "$OS" == "redhat" ]; then
        cd /var/www/$1/public_html
    fi
    wget https://wordpress.org/latest.tar.gz
    tar -xvzf latest.tar.gz --strip-components=1
    rm latest.tar.gz

    echo "Tạo database cho Wordpress..."
    DB_NAME=$(echo $1 | tr . _)

    read -p "Vui lòng nhập tên người dùng cho Wordpress database (mặc định: wp_user): " wp_user
    wp_user=${wp_user:-wp_user}

    while true; do
        read -sp "Vui lòng nhập mật khẩu cho người dùng $wp_user: " wp_password
        echo
        read -sp "Xác nhận lại mật khẩu: " wp_password_confirm
        echo
        if [ "$wp_password" == "$wp_password_confirm" ]; then
            break
        else
            echo "Mật khẩu không khớp. Vui lòng thử lại."
        fi
    done

    sudo mysql -e "CREATE DATABASE ${DB_NAME};"
    sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${wp_user}'@'localhost' IDENTIFIED BY '${wp_password}';"
    sudo mysql -e "FLUSH PRIVILEGES;"

    cp wp-config-sample.php wp-config.php
    sed -i "s/database_name_here/$DB_NAME/" wp-config.php
    sed -i "s/username_here/wp_user/" wp-config.php
    sed -i "s/password_here/$wp_password/" wp-config.php
}

#Thêm host vào trong /etc/hosts
add_host() {
    if grep -q "$domain" /etc/hosts; then
        echo "Tên miền $domain đã tồn tại trong /etc/hosts."
    else
        # Thêm tên miền vào /etc/hosts
        echo "$ip    $domain" | sudo tee -a /etc/hosts > /dev/null
        echo "Tên miền $domain đã được thêm vào /etc/hosts với địa chỉ IP $ip."
    fi
}

#Thêm ServerName vào apache2.conf hoặc httpd.conf
add_ServerName() {
    if [ "$OS" == "debian" ]; then
        apache2_conf="/etc/apache2/apache2.conf"
    elif [ "$OS" == "arch" ]; then
        apache2_conf="/etc/httpd/conf/httpd.conf"
    elif [ "$OS" == "redhat" ]; then
        apache2_conf="/etc/httpd/conf/httpd.conf"
    fi

    if grep -q "ServerName $domain" "$apache2_conf"; then
        echo "ServerName $domain đã tồn tại trong $apache2_conf."
    else
        echo "ServerName $domain" | sudo tee -a "$apache2_conf" > /dev/null
        echo "ServerName $domain đã được thêm vào $apache2_conf."
    fi
    
    if [ "$OS" == "debian" ]; then
        sudo systemctl restart apache2
    elif [ "$OS" == "arch" ] || [ "$OS" == "redhat" ]; then
        sudo systemctl restart httpd
    fi
}

# Bắt đầu script
check_os
read -p "Vui lòng nhập tên miền: " domain
read -
