#!/bin/bash
# Directory to check
DIR="/kubepanel"

# Check if directory exists
if [ -d "$DIR" ]; then
    # Check if directory is empty
    entries=$(ls -A "$DIR")
    if [ "$entries" = "lost+found" ]; then
        echo "Directory is empty. Cloning repository..."
        rmdir "$DIR/lost+found"
        git clone https://github.com/laszlokulcsar/kubepanel.git "$DIR"
        mkdir $DIR/yaml_templates
        #DJANGO_SUPERUSER_EMAIL DJANGO_SUPERUSER_USERNAME DJANGO_SUPERUSER_PASSWORD KUBEPANEL_DOMAIN env variables should be set for the following command
        sed -i "s/<KUBEPANEL_DOMAIN>/$KUBEPANEL_DOMAIN/g" $DIR/kubepanel/settings.py
        /usr/local/bin/python $DIR/manage.py createsuperuser --noinput
        /usr/local/bin/python $DIR/manage.py firstrun -d $KUBEPANEL_DOMAIN
    else
        echo "Directory is not empty."
    fi
else
    echo "Directory does not exist."
fi
