#!/bin/bash

# USAGE
function usage {
        echo "  Usage: ./report.sh [OPTIONS...]"
        echo "  #depricated# -p, --product       Name of Product report (Default = sentrex)"
        echo "  #depricated# -r, --report        Name of desired Sentry report (Default = claim)"
        echo "  -c, --contracts     File containing a comma separated list of contract_ids"
        echo "  -ds and -de         Request a custom date range (MM/DD/YYYY) other than the previous day"
        echo "  -o, --output        Declare report output type ('csv','xls','psv','json'; Default = psv)"
        echo "  -h, --help          This usage information"
        echo "  --debug             Debugging purposes, will output query without submitting to sentry"
        exit
}

# INITIAL SETUP
DEBUGGING=false
FOLDER="/home/dom/sentrex"
ATTEMPTS=0
# API SETUP
URL='https://secure.sentryds.com/api/reporter/'
USER_ID=$(<./userid)
API_KEY=$(<./api)
PRODUCT='sentrex'
REPORT='claim'
OUTPUT='psv'

# CHECK FOR INPUT ARGUMENTS
while [ "$1" != "" ]; do
	case $1 in
		--debug )		DEBUGGING=true
					;;
		-c | --contracts )	shift
					CONTRACT=$1
					CONTRACT_IDS=$(<$FOLDER/$CONTRACT)
					;;
		-d | --date )
					read -p "Start date (MM/DD/YYYY): " STARTDATE
					read -p "End date   (MM/DD/YYYY): " ENDDATE
					;;
		-ds )			shift
					STARTDATE=$1
					;;
		-de )			shift
					ENDDATE=$1
					;;
		-o | --output )		shift
					OUTPUT=$1
					;;
		-h | -u | --help | --usage ) usage
					exit
					;;
		* )			usage
					exit 1
	esac
	shift
done

# CALCULATE DATES
if [ -z $STARTDATE ]
then
	# always default to yesterday if no date was specified, report now runs daily
	STARTDATE=$( date --date="yesterday" +%Y/%m/%d )
	ENDDATE=$STARTDATE
fi

# BUILD QUERY
QUERYSTRING="product=${PRODUCT}&report=${REPORT}&output=${OUTPUT}&columns=note"
QUERYSTRING+="&start_date=${STARTDATE}&end_date=${ENDDATE}"
if [ ! -z $CONTRACT_IDS ] ## if a contract pharmacy was specified, add it to the query
then
	QUERYSTRING+="&contract_ids=${CONTRACT_IDS}"
fi
QUERYSTRING+="&user_id=${USER_ID}"

# HASH THE QUERY FOR TRANSMISSION
HASHING=`echo -n "${QUERYSTRING}&key=${API_KEY}" | md5sum` # echo to md5sum gives the correct value instead of calling md5sum as a command
HASH="${HASHING:0:32}" # but we have to strip off the extra characters when using the echo method

# DESIRED NAMING CONVENTION = {YYYYMMDD}_sentrex.{extension}
FILENAME="${FOLDER}/results/${STARTDATE//[\/]/}_${PRODUCT}.${OUTPUT}"

# EXECUTION or DEBUGGING
if [ $DEBUGGING = true ]
then
	echo `date`
	printf "Query: ${QUERYSTRING}&key=${API_KEY}"
	printf "curl command:\ncurl $URL -v -o $FILENAME -d \"${QUERYSTRING}&hash=${HASH}\""
	printf "\nUser ID: ${USER_ID} | API: ${API_KEY}\nHash: ${HASH}\nFilename: ${FILENAME}\n"
else
	# EXECUTE CURL
	echo `date` > ${FILENAME}.log
	echo "curling $URL -s -o $FILENAME -d \"${QUERYSTRING}&hash=${HASH}\"" >> ${FILENAME}.log
	curl $URL -o $FILENAME -d "${QUERYSTRING}&hash=${HASH}"

	# Check file size, API error is only 8KB, proper results >1MB
	FSIZE=$(stat -c %s $FILENAME)
	while [ $FSIZE -lt 10000 ] && [ $ATTEMPTS -lt 3 ];
	do
		echo `date` >> ${FILENAME}.log
		echo 'File returned is ${FSIZE}, must be API error message' >> ${FILENAME}.log
		# sleep 5 minutes and try again
		sleep 300
		ATTEMPTS=$(( $ATTEMPTS + 1 ))
		curl $URL -o $FILENAME -d "${QUERYSTRING}&hash=${HASH}"
		FSIZE=$(stat -c %s $FILENAME)
	done
	if [ $FSIZE -gt 10000 ]
	then
		# If after 4 attempts the file looks good, copy it to box for transfer
		cp $FILENAME /mnt/c/Users/Dom/Box\ Sync/sentry/.
		echo `date` >> ${FILENAME}.log
		echo "${ATTEMPTS} Reattempts" >> ${FILENAME}.log
	else
		# Gave up after 4 trys, touch an empty file just to get my attention to try and re-run before improt
		echo "file too small after ${ATTEMPTS} attempts" >> ${FILENAME}.log
		touch /mnt/c/Users/Dom/Box\ Sync/sentry/FAILED
	fi
fi
