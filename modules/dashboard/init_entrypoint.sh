#!/bin/bash
# Directory to check
DIR="/kubepanel"
mysql -h mariadb.kubepanel.svc.cluster.local -uroot -p$MARIADB_ROOT_PASSWORD -e "CREATE DATABASE IF NOT EXISTS $DBNAME; GRANT ALL PRIVILEGES ON $DBNAME.* TO $DBNAME@'%' IDENTIFIED BY '$MARIADB_ROOT_PASSWORD'"
# Check if directory exists
if [ -d "$DIR" ]; then
    # Check if directory is empty
    entries=$(ls -A "$DIR")
    if [ -z "$entries" ] || [ "$entries" = "lost+found" ];  then
        echo "Directory is empty. Cloning repository..."
        rmdir "$DIR/lost+found"
        git clone https://github.com/laszlokulcsar/kubepanel.git "$DIR" && mkdir $DIR/yaml_templates
        #DJANGO_SUPERUSER_EMAIL DJANGO_SUPERUSER_USERNAME DJANGO_SUPERUSER_PASSWORD KUBEPANEL_DOMAIN env variables should be set for the following command
        sed -i "s/<KUBEPANEL_DOMAIN>/$KUBEPANEL_DOMAIN/g" $DIR/kubepanel/settings.py
        sed -i "s/<MARIADB_ROOT_PASSWORD>/$MARIADB_ROOT_PASSWORD/g" $DIR/kubepanel/settings.py
        /usr/local/bin/python $DIR/manage.py makemigrations dashboard
        /usr/local/bin/python $DIR/manage.py migrate
        /usr/local/bin/python $DIR/manage.py createsuperuser --noinput
        /usr/local/bin/python $DIR/manage.py firstrun -d $KUBEPANEL_DOMAIN
    else
        echo $(date)
        echo "Directory is not empty."
    fi
else
    echo "Directory does not exist."
fi
