#!/bin/bash
install customized SMP Maximo product extensions
custmo_archive_dir="/config/customization_archives"
if [ -d "$custmo_archive_dir" ] && [ "$(ls -A $custmo_archive_dir)" ]; then
    cd /opt/IBM/SMP/maximo
    echo "Found customization archive files in $custmo_archive_dir"
    for f in $custmo_archive_dir/*.zip; do
        if [ -f "$f" ]; then
            echo "Installing customization archive file: $f"
            /opt/IBM/SMP/maximo/tools/java/bin/jar -vxf "$f" 
        fi
    done
else
    echo "No customization archive files found in $custmo_archive_dir"
fi

cp -Rf /opt/IBM/SMP/maximo/applications/maximo/businessobjects/classes/* /config/apps/maximo-all.ear/businessobjects.jar/
cp -Rf /opt/IBM/SMP/maximo/applications/maximo/maximouiweb/webmodule/WEB-INF/classes/* /config/apps/maximo-all.ear/maximouiweb.war/WEB-INF/classes/
# conf mdb
if [ -d "/opt/IBM/SMP/maximo/deployment/was-liberty-default/config-deployment-descriptors/maximo-all/mboejb/ejbmodule/META-INF" ]; then
    cp /opt/IBM/SMP/maximo/deployment/was-liberty-default/config-deployment-descriptors/maximo-all/mboejb/ejbmodule/META-INF/*.xml /opt/ibm/wlp/usr/servers/defaultServer/apps/maximo-all.ear/mboejb.jar/META-INF/ || echo "Warning: Failed to copy some META-INF files" >&2
fi

echo "import certs"
certificatmgr_dir="/config/certificatmgr"
truststore_path="/config/trust.p12"
for file in "$certificatmgr_dir"/*.crt; do
    alias=$(basename "$file" .crt)

    if keytool -list -alias "$alias" \
        -keystore $truststore_path \
        -storepass $OSM_TRUSTSTORE_PASSWORD >/dev/null 2>&1; then
        
        echo "Skipping $alias (already in truststore)"
    else
        echo "Importing $alias"
        keytool -importcert \
            -file "$file" \
            -alias "$alias" \
            -keystore $truststore_path \
            -storetype PKCS12 \
            -storepass $OSM_TRUSTSTORE_PASSWORD \
            -noprompt
        echo "$alias imported"
    fi
done


echo "Processing all product files"
currentworkdir=$(pwd)
cd /opt/IBM/SMP/maximo/tools/maximo/internal

for f in $(ls -1 /opt/IBM/SMP/maximo/applications/maximo/properties/product/*.xml)
do

    echo "Current file is $f"
    varname=$(sed -n -e 's/\s*<dbmaxvarname>\(.*\)<\/dbmaxvarname>/\1/p' $f | tr [:lower:] [:upper:] | tr -d [:space:])
    varvalue=$(sed -n -e 's/\s*<dbversion>\(.*\)<\/dbversion>/\1/p' $f | tr [:lower:] [:upper:] | tr -d [:space:])

    varvalue=(${varvalue//-/ })
    if [[ ${varvalue[1]} < 10 ]]; then 
        varvalue=${varvalue[0]}-${varvalue[1]:1}
    else 
        varvalue=${varvalue[0]}-${varvalue[1]}
    fi

    echo "Running query select count(*) from maxvars where upper(varname) = '$varname' and varvalue = '$varvalue'"
    querycount=$(/opt/IBM/SMP/maximo/tools/maximo/internal/querycount.sh -qcount -tmaxvars -w"upper(varname) = '$varname' and varvalue = '$varvalue'")
    querycount_res=$?
    
    if [[ ${querycount_res} == 1 ]]; then
        echo "Unable to verify if updatedb is required."
        echo "Continuing..."
        cd $currentworkdir
        exit 0
    else
        if [[ "${querycount}" == *"count=0"* ]]; then
            echo "$varname needs to be updated"
            cd $currentworkdir
            exit 1
        fi
    fi
done

cd $currentworkdir
exit 0