# GeoNode Project

GeoNode Django project. This can be forked to customize, add Python modules or Django apps to your GeoNode instance.

> [!IMPORTANT]  
This repository has been converted from a Django project template into a concrete Django project, ready to be forked and deployed. The goal is to make it easier to track updates and pull changes from this repo into your own project.s

## Table of Contents

-  [Quick Docker Start](#quick-docker-start)
-  [Reproduire la configuration sur une nouvelle machine](#reproduire-la-configuration-sur-une-nouvelle-machine)
-  [Start your server using Docker](#start-your-server-using-docker)
-  [Run the instance in development mode](#run-the-instance-in-development-mode)
-  [Run the instance on a public site](#run-the-instance-on-a-public-site)
-  [Stop the Docker Images](#stop-the-docker-images)
-  [Backup and Restore from Docker Images](#backup-and-restore-the-docker-images)
-  [Recommended: Track your changes](#recommended-track-your-changes)
-  [Hints: Configuring `requirements.txt`](#hints-configuring-requirementstxt)

## Reproduire la configuration sur une nouvelle machine

Ce guide décrit le déploiement GeoNode avec GeoServer et un MapStore autonome,
séparé de la carte intégrée à GeoNode. Les commandes supposent Docker Compose
v2 et Docker Desktop sous Windows; adaptez les chemins et adresses si besoin.

### 1. Préparer la machine et le dépôt

Installer Git, Docker Desktop et Python, puis cloner le dépôt :

```powershell
git clone https://github.com/Alban558/geonode-mapstore-protege.git
cd geonode-mapstore-protege
```

Le premier démarrage construit et lance les services; prévoir suffisamment de
mémoire pour les conteneurs GeoServer et GeoNode.

### 2. Copier les données SIG et configurer leur chemin

Copier les fichiers SIG nécessaires sur la nouvelle machine. Dans `.env`,
configurer `SIG_DATA_PATH` pour désigner le dossier hôte qui les contient.
L’exemple fourni pointe vers `D:/SIG_DATA`; ce chemin n’est pas transféré par
Git. Compose monte ce dossier en lecture/écriture dans GeoServer sous
`/SIG_DATA`.

Le montage des fichiers ne publie pas automatiquement une couche. La couche
testée ici doit être importée et publiée dans GeoNode sous le nom
`geonode:COMMUNE-1` avant que l’initialiseur puisse vérifier son accès.

### 3. Créer la configuration locale

Créer `.env` à partir du modèle, avec des mots de passe générés localement :

```powershell
python create-envfile.py --hostname localhost --env_type dev --email admin@example.com
```

Vérifier que `.env` contient les paramètres `MAPSTORE_*` et `SIG_DATA_PATH`.
Si le fichier a été créé avant l’ajout de ces paramètres, les ajouter depuis
`.env.sample` et remplacer le chemin par celui de la nouvelle machine.
Ne jamais publier `.env`, les mots de passe ou les données SIG. `.env.sample`
ne contient que des valeurs de modèle.

Sur une installation GeoServer vierge, les identifiants d’amorçage sont
`admin` / `geoserver`; l’initialiseur crée ensuite le compte administrateur
configuré dans `.env`. Pour une installation avec des données GeoServer déjà
initialisées, les identifiants d’amorçage doivent correspondre à ceux de ces
données.

### 4. Démarrer GeoNode, GeoServer et MapStore

Depuis la racine du dépôt :

```powershell
docker compose up -d --build
```

GeoNode est disponible sur `http://localhost/`. MapStore autonome est
disponible sur `http://localhost:8081/mapstore/`. Connectez-vous à MapStore
avec l’utilisateur `admin` et le mot de passe
`MAPSTORE_INITIAL_ADMIN_PASSWORD` du fichier `.env`.
Après la première connexion, changez le mot de passe administrateur MapStore et
retirez `MAPSTORE_INITIAL_ADMIN_PASSWORD` de `.env`.

Si `geonode:COMMUNE-1` n’était pas encore publiée au premier démarrage,
publiez-la dans GeoNode, puis relancez l’initialiseur :

```powershell
docker compose up -d --force-recreate mapstore-reader-init
```

Le rôle `MAPSTORE_READ` et le compte lecteur GeoServer sont créés par
l’initialiseur. Les règles GeoFence maintiennent la couche inaccessible aux
requêtes anonymes.

### 5. Ajouter le catalogue WMS à MapStore

Dans le catalogue de MapStore, ajouter un service WMS avec l’adresse :

```text
http://localhost:8081/geoserver/wms
```

Le gateway GeoServer exige une authentification HTTP Basic. Utiliser
`MAPSTORE_GEOSERVER_READER_USER` et
`MAPSTORE_GEOSERVER_READER_PASSWORD` de `.env`; ces identifiants sont distincts
de ceux de MapStore et de GeoNode. Le comportement du dialogue d’authentification
dans l’interface MapStore reste à confirmer.

Les tests HTTP confirment que les requêtes WMS anonymes sont refusées et que le
compte lecteur peut obtenir les capacités et une image `GetMap`. La validation
visuelle de l’ajout du catalogue et du rendu dans l’interface MapStore reste à
effectuer.

### 6. Vérifier et conserver l’installation

Vérifier l’état des conteneurs et le résultat de l’initialiseur :

```powershell
docker compose ps
docker compose logs mapstore-reader-init
```

Les appels WMS anonymes doivent être refusés; le compte lecteur doit voir
`geonode:COMMUNE-1` et obtenir une image pour `GetMap`. Les données GeoNode,
GeoServer et MapStore sont également conservées dans des volumes Docker :
cloner le dépôt ne copie pas ces volumes. Pour retrouver les données publiées
sur une autre machine, il faut les réimporter ou migrer les volumes concernés.

L’authentification Basic sur HTTP n’est pas chiffrée. L’accès sur `localhost`
convient au test local; ne publiez pas le port `8081` sur Internet sans HTTPS.

## Quick Docker Start
To setup your project follow these instructions:

1. Generate the project

    ```bash
    git clone https://github.com/GeoNode/geonode-project.git -b <your_branch>
    cd geonode-project
    ```

2. Create the .env file

    An `.env` file is requird to run the application. It can be created from the `.env.sample` either manually or with the create-envfile.py script.

    The script accepts several parameters to create the file, in detail:

    - *hostname*: e.g. master.demo.geonode.org, default localhost
    - *https*: (boolean), default value is False
    - *email*: Admin email (this is required if https is set to True since a valid email is required by Letsencrypt certbot)
    - *env_type*: `prod`, `test` or `dev`. It will set the `DEBUG` variable to `False` (`prod`, `test`) or `True` (`dev`)
    - *geonodepwd*: GeoNode admin password (required inside the .env)
    - *geoserverpwd*: Geoserver admin password (required inside the .env)
    - *mapstorepwd*: Standalone MapStore admin password (required inside the .env)
    - *mapstoregeoserverpwd*: Standalone MapStore GeoServer reader password (required inside the .env)
    - *pgpwd*: PostgreSQL password (required inside the .env)
    - *dbpwd*: GeoNode DB user password (required inside the .env)
    - *geodbpwd*: Geodatabase user password (required inside the .env)
    - *clientid*: Oauth2 client id (required inside the .env)
    - *clientsecret*: Oauth2 client secret (required inside the .env)
    - *authapikey*: Oauth2 API Key (required inside the .env)
    - *secret key*: Django secret key (required inside the .env)
    - *sample_file*: absolute path to a env_sample file used to create the env_file. If not provided, the one inside the GeoNode project is used.
    - *file*: absolute path to a json file that contains all the above configuration

     **NOTE:**
    - if the same configuration is passed in the json file and as an argument, the CLI one will overwrite the one in the JSON file
    - If some value is not provided, a random string is used

      Example USAGE

      ```bash
      python create-envfile.py -f /opt/core/geonode-project/file.json \
        --hostname localhost \
        --https \
        --email random@email.com \
        --geonodepwd gn_password \
        --geoserverpwd gs_password \
        --mapstorepwd ms_password \
        --mapstoregeoserverpwd ms_geoserver_read_password \
        --pgpwd pg_password \
        --dbpwd db_password \
        --geodbpwd _db_password \
        --clientid 12345 \
        --clientsecret abc123 
      ```

      Example JSON expected:

      ```JSON
      {
        "hostname": "value",
        "https": "value",
        "email": "value",
        "geonodepwd": "value",
        "geoserverpwd": "value",
        "mapstorepwd": "value",
        "mapstoregeoserverpwd": "value",
        "pgpwd": "value",
        "dbpwd": "value",
        "geodbpwd": "value",
        "clientid": "value",
        "clientsecret": "value"
      } 
      ```

### Start your server using Docker

You need Docker 1.12 or higher, get the latest stable official release for your platform.
Once you have the project configured run the following command from the root folder of the project.

1. Run `docker-compose` to start it up (get a cup of coffee or tea while you wait)

    ```bash
    docker-compose build --no-cache
    docker-compose up -d
    ```

    ```bash
    set COMPOSE_CONVERT_WINDOWS_PATHS=1
    ```

    before running `docker-compose up`

2. Access the site on http://localhost/

The `geoserver-init` service creates or verifies the account configured by
`GEOSERVER_ADMIN_USER` and grants it the `ADMIN` and `GROUP_ADMIN` roles. On a
fresh stock GeoServer data directory, the bootstrap credentials are `admin` /
`geoserver`. If you change them, they must match the account in your seeded
GeoServer data directory. The initializer does not delete the bootstrap
account; production deployments should use secured seed data and disable or
rotate that account after validating the configured administrator.

## Run the instance on a public site

### Preparation of the image (First time only)

**NOTE**: In this example we are going to publish to the public IP http://123.456.789.111

```bash
vim .env
  --> replace localhost with 123.456.789.111 everywhere
```

### Startup the image

```bash
docker-compose up --build -d
```

### Stop the Docker Images

```bash
docker-compose stop
```

### Fully Wipe-out the Docker Images

**WARNING**: This will wipe out all the repositories created until now.

**NOTE**: The images must be stopped first

```bash
docker system prune -a
```

## Backup and Restore from Docker Images

### Run a Backup

```bash
SOURCE_URL=$SOURCE_URL TARGET_URL=$TARGET_URL ./geonode_project/br/backup.sh $BKP_FOLDER_NAME
```

- BKP_FOLDER_NAME:
  Default value = backup_restore
  Shared Backup Folder name.
  The scripts assume it is located on "root" e.g.: /$BKP_FOLDER_NAME/

- SOURCE_URL:
  Source Server URL, the one generating the "backup" file.

- TARGET_URL:
  Target Server URL, the one which must be synched.

e.g.:

```bash
docker exec -it django4geonode_project sh -c 'SOURCE_URL=$SOURCE_URL TARGET_URL=$TARGET_URL ./geonode_project/br/backup.sh $BKP_FOLDER_NAME'
```

### Run a Restore

```bash
SOURCE_URL=$SOURCE_URL TARGET_URL=$TARGET_URL ./geonode_project/br/restore.sh $BKP_FOLDER_NAME
```

- BKP_FOLDER_NAME:
  Default value = backup_restore
  Shared Backup Folder name.
  The scripts assume it is located on "root" e.g.: /$BKP_FOLDER_NAME/

- SOURCE_URL:
  Source Server URL, the one generating the "backup" file.

- TARGET_URL:
  Target Server URL, the one which must be synched.

e.g.:

```bash
docker exec -it django4geonode_project sh -c 'SOURCE_URL=$SOURCE_URL TARGET_URL=$TARGET_URL ./geonode_project/br/restore.sh $BKP_FOLDER_NAME'
```

## Recommended: Track your changes

Step 1. Install Git (for Linux, Mac or Windows).

Step 2. Init git locally and do the first commit:

```bash
git init
git add *
git commit -m "Initial Commit"
```

Step 3. Set up a free account on github or bitbucket and make a copy of the repo there.

## Hints: Configuring `requirements.txt`

You may want to configure your requirements.txt, if you are using additional or custom versions of python packages. For example

```python
Django==3.2.16
git+git://github.com/<your organization>/geonode.git@<your branch>
```

## Increasing PostgreSQL Max connections

In case you need to increase the PostgreSQL Max Connections , you can modify
the **POSTGRESQL_MAX_CONNECTIONS** variable in **.env** file as below:

```
POSTGRESQL_MAX_CONNECTIONS=200
```

In this case PostgreSQL will run accepting 200 maximum connections.

## Developing with Dev Containers in VS Code

This repo includes a .devcontainer folder with the condigurations to run Django and Celery inside a VS Code Dev Container.
A `docker.sh` script aliases the `docker compose` command with the pre-configured arguments to use the customized compose files.

You can run the Dev Container with the following commands:

```bash
cd .devcontainer
chmod +x docker.sh
./docker.sh build
.docker.sh up -d
```

The Django and the Celery containers will be started **without** running the Django and Celery processes. They can be started manually inside the dev container. The container is autopopulated with VS Code development extensions for Python and a list of pre-configured luanch configurations (for Django and Celery).

Within VS Code open the command palette with `Ctrl+P` and run `Dev Container: Reopen in Container`. VS Code will recognize the presence of the two dev container, and will allow to reopen the current window inside the container's workspace.
Wait a few seconds to let VS Code setup the dev extensions, then you should see the launch configurations.

To simplify the debugging of GeoNode and the GeoNode client, these modules can be installed as editable (PEP-660) with the following commands:

```bash
pip install -e git+https://github.com/GeoNode/geonode.git@master#egg=geonode --src=/usr/src
pip install -e git+https://github.com/GeoNode/geonode-mapstore-client.git@master#egg=django_geonode_mapstore_client --src=/usr/src
```

The modules will be isntalled under `/usr/src` and so at te root of the VS Code workspace.
Notice that at the time of writing Pylance can't resolve PEP-660 editable installs. For this reason the `.vscode/settings.py` contain extrPaths for the modules.

### Running Django
The `GeoNode` launch configuration for Django sets the `ASYNC_SIGNALS` env variable to False. This way GeoNode can be developed and debugged in sync mode, without Celery.
If you want to test Django in async mode, you can switch this variable to `True` and tun Celery (see below).

Running the Debug sessions for Django will start Django with its internal development server.

### Running Celery
Celery exectutions requires luanching three Debug processes:

 - `Celery Worker`: the generic worker process
 - `Celery Beat`: the scheduler
 - `Celery Harvesters`: The worker dedicated to the harvesters

You can also remove the `-X harvesting` argument inside the Celery Worker launch configuration to have also the harvesters running in the same worker. this way you don't need to run the Beat and the Celery Harvesters processes.