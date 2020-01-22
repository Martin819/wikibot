#!/bin/bash

WIKIAPIURL="https://cs.wikipedia.org/w/api.php"
WIKIURL="https://cs.wikipedia.org/wiki/"
ENABLE="true"
DEBUG="false"
QUIET="false"

USERNAMEPATH="config/username"
PASSWORDPATH="config/password"
USERNAME="NotProvided"
PASSWORD="NotProvided"
LOGINTOKEN="NotProvided"
LISTPAGELIMIT=500
LISTPAGECATEGORY="Kategorie%3A%C3%9Adr%C5%BEba%3A%C4%8Cl%C3%A1nky%20obsahuj%C3%ADc%C3%AD%20star%C3%A9%20symboly%20nebezpe%C4%8D%C3%AD"
LISTPAGEURL="${WIKIAPIURL}?action=query&format=json&list=categorymembers&cmtitle=${LISTPAGECATEGORY}&cmlimit=${LISTPAGELIMIT}"
LISTPAGEJSON="data/listpage.json"
PUBCHEMAPIURL="https://pubchem.ncbi.nlm.nih.gov/rest/"
PUBCHEMPUG="pug/compound/"
PUBCHEMPUGVIEW="pug_view/data/compound/"
PUBCHEMGHSPARAMS="/JSON?heading=GHS+Classification"
STAGEDPAGES=[]
PAGETOUPLOAD="NotProvided"
TESTPAGE="Wikipedista:Martin819/Pískoviště"
STAGEDWIKITEXT=""
STAGEDTEXT=""
SMILES=""
CID=""
GHS=""
SYMBOLS=""
NEWSYMBOLS=""
TEST="false"

#declare -A STAGEDPAGESARR

cleanstaged() {
	rm -f data/wikitextrequest.json 2>/dev/null
	rm -f data/stagedtext.txt 2>/dev/null
	rm -f data/ghs.json 2>/dev/null
	STAGEDTEXT=""
	SMILES=""
	CID=""
	GHS=""
	SYMBOLS=""
	NEWSYMBOLS=""
}

info() {
	if [ QUIET != "true" ]; then
		echo "[INFO   ] $1"
	fi
}

debug() {
	if [ DEBUG="true" ]; then
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

mkdir config 2>/dev/null
mkdir data 2>/dev/null
cleanstaged

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
	debug "Using user: ${USERNAME}"
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

getcategorymembers() {
	fetchwikilistpages $1
	parsecategorymemebers
}

fetchwikilistpages() {
	info "-----"
	info "Requesting list of pages from ${1}"
    wget "${1}" -T 60 -O $LISTPAGEJSON >/dev/null 2>&1
	debug "Got response: $(cat $LISTPAGEJSON)"
}

parsecategorymemebers() {
	jq -r ".query.categorymembers[] | .title" $LISTPAGEJSON > $STAGEDPAGES
	info "Found pages: $(cat ${STAGEDPAGES})"
}

getpagewikitext() {
	info "Requesting wikipage: ${WIKIURL}${1}"
    WIKITEXTREQUEST=$(curl -S \
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
			--request "GET" "${WIKIAPIURL}?action=parse&page=${1}&prop=wikitext&format=json&ascii=1")
	echo "${WIKITEXTREQUEST}" > data/wikitextrequest.json
	STAGEDTEXT=$(jq --raw-output '.parse.wikitext[]' data/wikitextrequest.json)
	echo "$STAGEDTEXT" > data/stagedtext.txt
	# iconv -f utf-8 -t ASCII//TRANSLIT data/stagedtext.txt data/stagedtextascii.txt
	debug "Wikitext: ${STAGEDTEXT}"
	# debug "ASCII: $(cat data/stagedtextascii.txt)"
}

editpage() {
	info "Uploading edit to page $1"
	debug "Using token ${EDITTOKEN}"
	EDITREQUEST=$(curl -S \
			--location \
			--cookie $cj \
			--cookie-jar $cj \
			--user-agent "pubchem.sh by Martin819" \
			--keepalive-time 60 \
			--header "Accept-Language: en-us" \
			--header "Connection: keep-alive" \
			--compressed \
			--data-urlencode "title=$1" \
			--data-urlencode "nocreate=true" \
			--data-urlencode "summary=Nahrada symbolu nebezpeci za GHS" \
			--data-urlencode "text=$(cat data/stagedtext.txt)" \
			--data-urlencode "token=${EDITTOKEN}" \
			--request "POST" "${WIKIAPIURL}?action=edit&format=json")
	debug "Request response: $EDITREQUEST"
}

getsmilesfromwiki() {
	SMILES=$(cat $1 | grep -oP '(?<=SMILES\s=\s)\S+')
	debug " Found SMILES: $SMILES"
}

getCIDbysmiles() {
	getsmilesfromwiki $1
	if [ SMILES != "" ]; then
		CID=$(wget -qO- "${PUBCHEMAPIURL}${PUBCHEMPUG}smiles/$SMILES/cids/TXT")
		debug "CID: $CID"
	fi
}

# TODO: Add more ways to obtain CID

getGHSbyCID() {
	if [ "$CID" != "" ]; then
		GHS=$(wget -qO- "${PUBCHEMAPIURL}${PUBCHEMPUGVIEW}${CID}/${PUBCHEMGHSPARAMS}")
		echo "$GHS" > data/ghs.json
		debug "GHS: $GHS" 
	fi
}

getSymbolsbyGHS() {
	if [ "GHS" != "" ]; then
		SYMBOLS=$(jq --raw-output ".Record.Section[].Section[].Section[].Information[].Value.StringWithMarkup[].Markup[].Extra" data/ghs.json)
		debug "SYMBOLS: $SYMBOLS"
	fi
}

determineNewSymbols() {
	for SYMBOL in $SYMBOLS
	do
		case $SYMBOL in
			"Explosive" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS01}}" ;;
			"Flammable" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS02}}" ;;
			"Oxidizing" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS03}}" ;;
			"Compressed Gas" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS04}}" ;;
			"Corrosive" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS05}}" ;;
			"Toxic" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS06}}" ;;
			"Harmful" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS07}}" ;;
			"Health hazard" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS08}}" ;;
			"Environmental hazard" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS09}}" ;;
		esac
	done
	info "Found new symbols to be places: ${NEWSYMBOLS}"
}

removeOldSymbols() {
	perl -pi -e 's/symboly\snebezpečí\s=\s\S+(?=\n)/SYMBOLS_TO_REPLACE/g' $1
}

placeNewSymbols() {
	perl -pi -e "s/SYMBOLS_TO_REPLACE/symboly nebezpečí GHS = ${NEWSYMBOLS}/g" $1
}

if [[ $ENABLE == "true" ]]; then
    getlogintoken
    login
    getedittoken
fi

getcategorymembers $LISTPAGEURL

IFS=$'\n'
for PAGE in $(cat $STAGEDPAGES | tr -d '\r')
do

	getpagewikitext $PAGE
	if [ "$STAGEDTEXT" != "" ]; then
		getCIDbysmiles data/stagedtext.txt
		getGHSbyCID $CID
		getSymbolsbyGHS $GHS
		determineNewSymbols
		if [ ${#NEWSYMBOLS} > 0 ]; then
			removeOldSymbols data/stagedtext.txt
			placeNewSymbols data/stagedtext.txt
			if [ $TEST = "true" ]; then
				editpage $TESTPAGE
			else
				editpage $PAGE
			fi
		fi
		cleanstaged
	fi

done