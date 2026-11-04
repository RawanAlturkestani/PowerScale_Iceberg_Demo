# Open Source Lakehouse on Dell PowerScale: Spark, Trino and Iceberg

A small, self-contained environment for testing an open source lakehouse stack on your own Dell PowerScale cluster, using its S3 interface. Everything except the storage runs in Docker on one host.

> **Community example for evaluation only.** This is not a Dell product and is not covered by Dell support. It uses lab shortcuts (S3 over HTTP, default database password) that are not suitable for production. Don't use it with production data.

## Contents

[Demo Objective](#demo-objective)

[Demo Architecture](#demo-architecture)

[Pre-requisites](#pre-requisites)

&emsp;[Create S3 buckets on PowerScale (OneFS)](#create-s3-buckets-on-powerscale-onefs)

&emsp;[Install and setup docker environment](#install-and-setup-docker-environment)

&emsp;[Download the required jars](#download-the-required-jars)

[Start The Environment](#start-the-environment)

## Demo Objective

Show open source lakehouse tools working with Dell PowerScale as their storage, using its S3 interface.

By the end of the demo you will see:
* Spark and Trino reading and writing the same Iceberg table on PowerScale, with no copies
* How Iceberg organises a table into three layers: catalog, metadata and data
* Where each layer lives: the catalog in the Hive Metastore (backed by PostgreSQL), the metadata and data files on PowerScale
* Iceberg features driven by its metadata, such as snapshots and time travel

**Who it's for:** Dell customers and partners who want to see open source data engines working with PowerScale.

## Demo Architecture

<img width="1674" height="1059" alt="Architecture: Spark and Trino share the Hive Metastore (backed by PostgreSQL) and read and write Iceberg tables on PowerScale S3" src="https://github.com/user-attachments/assets/0cfb6dd0-12f9-407c-a328-fe3ba7409c22" />

Spark and Trino both ask the Hive Metastore where a table's current Iceberg metadata file is, then read and write the metadata and data files directly on PowerScale. The metastore keeps only that pointer (plus table names and locks) in PostgreSQL.

### Scope

**Software (Docker images)**
* **Apache Spark + Iceberg + Jupyter**, based on `tabulario/spark-iceberg`, customised for PowerScale (Iceberg 1.10, Hadoop S3A connector, Trino client)
* **Trino**, a second query engine on the same tables
* **Apache Hive Metastore 4.0**, one shared Iceberg catalog for Spark and Trino
* **PostgreSQL 14**, the backend database for the Hive Metastore

**Compute**
* Any Docker-compatible host: a virtual machine or bare metal
* x86 (64-bit) required by the Spark image
* Minimum: 4 vCPU, 8 GB RAM, 30 GB free disk
* Recommended: 8 vCPU, 16 GB RAM, 50 GB free disk
* The disk holds the Docker images, the jars and the Postgres data only. Table data lives on PowerScale.

**Operating system**
* All four containers are Linux containers and need a Linux kernel
* Recommended: a Linux host (for example Ubuntu 22.04 or later, or RHEL 8 or later)
* Also works with Docker Desktop on Windows 10/11 (WSL 2 backend, run the shell commands inside WSL) or on macOS with an Intel CPU. Give Docker Desktop at least 8 GB of memory.
* Windows containers and Apple Silicon Macs are not supported

**Storage**
* Dell PowerScale (OneFS) S3, on premises
* One bucket, `warehouse`, holding all table data and Iceberg metadata
* No fixed bucket size needed. The walkthrough uses under 1 MB, and 1 GB of free space is plenty.

**Network**
* Containers talk to each other on a private Docker network
* The Docker host reaches PowerScale on its S3 port (9020 for HTTP)

**Lab simplifications (not for production)**
* S3 over HTTP rather than HTTPS
* Default database password and no login on Jupyter or Trino

## Pre-requisites

### Create S3 buckets on PowerScale (OneFS)

Run these on the PowerScale cluster, over SSH as an admin user (ask your storage admin if you don't manage the cluster):

    ssh root@<PowerScale IP>

> These commands change settings on the cluster. Use a test cluster or a test access zone where possible. If you use an access zone other than System, add `--zone <zone name>` to each `isi` command and use a path inside that zone.

**1. Enable the S3 service**

    isi services s3            # shows whether it is running
    isi services s3 enable     # only if it is disabled

**2. Allow S3 over HTTP (port 9020)**

    isi s3 settings global modify --https-only=false

> This setting is **cluster wide**. It allows HTTP for every S3 client on the cluster, not just this demo. Check with your storage or security team first, and note the current value (`isi s3 settings global view`) so you can set it back afterwards. This demo uses HTTP because the containers don't trust PowerScale's self-signed certificate out of the box.

**3. Create a user for the demo**

Use a dedicated user rather than root:

    isi auth users create lakehouse --enabled yes --password '<choose-a-password>'

**4. Create the bucket and its folder**

    mkdir -p /ifs/data/lakehouse/warehouse
    chown lakehouse /ifs/data/lakehouse/warehouse
    isi s3 buckets create warehouse /ifs/data/lakehouse/warehouse --owner lakehouse

* `warehouse` is the **bucket name**: what Spark and Trino use, for example `s3a://warehouse/...`
* `/ifs/data/lakehouse/warehouse` is the **path**: the folder on PowerScale where the files are stored. It must exist, or every write fails with "The specified key does not exist" (404).
* `--owner lakehouse` lets the demo user's key read and write the bucket

> In the web UI: **Protocols > Object storage (S3) > Buckets**. Enter the folder in the **Path** field and tick **Create path**. The **Description** field is only a label.

**5. Create an S3 key for the user**

    isi s3 keys create lakehouse

Copy both values straight away. The secret is shown only once:
* **Access ID**, for example `1_lakehouse_accid`
* **Secret key**

> In the web UI: **Protocols > Object storage (S3) > Key management > Add**, then pick the user.

> **Lab shortcut:** on a lab cluster you can use root instead of a new user (`--owner root` and `isi s3 keys create root`). Don't do this on a shared or production cluster.

**6. Check the setup**

    isi s3 buckets list
    ls -ld /ifs/data/lakehouse/warehouse

Type `exit` to leave the cluster, then from the Docker host:

    curl http://<PowerScale IP>:9020

An XML reply means S3 is reachable over HTTP.

### Install and setup docker environment

**1. Check the Docker host**

* Docker Engine and the Docker Compose plugin (`docker compose version` should work)
* **Internet access** to pull images from Docker Hub and download jars from Maven Central (`repo1.maven.org`)
* **Network access to PowerScale** on port 9020: `curl http://<PowerScale IP>:9020` should return XML

> **Behind a proxy?** Set the proxy for the Docker daemon (see Docker's [daemon proxy guide](https://docs.docker.com/engine/daemon/proxy/)), export `HTTPS_PROXY` in your shell for the jar download, and build with `docker compose build --build-arg HTTPS_PROXY=$HTTPS_PROXY spark`.

**2. Make sure the ports are free**

    sudo ss -tlnp | grep -E ':(8888|4040|8080)\b'

No output means they're free. Only these three need checking, because they are the only ports the demo opens on the Docker host.

| Port | Service | Used for | Accessible through browser |
|---|---|---|---|
| 8888 | Spark container | Jupyter notebook | Yes |
| 4040 | Spark container | Spark UI (jobs and queries) | Yes |
| 8080 | Trino | Trino web UI and client connections | Yes |
| 9083 | Hive Metastore | Thrift catalog connection | No, used only between the containers |
| 5432 | PostgreSQL | Metastore database | No, used only between the containers |
| 9020 | PowerScale | S3 (HTTP) | No, this port is on PowerScale. The Docker host connects out to it. |

**3. Get the project and add your settings**

Download this repository (**Code > Download ZIP**, or `git clone`), unpack it on the Docker host and open the project folder:

    cd PowerScale_Iceberg_Demo-main      # or PowerScale_Iceberg_Demo if you used git clone

Open the `.env` file in the project folder with any text editor and add your settings, using the IP and key from the bucket steps. For example, with nano:

    nano .env

    POWERSCALE_HOST=<your PowerScale IP>
    POWERSCALE_PORT=9020
    POWERSCALE_BUCKET=warehouse
    POWERSCALE_ACCESS_KEY=<your access ID>
    POWERSCALE_SECRET_KEY=<your secret key>

No quotes and no spaces around `=`.

The same `.env` file also has the password for the Hive Metastore's PostgreSQL database:

    HIVE_DB_PASSWORD=password

To use a different password, change the value after `=` in `.env` before you start the environment for the first time. Docker Compose passes it to PostgreSQL, the metastore and the notebook, so this is the only place to change it. PostgreSQL only reads it when its data volume is first created. To change it later, run `docker compose down -v` (this deletes the metastore database), edit `.env`, and start again.

`conf/spark-defaults.conf` can't read `.env`, so put the same IP there with this command:

    . ./.env && sed -i "s/<PowerScale IP>/$POWERSCALE_HOST/g" conf/spark-defaults.conf
    grep endpoint conf/spark-defaults.conf

The three endpoint lines should now show your IP. If you changed the port or bucket name in `.env`, change `9020` and `warehouse` in that file too.

### Download the required jars

The Hive Metastore needs three Java libraries. They are not stored in this repository. From the project folder, run:

    sh jars/get-jars.sh

| Jar | Size | Used by | Why it is needed |
|---|---|---|---|
| `hadoop-aws-3.3.6.jar` | ~769 KB | Hive Metastore | S3A connector, used to create database folders on PowerScale |
| `aws-java-sdk-bundle-1.12.367.jar` | ~297 MB | Hive Metastore | AWS SDK that the S3A connector depends on |
| `postgresql-42.7.3.jar` | ~1.1 MB | Hive Metastore, Spark | Lets the metastore store its catalog in PostgreSQL |

Check them:

    ls -lh jars/

Each jar must be a normal file (the line starts with `-`) with roughly the size above. If a line starts with `d`, or a jar is only a few hundred bytes, run the script again.

> **Do this before starting the containers.** If a jar is missing at start, Docker creates an empty folder in its place and the metastore fails with `ClassNotFoundException: org.postgresql.Driver` or `S3AFileSystem not found`. To fix it, run `docker compose down`, run the script again, and start again.

## Start The Environment

**1. Build and start**

From the project folder:

    docker compose build spark
    docker compose up -d

**2. Check that everything is running**

    docker compose ps

All four containers (`postgres`, `metastore`, `spark`, `trino`) should show **Up**. The metastore takes about 30 seconds on first start. To confirm it's ready:

    docker compose logs metastore | grep -iE "exception|Starting Hive Metastore"

You should see `Starting Hive Metastore Server` and no exceptions.

**3. Open the notebook**

By default the web UIs only listen on the Docker host itself (`BIND_ADDRESS=127.0.0.1` in `.env`), because Jupyter and Trino have no login. From your laptop, open an SSH tunnel to the Docker host:

    ssh -L 8888:localhost:8888 -L 8080:localhost:8080 -L 4040:localhost:4040 <user>@<Docker host IP>

Then open `http://localhost:8888`, go to `notebooks/General_Walkthrough.ipynb` and run the cells in order.

> On a trusted lab network you can set `BIND_ADDRESS=0.0.0.0` in `.env` and run `docker compose up -d` again. The UIs are then open to anyone who can reach the host, at `http://<Docker host IP>:8888`.

**4. Stop and clean up**

    docker compose down -v                  # stops the containers and deletes the Postgres data
    docker rmi spark-iceberg-powerscale     # removes the custom Spark image

On PowerScale, delete the bucket, its folder (deleting the bucket does not delete its files), the S3 key and the user. If you changed the HTTPS setting and it was `true` before, set it back with `isi s3 settings global modify --https-only=true`.

---

Licensed under the Apache License 2.0 (see [LICENSE](LICENSE)). Community example, not a Dell product and not covered by Dell support.
