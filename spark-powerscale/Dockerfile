# Same image as before, with two changes for PowerScale S3:
#  1. Iceberg upgraded from 1.8.1 to 1.10.0. Iceberg 1.10 ships a newer AWS SDK
#     that no longer runs the MD5/ETag check that fails against PowerScale.
#  2. Hadoop's S3A connector added (hadoop-aws + AWS SDK bundle), so Spark can
#     use s3a:// paths for its warehouse dir and for plain (non-Iceberg) Hive tables.
#     Versions match Hadoop 3.3.4, which Spark 3.5 is built with.
FROM tabulario/spark-iceberg:latest

ARG ICEBERG_VERSION=1.10.0
ARG HADOOP_AWS_VERSION=3.3.4
ARG AWS_SDK_BUNDLE_VERSION=1.12.262
ARG MAVEN=https://repo1.maven.org/maven2

USER root
RUN rm -f /opt/spark/jars/iceberg-*.jar \
 && cd /opt/spark/jars \
 && curl -fsSLO ${MAVEN}/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/${ICEBERG_VERSION}/iceberg-spark-runtime-3.5_2.12-${ICEBERG_VERSION}.jar \
 && curl -fsSLO ${MAVEN}/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar \
 && curl -fsSLO ${MAVEN}/org/apache/hadoop/hadoop-aws/${HADOOP_AWS_VERSION}/hadoop-aws-${HADOOP_AWS_VERSION}.jar \
 && curl -fsSLO ${MAVEN}/com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_BUNDLE_VERSION}/aws-java-sdk-bundle-${AWS_SDK_BUNDLE_VERSION}.jar \
 && ls /opt/spark/jars | grep -E "iceberg|hadoop-aws|aws-java-sdk|hadoop-client"

# Trino's Python client, so notebooks can query Trino without running %pip install
RUN pip install --no-cache-dir trino
