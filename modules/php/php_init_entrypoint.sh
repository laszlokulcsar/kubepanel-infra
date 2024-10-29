#!/bin/bash
SMTP=$(dig +short smtp.kubepanel.svc.cluster.local)
iptables -t nat -I OUTPUT -m tcp -p tcp --dport 25 -j DNAT --to-destination $SMTP:25
iptables -t nat -A POSTROUTING -j MASQUERADE
