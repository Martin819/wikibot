#!/bin/bash

WIKIAPIURL="https://cs.wikipedia.org/w/api.php"
WIKIURL="https://cs.wikipedia.org/wiki/"
ENABLE="true"
TESTPAGE="Wikipedista:Martin819/Pískoviště"
STAGEDTEXT=""
USERNAMEPATH="config/username"
PASSWORDPATH="config/password"
USERNAME="NotProvided"
PASSWORD="NotProvided"
LOGINTOKEN="NotProvided"
DEBUG="true"
VERBOSE="false"
QUIET="false"
TEST="false"

for i in "$@"
do
case $i in
    -c=*|--content=*)
    CONTENT="${i#*=}"
    shift # past argument=value
    ;;
    -t=*|--title=*)
    TITLE="${i#*=}"
    shift # past argument=value
    ;;
    --test)
    TEST="true"
    shift # past argument with no value
    ;;
    --verbose)
    VERBOSE="true"
    shift # past argument with no value
    ;;
    *)
          # unknown option
    ;;
esac
done

echo "CONTENT: $CONTENT"
echo "TITLE: $TITLE"
echo "TEST: $TEST"
echo "VERBOSE: $VERBOSE"

info() {
	if [ $QUIET != "true" ]; then
		echo "[INFO   ] $1"
	fi
}

verbose() {
	if [ $VERBOSE == "true" ]; then
		echo "[VERBOSE] $1"
	fi
}

debug() {
	if [ $DEBUG == "true" ]; then
		echo "[ DEBUG ] $1"
	fi
}

warning() {
	echo "[WARNING] $1"
}

error() {
	echo "[  ERROR] $1"
	exit 1
}

show_help() {
    echo "help"
}

rawurlencode() {
	ENCODED="${1//\&/\%26}" #replace ampersand with %26
	echo "${ENCODED}"
}

getlogintoken() {
    TOKENREQUEST=$(curl -S \
			--location \
			--retry 2 \
			--retry-delay 5\
			--cookie $cj \
			--cookie-jar $cj \
			--user-agent "pubchem.sh by Martin819" \
			--keepalive-time 60 \
			--header "Accept-Language: en-us" \
			--header "Connection: keep-alive" \
			--compressed \
			--request "GET" "${WIKIAPIURL}?action=query&meta=tokens&type=login&format=json")

    echo "$TOKENREQUEST" | jq .
        
    rm tokenrequest.json 2>/dev/null
    echo "$TOKENREQUEST" > data/tokenrequest.json
    LOGINTOKEN=$(jq --raw-output '.query.tokens.logintoken' data/tokenrequest.json)
    LOGINTOKEN="${LOGINTOKEN//\"/}" #replace double quote with nothing

    #Remove carriage return!
    printf "%s" "$LOGINTOKEN" > data/logintoken.txt
    LOGINTOKEN=$(cat data/logintoken.txt | sed 's/\r$//')

    if [ "$LOGINTOKEN" == "null" ]; then
        warning "Getting a login token failed. Retrying..."
        sleep 5
        continue
    else
        debug "Login token is $LOGINTOKEN"
        debug "-----"
    fi
}

login() {
	debug "Using user: ${USERNAME}:${PASSWORD}"
    	LOGINREQUEST=$(curl -S \
			--location \
			--cookie $cj \
			--cookie-jar $cj \
			--user-agent "pubchem.sh by Martin819" \
			--keepalive-time 60 \
			--header "Accept-Language: en-us" \
			--header "Connection: keep-alive" \
			--compressed \
			--data-urlencode "username=${USERNAME}" \
			--data-urlencode "password=${PASSWORD}" \
			--data-urlencode "rememberMe=1" \
			--data-urlencode "logintoken=${LOGINTOKEN}" \
			--data-urlencode "loginreturnurl=http://cs.wikipedia.org" \
			--request "POST" "${WIKIAPIURL}?action=clientlogin&format=json")

		echo "$LOGINREQUEST" | jq .

		STATUS=$(echo $LOGINREQUEST | jq '.clientlogin.status')
		if [[ $STATUS == *"PASS"* ]]; then
			info "Successfully logged in as $USERNAME, STATUS is $STATUS."
			info "-----"
		else
			error "Unable to login, is login token ${LOGINTOKEN} correct?"
			exit
		fi
}

getedittoken() {
		debug "Requesting edit token"
    	EDITTOKENREQUEST=$(curl -S \
			--location \
			--cookie $cj \
			--cookie-jar $cj \
			--user-agent "nocat.sh by Smile4ever" \
			--keepalive-time 60 \
			--header "Accept-Language: en-us" \
			--header "Connection: keep-alive" \
			--compressed \
			--request "POST" "${WIKIAPIURL}?action=query&meta=tokens&format=json")
		debug "Call output: ${EDITTOKENREQUEST}"
		echo "$EDITTOKENREQUEST" | jq .
		echo "$EDITTOKENREQUEST" > data/edittokenrequest.json
		EDITTOKEN=$(jq --raw-output '.query.tokens.csrftoken' data/edittokenrequest.json)
		rm data/edittokenrequest.json

		EDITTOKEN="${EDITTOKEN//\"/}" #replace double quote with nothing

		#Remove carriage return!
		printf "%s" "$EDITTOKEN" > data/edittokenrequest.txt
		EDITTOKEN=$(cat data/edittokenrequest.txt | sed 's/\r$//')

		if [[ $EDITTOKEN == *"+\\"* ]]; then
			debug "Edit token is: $EDITTOKEN"
		else
			error "Edit token not set."
			error "EDITTOKEN was {EDITTOKEN}"
		fi
}

editpage() {
	info "Uploading edit to page $1"
	debug "Using token ${EDITTOKEN}"
	#debug "Text to be pushed: $(cat data/stagedtext.txt)"
	EDITREQUEST=$(curl -S \
			--location \
			--cookie $cj \
			--cookie-jar $cj \
			--user-agent "pubchem.sh by Martin819" \
			--keepalive-time 60 \
			--header "Accept-Language: en-us" \
			--header "Connection: keep-alive" \
			--compressed \
			--data-urlencode "title=${1}" \
			--data-urlencode "nocreate=true" \
			--data-urlencode "summary=Nahrada symbolu nebezpeci za GHS a standardizace infoboxu." \
			--data-urlencode "text=$(cat ${CONTENT})" \
			--data-urlencode "token=${EDITTOKEN}" \
			--request "POST" "${WIKIAPIURL}?action=edit&format=json")
	debug "Request response: $EDITREQUEST"
}

commentCat() {
	debug "Commenting categories"
	perl -pi -e "s/\[\[Kategorie.+(?=\]\])/\[\[nocat/g" $1
}

mkdir config 2>/dev/null

if [[ ! -f "$USERNAMEPATH" ]]; then
    # First run
    read -p "Username: " inputusername
    echo -n "$inputusername" > "${USERNAMEPATH}"
    read -p "Password: " inputpassword
    openssl enc -base64 <<< "$inputpassword" | tr -d '\n' | tr -d '\r' > "${PASSWORDPATH}"
fi

USERNAME=$(cat ${USERNAMEPATH})
PASSWORD=$(cat ${PASSWORDPATH} | base64 --decode)
cj="data/wikicj"

if [[ $ENABLE == "true" ]]; then
    getlogintoken
    login
    getedittoken
fi

if [ $TEST = "true" ]; then
    commentCat $CONTENT
    editpage $TESTPAGE
else
    editpage $TITLE
fi