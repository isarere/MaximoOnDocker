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