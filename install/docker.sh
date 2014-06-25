#!/bin/bash

### PREPARE ###

# docker pull koding/mongo
# docker pull koding/postgres
# docker pull koding/rabbitmq
# docker pull koding/redis
# docker build --no-cache -t koding/codebase1 .

# Remove all stopped containers.
# docker rm $(docker ps -a -q)

# Remove all untagged images
# docker rmi $(docker images | grep "^<none>" | awk "{print $3}")

### RUN ###

PRJ=/opt/koding       # `pwd`
BLD=./BUILD_DATA        # /BUILD_DATA
CFG=`cat $BLD/BUILD_CONFIG`
RGN=`cat $BLD/BUILD_REGION` 
HST=`cat $BLD/BUILD_HOSTNAME`
PBKEY=$PRJ/certs/test_kontrol_rsa_public.pem
PVKEY=$PRJ/certs/test_kontrol_rsa_private.pem
LOG=/tmp/logs

mkdir -p $LOG

docker run  --expose=27017                        --net=host -d --name=mongo            --entrypoint=mongod                    koding/mongo    --smallfiles --nojournal
sleep 5
docker run  --expose=5432                         --net=host -d --name=postgres                                                koding/postgres postgres
docker run  --expose=5672                         --net=host -d --name=rabbitmq                                                koding/rabbitmq rabbitmq-server
docker run  --expose=6379                         --net=host -d --name=redis                                                   koding/redis    redis-server

echo sleeping some secs to give some time to db servers to start
sleep 5

echo starting go workers.
docker run  --expose=4000    --volume=$LOG:$LOG   --net=host -d --name=kontrol          --entrypoint=$PRJ/go/bin/kontrol       koding/codebase1 -c $CFG -r $RGN
docker run  --expose=4001    --volume=$LOG:$LOG   --net=host -d --name=proxy            --entrypoint=$PRJ/go/bin/reverseproxy  koding/codebase1 -region $RGN -host $HST -env production 
docker run                   --volume=$LOG:$LOG   --net=host -d --name=kloud            --entrypoint=$PRJ/go/bin/kloud         koding/codebase1 -c $CFG -r $RGN -public-key $PBKEY -private-key $PVKEY -kontrol-url "http://$HST:4000/kite"
docker run                   --volume=$LOG:$LOG   --net=host -d --name=rerouting        --entrypoint=$PRJ/go/bin/rerouting     koding/codebase1 -c $CFG
docker run                   --volume=$LOG:$LOG   --net=host -d --name=cronJobs         --entrypoint=$PRJ/go/bin/cron          koding/codebase1 -c $CFG
docker run  --expose=8008    --volume=$LOG:$LOG   --net=host -d --name=broker           --entrypoint=$PRJ/go/bin/broker        koding/codebase1 -c $CFG

echo starting node workers.
docker run  --expose=80      --volume=$LOG:$LOG   --net=host -d --name=webserver        --entrypoint=node koding/codebase1 $PRJ/server/index.js               -c $CFG -p 80   --disable-newrelic
docker run  --expose=3526    --volume=$LOG:$LOG   --net=host -d --name=sourceMapServer  --entrypoint=node koding/codebase1 $PRJ/server/lib/source-server.js   -c $CFG -p 3526
docker run                   --volume=$LOG:$LOG   --net=host -d --name=authWorker       --entrypoint=node koding/codebase1 $PRJ/workers/auth/index.js         -c $CFG
docker run  --expose=3030    --volume=$LOG:$LOG   --net=host -d --name=social           --entrypoint=node koding/codebase1 $PRJ/workers/social/index.js       -c $CFG -p 3030 --disable-newrelic --kite-port=13020
docker run                   --volume=$LOG:$LOG   --net=host -d --name=guestCleaner     --entrypoint=node koding/codebase1 $PRJ/workers/guestcleaner/index.js -c $CFG
docker run                   --volume=$LOG:$LOG   --net=host -d --name=emailSender      --entrypoint=node koding/codebase1 $PRJ/workers/emailsender/index.js  -c $CFG
