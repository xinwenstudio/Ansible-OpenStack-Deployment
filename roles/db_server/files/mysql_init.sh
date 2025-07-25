#!/bin/bash
set -e

MYSQL_ROOT_PASSWORD=""
SKIP_SECURE_INSTALL=0

while getopts "p:s" opt; do
  case $opt in
    p) MYSQL_ROOT_PASSWORD="$OPTARG" ;;
    s) SKIP_SECURE_INSTALL=1 ;;
    *) echo "Usage: $0 [-p <root_password>] [-s]"; exit 1 ;;
  esac
done

if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
  echo "Error: root password (-p) must be specified"
  exit 1
fi

# 启动 mysqld 服务（如果未启动）
if ! systemctl is-active --quiet mysqld; then
  echo "Starting mysqld service..."
  systemctl start mysqld
fi

# 尝试获取临时密码
TEMP_PASS=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}' 2>/dev/null || echo "")

if [ -n "$TEMP_PASS" ]; then
  echo "Changing temporary root password..."
  mysql -u root -p"${TEMP_PASS}" --connect-expired-password <<-EOF
    ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
    FLUSH PRIVILEGES;
EOF
else
  echo "Setting root password directly..."
  mysql -u root <<-EOF
    ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
    FLUSH PRIVILEGES;
EOF
fi

# 是否执行安全安装相关清理
if [ "$SKIP_SECURE_INSTALL" -eq 0 ]; then
  echo "Performing secure installation cleanup..."
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<-EOF
    DELETE FROM mysql.user WHERE User='';
    DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    DROP DATABASE IF EXISTS test;
    DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
    FLUSH PRIVILEGES;
EOF
else
  echo "Skipping secure install (-s option enabled)"
fi

echo "Granting root remote access..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<-EOF
  CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
  GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
  FLUSH PRIVILEGES;
EOF

echo "Restarting mysqld service..."
systemctl restart mysqld

echo "MySQL initialization complete! Root password: ${MYSQL_ROOT_PASSWORD}"

