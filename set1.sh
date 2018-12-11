#!/bin/bash

#检查系统是否已经安装相应软件
rpm -ql php && yum -y remove php

if [ `sed -r 's/.* ([0-9]+)\..*/\1/' /etc/centos-release` -eq 7 ]; then
        rpm -ql httpd && systemctl stop httpd
        rpm -ql php-fpm && systemctl stop php-fpm
else
        rpm -ql httpd && service httpd stop
        rpm -ql php-fpm && service php-fpm stop
fi

mkdir -p /app/lamp-src
cd /app/lamp-src

#下载http2.4.X,apr-1.6.X,apr-util-1.6.X,php-7.1.X,wordpress-4.8.X等源码包
wget ftp://twenty-six:twenty-six@172.17.0.1/files/lamp/httpd-2.4.28.tar.bz2
wget ftp://twenty-six:twenty-six@172.17.0.1/files/lamp/apr-1.6.2.tar.gz
wget ftp://twenty-six:twenty-six@172.17.0.1/files/lamp/apr-util-1.6.0.tar.gz
wget ftp://twenty-six:twenty-six@172.17.0.1/files/lamp/php-7.1.10.tar.xz
wget ftp://twenty-six:twenty-six@172.17.0.1/files/lamp/wordpress-4.8.1-zh_CN.tar.gz

#对下载好的源码包进行解压
tar -xvf httpd-2.4.28.tar.bz2
mkdir -p httpd-2.4.28/srclib/apr
mkdir /app/lamp-src/httpd-2.4.28/srclib/apr-util
tar -xvf /app/lamp-src/apr-1.6.2.tar.gz 
tar -xvf /app/lamp-src/apr-util-1.6.0.tar.gz 
cp -r apr-1.6.2/* httpd-2.4.28/srclib/apr
cp -r apr-util-1.6.0/* httpd-2.4.28/srclib/apr-util

#安装开发工具包组
yum groupinstall "Development tools" -y

#安装http相关的依赖包
yum install openssl-devel expat-devel pcre-devel -y

#编译安装http2.4.X
cd httpd-2.4.28/
./configure --prefix=/app/httpd24 \
--sysconfdir=/etc/httpd24 \
--enable-so \
--enable-ssl \
--enable-cgi \
--enable-rewrite \
--with-zlib \
--with-pcre \
--with-included-apr \
--enable-modules=most \
--enable-mpms-shared=all \
--with-mpm=prefork

make && make install

#添加环境变量
cd /etc/profile.d/
echo PATH=$PATH:/app/httpd24/bin/ > lamp.sh
. lamp.sh

#启动httpd服务
apachectl

#首先安装php依赖包
yum install libxml2-devel bzip2-devel libmcrypt-devel -y

cd /app/lamp-src/
tar -xvf php-7.1.10.tar.xz
cd php-7.1.10

#编译安装php
./configure --prefix=/app/php \
--enable-mysqlnd \
--with-mysqli=mysqlnd \
--with-pdo-mysql=mysqlnd \
--with-openssl \
--enable-mbstring \
--with-freetype-dir \
--with-jpeg-dir \
--with-png-dir \
--with-zlib \
--with-libxml-dir=/usr \
--enable-xml \
--enable-sockets \
--enable-fpm \
--with-mcrypt \
--with-config-file-path=/etc/ \
--with-config-file-scan-dir=/etc/php.d \
--enable-maintainer-zts \
--with-bz2

make && make install

#将php的初始化文件拷贝到 /etc/目录下，并改名为php.ini
cp php.ini-production /etc/php.ini

#将php的服务启动脚本拷贝到 /etc/rc.d/init.d/ 目录下，并改名为php-fpm
#同时设置该服务的运行级别
cp sapi/fpm/init.d.php-fpm /etc/rc.d/init.d/php-fpm
chmod +x /etc/rc.d/init.d/php-fpm
systemctl enable php-fpm

cd /app/php/etc/
#启用php-pfm服务的配置文件
cp php-fpm.conf.default php-fpm.conf
#把pid的注释行取消掉，启用php-pfm服务的pid设置文件
sed -i '/pid/s/;//' php-fpm.conf 

#启用php-fpm服务的一些其他配置选项
#该文件里可以配置php-fpm服务的进程、用户等选项
#一般情况下默认即可，有特殊需求的可以根据自身需求进行修改
cd /app/php/etc/php-fpm.d/
cp www.conf.default www.conf

#开启php-fpm服务
systemctl start php-fpm 

cd /etc/httpd24/
echo '
#这两项是用来设置httpd程序可以识别 .php和.phps 结尾的php程序文件的
AddType application/x-httpd-php .php
AddType application/x-httpd-php-source .phps

#关闭正向代理
ProxyRequests Off 
#匹配httpd服务主机上的PHP程序文件路径
ProxyPassMatch ^/(.*\.php)$ fcgi://127.0.0.1:9000/app/httpd24/htdocs/$1' >> httpd.conf

#将httpd服务主页修改成一个PHP程序文件生成的页面
sed -i 's/index.html/index.php &/' httpd.conf

#将 /etc/httpd24/httpd.conf 文件中以下两行的注释取消掉
#httpd2.4中这两个模块是专门针对FastCGI进行实现的
#proxy_fcgi.so是对proxy.so的扩展
sed -i '/proxy.so/s/#//' httpd.conf
sed -i '/proxy_fcgi.so/s/#//' httpd.conf

#重启httpd服务
apachectl restart

#创建测试php连接Mariadb的文件
cd /app/httpd24/htdocs/
echo '<html><body><h1> LAMP </h1></body></html>
<?php
$mysqli=new mysqli("172.17.254.98","wpuser","123456");
if(mysqli_connect_errno()){
echo "连接数据库失败!";
$mysqli=null;
exit;
}
echo "连接数据库成功!";
$mysqli->close();
phpinfo();
?>' > index.php

#安装配置wordpress
cd
wget ftp://twenty-six:twenty-six@172.17.0.1/files/lamp/wordpress-4.8.1-zh_CN.tar.gz
tar xvf wordpress-4.8.1-zh_CN.tar.gz  -C /app/httpd24/htdocs
cd /app/httpd24/htdocs
mv wordpress/ blog/

cd /app/httpd24/htdocs/blog/
cp wp-config-sample.php wp-config.php

sed -i 's/database_name_here/wpdb/' wp-config.php 
sed -i 's/username_here/wpuser/' wp-config.php
sed -i 's/password_here/123456/' wp-config.php
sed -i 's/localhost/172.17.254.98/' wp-config.php


#关闭防火墙
iptables -F
#查看httpd服务80端口是否打开
ss -ntl
#查看php-fpm服务是否设置为开机自启动
chkconfig --list php-fpm
