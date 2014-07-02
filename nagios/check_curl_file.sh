#!/bin/sh

# This probe is made to check webDAV write and read. It checks the checksum of the file
# that was written, then read and only then it return with a success.
#
# To integrate this probe into nagios please define the command as follows in the command.cfg:
#    define command{
#       command_name check_curl_read_write
#       command_line /usr/lib64/nagios/plugins/check_curl_file.sh $ARG1$
#    }
#
# Further you have to define a service and bind it to a host:
#     define service{
#           use                             remote-service-cloud
#           host_name                       cloud.dcache.org
#           service_description             curl write and read
#           check_command                   check_curl_read_write! curlCheckFileWriteRead
#           }

DEBUG=0 # 0 for off, 1 for on

NAGIOS_RETURN_OK=0;
NAGIOS_RETURN_WARNING=1;
NAGIOS_RETURN_CRITICAL=2;
NAGIOS_RETURN_UNKNOWN=3;

WebDavEndpoint=https://cloud.dcache.org
CA_Cert_File=/etc/grid-security/cacert_bundle.pem
Prefix="/tmp"
File_Size=10485760
File_MB=$(expr 10485760 / 1024 / 1024)
FileName="testFile_$File_MB"
File="$Prefix/$FileName"
Return_File="$Prefix/$FileName.back"

UserName=""
Passwd=""

usage()
{
echo "Usage: $(basename $0) [OPTION]... COMMAND"
    echo
    echo "Valid commands are:"
    echo " curlCheckFileWriteRead"
} 1>&2

cleanUp()
 {
    result="$(curl -i -u $UserName:$Passwd -X DELETE $WebDavEndpoint/$FileName --cacert $CA_Cert_File 2>&1)"
    if [ -f $Return_File ]; then
        rm $Return_File;
    fi
    if [ -f $File ]; then
        rm $File;
    fi
}

call_curlCheckFileWriteRead()
{
    if [ ! DEBUG ]; then
    echo "Creating file $File"
    fi

    dd if=/dev/zero of=$File bs=$File_Size count=1 &> /dev/null

    if [ $? != 0 ]; then
        echo -e "CRITICAL: File creation failed\n" 1>&2
        exit $NAGIOS_RETURN_CRITICAL;
    fi

    if [ ! DEBUG ]; then
        echo "Writing file to WebDAV endpoint"
    fi

    exec 3>&1

    result="$(curl -i -u $UserName:$Passwd -X DELETE $WebDavEndpoint/$FileName --cacert $CA_Cert_File 2>&1)"
    if [ $? != 0 ]; then
        echo -e "CRITICAL: WebDAV DELETE not working:\n $result"
        exit $NAGIOS_RETURN_CRITICAL;
    fi
    result="$(/usr/bin/curl --fail -u $UserName:$Passwd -T $File $WebDavEndpoint --cacert $CA_Cert_File 2>&1)"
    if [ $? != 0 ]; then
        echo -e "CRITICAL: WebDAV write not working:\n $result"
        exit $NAGIOS_RETURN_CRITICAL;
    fi

    if [ ! DEBUG ]; then
        echo "Reading file: $WebDavEndpoint/$File from WebDAV endpoint"
    fi

    result="$(/usr/bin/curl --fail -u $UserName:$Passwd $WebDavEndpoint/$FileName --cacert $CA_Cert_File -o $Return_File 2>&1)"
    if [ $? != 0 ]; then
        echo -e "CRITICAL: WebDAV read not working\n $result" 1>&2
        exit $NAGIOS_RETURN_CRITICAL;
    fi

    md5_1=$(md5sum $File | awk '{print $1}')
    md5_2=$(md5sum $Return_File | awk '{print $1}')

    if [ ! DEBUG ]; then
        echo "Comparing md5 sums of $File and $Return_File"
        echo "    Sum of $File:\t$md5_1"
        echo "    Sum of $Return_File:\t$md5_2"
    fi

    cleanUp;
    [ "$md5_1" != "$md5_2" ] &&
    {
        echo "MD5 doesn't match";
        exit $NAGIOS_RETURN_CRITICAL;
    }

    echo -e "OK: WebDAV curl read/write working fine.\n"
    exit $NAGIOS_RETURN_OK
}

case "$1" in
    curlCheckFileWriteRead)
        shift
        call_curlCheckFileWriteRead
        ;;
    *)
        usage
        ;;
esac
