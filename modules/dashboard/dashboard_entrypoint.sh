#!/bin/bash
#v0.1
DJANGO_SECRET_KEY=$(openssl rand -base64 45)
export DJANGO_SECRET_KEY
/usr/local/bin/python /kubepanel/manage.py runserver 0.0.0.0:8000
