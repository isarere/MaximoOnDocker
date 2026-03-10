#!/bin/bash
# export AWS_ACCESS_KEY_ID=000000000000 AWS_SECRET_ACCESS_KEY=000000000000

# version free ne porte pas la capacité de persistance, il faut donc recréer le bucket à chaque démarrage
awslocal s3 mb s3://my-bucket

init_bucket_dir=/var/lib/localstack/tmp/init-my-bucket

# Utiliser find et awk pour générer les commandes d'upload
find "$init_bucket_dir" -type f | awk -v init_bucket_dir="$init_bucket_dir" '{
    filename = substr($0, length(init_bucket_dir) + 2);
    print "Uploading \"" $0 "\" to s3://my-bucket/" filename;
    cmd = "awslocal s3 cp \"" $0 "\" \"s3://my-bucket/" filename "\"";
    system(cmd);
}'
