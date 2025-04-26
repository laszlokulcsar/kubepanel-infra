#!/bin/bash
/etc/init.d/postfix start
/etc/init.d/dovecot start
while true; do sleep 36000; done;
