## Service Environment Variable

-e MAPR_CLUSTER=my.cluster.com -e MAPR_CLDB_HOSTS=192.168.99.18 -e MAPR_CONTAINER_USER=mapr -e MAPR_MOUNT_PATH=/mapr



***** MAPR 5.2.1 *****
    # Start MAPR
MAPR ın sitesinden sandbox indirip kullanabilirsiniz.
    # Start OpenTSDB
docker run -td -v /media/miwgates/Depo/Projeler_Docker/bin/OpenTSDB_2.3.0-MAPR/config:/MAPRConfig -e MAPR_CLUSTER=demo.mapr.com -e MAPR_CLDB_HOSTS=192.168.59.130 -e MAPR_CONTAINER_USER=mapr -e MAPR_MOUNT_PATH=/mapr -e CONFIG_FILE_PATH=/MAPRConfig -e OPENTSDB_CONFIG_FILE_PATH=/MAPRConfig/opentsdb.conf -e KAFKA2OPENTSDB_CONFIG_FILE_PATH=/MAPRConfig/kafka2opentsdb_application.properties -e START_OPENTSDB=1 -e START_KAFKA2OPENTSDB=0 --name OpenTSDB4MAPR bear/opentsdb-2.3:mapr-5.2





- docker run -td -v /media/miwgates/Depo/Projeler_Docker/bin/Kafka2OpenTSDB-MAPR/config:/tmp/config -e MAPR_CLUSTER=demo.mapr.com -e MAPR_CLDB_HOSTS=192.168.59.130 -e MAPR_CONTAINER_USER=mapr -e MAPR_MOUNT_PATH=/mapr -e CONFIG_FILE_PATH=/tmp/config -e START_OPENTSDB=1 --name k2o bear/kafka2opentsdbmapr:5.2.0
