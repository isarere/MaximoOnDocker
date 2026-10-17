#!/bin/bash


echo "Processing all product files"
currentworkdir=$(pwd)
cd /opt/IBM/SMP/maximo/tools/maximo/internal

for f in $(ls -1 /opt/IBM/SMP/maximo/applications/maximo/properties/product/*.xml)
do

    echo "Current file is $f"
    varname=$(sed -n -e 's/\s*<dbmaxvarname>\(.*\)<\/dbmaxvarname>/\1/p' $f | tr [:lower:] [:upper:] | tr -d [:space:])
    varvalue=$(sed -n -e 's/\s*<dbversion>\(.*\)<\/dbversion>/\1/p' $f | tr [:lower:] [:upper:] | tr -d [:space:])

    # Legacy Work Centers are not deployed by this standalone maximo-all bundle.
    if [[ "$varname" == "NXTGENUI" ]]; then
        continue
    fi

    # UpdateDBLite applies Manage's hotfix scripts through the core product and
    # leaves MANAGEUPG unchanged. Check the marker it actually updates instead.
    if [[ "$varname" == "MANAGEUPG" ]]; then
        varname=$(sed -n -e 's/\s*<hfdbmaxvarname>\(.*\)<\/hfdbmaxvarname>/\1/p' "$f" | tr [:lower:] [:upper:] | tr -d [:space:])
        varvalue=$(sed -n -e 's/\s*<hfdbversion>\(.*\)<\/hfdbversion>/\1/p' "$f" | tr [:lower:] [:upper:] | tr -d [:space:])
    fi

    if [[ ! "$varname" =~ ^[A-Z0-9_]+$ || ! "$varvalue" =~ ^[A-Z]+[0-9]+-[0-9]+$ ]]; then
        echo "Invalid database version metadata in $f."
        cd "$currentworkdir"
        exit 2
    fi
    version_number=$((10#${varvalue##*-}))
    # Zero-version placeholders have no database scripts for UpdateDBLite to run.
    if [[ "$version_number" == 0 ]]; then
        continue
    fi
    varvalue="${varvalue%-*}-$version_number"

    echo "Running query select count(*) from maxvars where upper(varname) = '$varname' and varvalue = '$varvalue'"
    querycount=$(/opt/IBM/SMP/maximo/tools/maximo/internal/querycount.sh -qcount -tmaxvars -w"upper(varname) = '$varname' and varvalue = '$varvalue'")
    querycount_res=$?
    
    # QueryCount can return zero even after a JDBC exception. Require an
    # explicit numeric result rather than treating an empty/error output as current.
    if [[ ${querycount_res} != 0 ]] || ! printf '%s\n' "$querycount" | grep -Eq '^(BMXAA9891I:)?count=[0-9]+$'; then
        echo "Unable to verify if updatedb is required."
        cd $currentworkdir
        exit 2
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
