#!/bin/sh
# Downloads the S3A connector jars the Hive Metastore needs.
# Versions match Hadoop 3.3.6, which apache/hive:4.0.0 is built on.
set -e
mkdir -p jars
cd jars
curl -fLO https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.6/hadoop-aws-3.3.6.jar
curl -fLO https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.367/aws-java-sdk-bundle-1.12.367.jar
ls -lh
