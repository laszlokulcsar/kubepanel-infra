#!/bin/bash
chown vmail:vmail /var/mail/vmail
rm -rf /var/spool/postfix/pid/*
/etc/init.d/postfix start
/etc/init.d/dovecot start
while true; do sleep 36000; done;
