#!/bin/bash
# CWP to VESTACP
# By Maksim Usmanov - Maks Skamasle
# Beta 0.2 mar 2017

# Imort account from Centos Web Panel to VESTACP
# This need a ssh conection, ssh port, and mysql password, I asume you have setup SSH keys
# This also need remote server whit grant access to your IP
# SSH is needit because CWP not have good backup system
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details. http://www.gnu.org/licenses/
###############################
# SSH CONNECTION REMOTE SERVER
sk_host="REMOTE_HOST_IP"
sk_port="22"

# MYSQL CONNECTION
# Use sk_host to connect
# User not needed asume you use root.
#
#Mysql root Password
sk_mysql='MYSQLrootPASS'

#Check connections
function check_ssh() {
# this will check ssh conection
echo " "
}

function sk_check_mysql () {
# this will check remote mysql connection
echo " "
}
function sk_grant_all () {
# This will do grant privileges to local IP
echo " "
}
####
if [ ! -d /root/tmp ]; then
	mkdir /root/sk_tmp
fi
sk_tmp=/root/sk_tmp

sk_cwp_user=$1
tput setaf 2
echo "Create user in vestacp"
tput sgr0
# crear usuario
sk_pass=$(date +%s | sha256sum | base64 | head -c 7)
/usr/local/vesta/bin/v-add-user $sk_cwp_user $sk_pass administrator@example.net default $sk_cwp_user $sk_cwp_user 
tput setaf 2
echo "Start Whit Domains"
tput sgr0
function deltmp() {
rm -rf $sk_tmp
}
function mysql_query() {
    mysql -h$sk_host -p$sk_mysql -s -e "$1" 2>/dev/null
}

function sk_get_domains() {
	mysql_query  "SELECT domain, path FROM root_cwp.domains WHERE user='$sk_cwp_user';"
}

function sk_get_sub_dom() {
	mysql_query "SELECT domain, subdomain, path FROM root_cwp.subdomains WHERE user='$sk_cwp_user';"
}
function sk_get_dbs() {
	mysql_query  "SHOW DATABASES" |grep ${sk_cwp_user}_
}

function sk_dump_it() {
	mysqldump -h$sk_host -p$sk_mysql $1 > $1.sql
}
function sk_get_md5(){
	query="SHOW GRANTS FOR '$1'@'localhost'"
	md5=$(mysql_query "$query" 2>/dev/null)
	md5=$(echo "$md5" |grep 'PASSWORD' |tr ' ' '\n' |tail -n1 |cut -f 2 -d \')
}

function sk_restore_imap_pass () {
# 1 account, 2 remote pass, 3 domain
	if [ -d /etc/exim ]; then
		EXIM=/etc/exim
	else
		EXIM=/etc/exim4
	fi
	sk_actual_pass=$(grep -w $1 ${EXIM}/domains/$3/passwd |tr '}' ' ' | tr ':' ' ' | cut -d " " -f 3)
	sk_orig_pass=$(echo $2 | cut -d'}' -f2)
	replace "${sk_actual_pass}" "${sk_orig_pass}" -- ${EXIM}/domains/$3/passwd > /dev/null
	echo "Password for $1@$3 was restored"
#################
# fix vesta needed
}

function sk_import_mail () {
	mysql_query "SELECT username, password, maildir, domain FROM postfix.mailbox where domain='$1'" | while read u p md dm
do
	sk_mail_acc=$(echo "$u" | cut -d "@" -f 1)
	echo " Add account $sk_mail_acc@$sk_cwp_user"
	v-add-mail-account ${sk_cwp_user} $1 $sk_mail_acc temppass
	echo "Start copy mails for $sk_mail_acc@$sk_cwp_user"
	rsync -av -e "ssh -p $sk_port" root@$sk_host:/var/vmail/${md}/ /home/${sk_cwp_user}/mail/${md} 2>&1 | 
	    			while read sk_file_dm; do
	       			 	sk_sync=$((sk_sync+1))
	       			 	echo -en "-- $sk_sync mails restored\r"
	    			done
	echo " "
	chown -R ${sk_cwp_user} /home/${sk_cwp_user}/mail/${md}
	sk_restore_imap_pass $sk_mail_acc $p $dm
done
}

function check_mail () {
	mail_domain=$1
	echo "Check mails accounts for $mail_domain"
	is_mail=$(mysql_query "SELECT EXISTS(SELECT * FROM postfix.mailbox WHERE domain='$mail_domain')")

	if [ "$is_mail" -ge "1" ]; then
		echo "Mail accounts found for $mail_domain"
		sk_import_mail $mail_domain
	else
		echo "No mail accounts found for $mail_domain"
	fi
}

sk_get_domains | while read sk_domain sk_path
do
	tput setaf 2
		echo "Add $sk_domain"
	tput sgr0
	v-add-domain $sk_cwp_user $sk_domain
	echo "Start copy files for $sk_domain"
	rsync -av -e "ssh -p $sk_port" root@$sk_host:$sk_path/ /home/${sk_cwp_user}/web/${sk_domain}/public_html 2>&1 | 
    			while read sk_file_dm; do
       			 	sk_sync=$((sk_sync+1))
       			 	echo -en "-- $sk_sync restored files\r"
    			done
	echo " "
	chown $sk_cwp_user:$sk_cwp_user -R /home/${sk_cwp_user}/web/${sk_domain}/public_html 
	chmod 751 /home/${sk_cwp_user}/web/${sk_domain}/public_html 
	check_mail $sk_domain
done  

tput setaf 2
	echo "Get Subdomains"
tput sgr0
	sk_get_sub_dom | while read sk_domain sk_sub sk_path
do
	tput setaf 2
		echo "Add ${sk_sub}.${sk_domain}"
	tput sgr0
	v-add-domain $sk_cwp_user ${sk_sub}.${sk_domain}
	echo "Start copy files for ${sk_sub}.${sk_domain}"
	rsync -av -e "ssh -p $sk_port" root@$sk_host:$sk_path/ /home/${sk_cwp_user}/web/${sk_sub}.${sk_domain}/public_html 2>&1 | 
    			while read sk_file_dm; do
       			 	sk_sync=$((sk_sync+1))
       			 	echo -en "-- $sk_sync restored files\r"
    			done
	echo " "
	chown $sk_cwp_user:$sk_cwp_user -R /home/${sk_cwp_user}/web/${sk_sub}.${sk_domain}/public_html 
	chmod 751 /home/${sk_cwp_user}/web/${sk_sub}.${sk_domain}/public_html 
done  

tput setaf 2
	echo "Start whit Databases"
tput sgr0

sk_get_dbs | while read sk_db
do
	echo "Get database  $sk_db"
	sk_dump_it $sk_db
	sk_get_md5 $sk_db
	echo "DB='$sk_db' DBUSER='$sk_db' MD5='$md5' HOST='localhost' TYPE='mysql' CHARSET='UTF8' U_DISK='0' SUSPENDED='no' TIME='00000' DATE='$DATE'" >> /usr/local/vesta/data/users/$sk_cwp_user/db.conf
	v-rebuild-databases $sk_cwp_user
	echo "Restore database  $sk_db"
	mysql $sk_db < $sk_db.sql
	rm -f $sk_db.sql
	echo "Restored $sk_db database whit user $sk_db" 
done

deltmp
