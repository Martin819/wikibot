#!/bin/bash

WIKIAPIURL="https://cs.wikipedia.org/w/api.php"
WIKIURL="https://cs.wikipedia.org/wiki/"
ENABLE="true"
DEBUG="true"
VERBOSE="false"
QUIET="false"

BLACKLIST="Forfor fosfor 1-aminopropan-2-on"

USERNAMEPATH="config/username"
PASSWORDPATH="config/password"
USERNAME="NotProvided"
PASSWORD="NotProvided"
LOGINTOKEN="NotProvided"
LISTPAGELIMIT=50
LISTPAGECATEGORY="Kategorie%3A%C3%9Adr%C5%BEba%3A%C4%8Cl%C3%A1nky%20obsahuj%C3%ADc%C3%AD%20star%C3%A9%20symboly%20nebezpe%C4%8D%C3%AD"
LISTPAGEURL="${WIKIAPIURL}?action=query&format=json&list=categorymembers&cmtitle=${LISTPAGECATEGORY}&cmlimit=${LISTPAGELIMIT}"
LISTPAGEJSON="data/listpage.json"
PUBCHEMAPIURL="https://pubchem.ncbi.nlm.nih.gov/rest/"
PUBCHEMPUG="pug/compound/"
PUBCHEMPUGVIEW="pug_view/data/compound/"
PUBCHEMGHSPARAMS="JSON?heading=GHS+Classification"
STAGEDPAGES=[]
PAGETOUPLOAD="NotProvided"
TESTPAGE="Wikipedista:Martin819/Pískoviště"
DATEOFACCESS=$(date +%F)
STAGEDWIKITEXT=""
STAGEDTEXT=""
SMILES=""
CID=""
GHS=""
SYMBOLS=""
NEWSYMBOLS=""
CAS=""
REFERENCE=""
CNAME=""
GHSREQLINK=""
ORIGINALR=""
ORIGINALS=""
ORIGINALTITLE=""
ORIGINALVZHLED=""
ORIGINALSYSNAME=""
AUTOMATIC="false"
TEST="false"
GETLISTOFREPL="false"
RETRY="false"

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
	CAS=""
	REFERENCE=""
	CNAME=""
	GHSREQLINK=""
	ORIGINALR=""
	ORIGINALS=""
	ORIGINALTITLE=""
	ORIGINALVZHLED=""
	ORIGINALSYSNAME=""
}

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

mkdir config 2>/dev/null
mkdir data 2>/dev/null
touch data/failed
touch data/empty
touch data/successful
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
	verbose "Got response: $(cat $LISTPAGEJSON)"
}

parsecategorymemebers() {
	jq -r ".query.categorymembers[] | .title" $LISTPAGEJSON > $STAGEDPAGES
	debug "Found pages: $(cat ${STAGEDPAGES} | tr '\n' ' ')"
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
	verbose "Wikitext: ${STAGEDTEXT}"
	# debug "ASCII: $(cat data/stagedtextascii.txt)"
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
			--data-urlencode "title=$1" \
			--data-urlencode "nocreate=true" \
			--data-urlencode "summary=Nahrada symbolu nebezpeci za GHS a standardizace." \
			--data-urlencode "text=$(cat data/stagedtext.txt)" \
			--data-urlencode "token=${EDITTOKEN}" \
			--request "POST" "${WIKIAPIURL}?action=edit&format=json")
	debug "Request response: $EDITREQUEST"
}

getsmilesfromwiki() {
	SMILES=$(cat $1 | grep -oP '(?<=SMILES\s=\s)\S+')
	if [ "$SMILES" == "" ]; then
		SMILES=$(cat $1 | grep -oP '(?<=SMILES=)\S+')
	fi
	if [ $(echo $SMILES | grep -oP '<br>') ]; then
		SMILES=$(echo $SMILES | grep -oP '\S+(?=<br>)')
	fi
	if [ $(echo $SMILES | grep -oP '<br\>') ]; then
		SMILES=$(echo $SMILES | grep -oP '\S+(?=<br\>)')
	fi
	if [ $(echo $SMILES | grep -oP '<br \>') ]; then
		SMILES=$(echo $SMILES | grep -oP '\S+(?=<br \>)')
	fi
	if [ $(echo $SMILES | grep -oP '<br') ]; then
		SMILES=$(echo $SMILES | grep -oP '\S+(?=<br)')
	fi
	debug "Found SMILES: $SMILES"
}

getCASfromwiki() {
	CAS=$(cat $1 | grep -oP '(?<=číslo\sCAS\s=\s)\S+')
	if [ "$CAS" == "" ]; then
		CAS=$(cat $1 | grep -oP '(?<=číslo\sCAS=)\S+')
	fi
	debug "Found CAS: $CAS"
}

getCID() {
	getsmilesfromwiki $1
	if [ "$SMILES" != "" ]; then
		CID=$(wget -qO- "${PUBCHEMAPIURL}${PUBCHEMPUG}smiles/$SMILES/cids/TXT")
		debug "CID: $CID"
	else
		getCASfromwiki $1
		if [ "$CAS" != "" ]; then
			CID=$(wget -qO- "${PUBCHEMAPIURL}${PUBCHEMPUG}name/$CAS/cids/TXT")
			debug "CID: $CID"
		else
			CID=""
		fi
	fi

	# TODO: Add more ways to obtain CID
}


getGHSbyCID() {
	if [ "$CID" != "" ]; then
		GHSREQLINK="${PUBCHEMAPIURL}${PUBCHEMPUGVIEW}${CID}/${PUBCHEMGHSPARAMS}"
		debug "GHS request link: ${GHSREQLINK}"
		GHS=$(wget -qO- "${GHSREQLINK}")
		echo "$GHS" > data/ghs.json
#		debug "GHS: $GHS" 
	fi
}

getSymbolsbyGHS() {
	if [ "GHS" != "" ]; then
		SYMBOLS=$(jq --raw-output ".Record.Section[].Section[].Section[].Information[].Value.StringWithMarkup[].Markup[].Extra" data/ghs.json)
		info "SYMBOLS: $SYMBOLS"
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
			"Acute Toxic" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS06}}" ;;
			"Irritant" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS07}}" ;;
			"Health Hazard" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS08}}" ;;
			"Environmental Hazard" )
				NEWSYMBOLS=${NEWSYMBOLS}"{{GHS09}}" ;;
			*)
				warning "Found unknown Symbol: $SYMBOL."
		esac
	done
	info "New symbols to be placed: ${NEWSYMBOLS}"
}

getEnglishCompoundNameFromPubChem() {
	if [ "GHS" != "" ]; then
		CNAME=$(jq --raw-output ".Record.RecordTitle" data/ghs.json)
		debug "COMPOUND NAME: $CNAME"
	fi
}

addReference() {
	debug "Adding reference"
	getEnglishCompoundNameFromPubChem
	DATEOFACCESS=$(date +%F)
	REFERENCE="<ref name=pubchem_cid_${CID}>{{Citace elektronického periodika \| titul = ${CNAME} \| periodikum = pubchem.ncbi.nlm.nih.gov \| vydavatel = PubChem \| url = https:\/\/pubchem.ncbi.nlm.nih.gov\/compound\/${CID} \| jazyk = en \| datum přístupu = 2020-01-20 }}<\/ref>"
}

removeGHSSymbols() {
	debug "Removing any already present GHS symbols"
	perl -pi -e 's/symboly\snebezpečí\s?GHS\s?=\s?(?=\n)/SYMBOLS_TO_REPLACE/g' $1
}

removeOldSymbols() {
	debug "Removing old symbols"
	if  grep "SYMBOLS_TO_REPLACE" $1; then
		perl -pi -e 's/symboly\snebezpečí\s?=\s?(?=\n)/symboly nebezpečí =/g' $1
	else
		perl -pi -e 's/symboly\snebezpečí\s?=\s?(?=\n)/SYMBOLS_TO_REPLACE/g' $1
	fi
}

placeNewSymbols() {
	debug "Placing new symbols"
	if  grep "SYMBOLS_TO_REPLACE" $1; then
		addReference
		perl -pi -e "s/SYMBOLS_TO_REPLACE/symboly nebezpečí GHS = ${NEWSYMBOLS}${REFERENCE}/g" $1
	elif [ $(grep -P 'R-věty\s?=' $1) ]; then
		addReference
		ORIGINALR="$(grep -P 'R=věty\s?=' $1)"
		debug "Original R: $ORIGINALR"
		perl -pi -e "s/R=věty\s?=.*(?=\n)/symboly nebezpečí GHS = ${NEWSYMBOLS}${REFERENCE}
${ORIGINALR}/g" $1
	elif [ $(grep -P 'S-věty\s?=' $1) ]; then
		addReference
		ORIGINALS="$(grep -P 'S=věty\s?=' $1)"
		debug "Original S: $ORIGINALS"
		perl -pi -e "s/S=věty\s?=.*(?=\n)/symboly nebezpečí GHS = ${NEWSYMBOLS}${REFERENCE}
${ORIGINALS}/g" $1
	#elif [ $(grep -P '' $1) ]; then
	elif [ $(grep -P 'SMILES\s?=' $1) ]; then
		addReference
		ORIGINALTITLE="$(grep -P 'SMILES\s?=' $1)"
		debug "Original title: $ORIGINALTITLE"
		perl -pi -e "s/SMILES\s?=.*(?=\n)/symboly nebezpečí GHS = ${NEWSYMBOLS}${REFERENCE}
${ORIGINALTITLE}/g" $1
	elif [ $(grep -P 'vzhled\s?=' $1) ]; then
		addReference
		ORIGINALVZHLED="$(grep -P 'vzhled\s?=' $1)"
		debug "Original vzhled: $ORIGINALVZHLED"
		perl -pi -e "s/vzhled\s?=.*(?=\n)/symboly nebezpečí GHS = ${NEWSYMBOLS}${REFERENCE}
${ORIGINALVZHLED}/g" $1
	elif [ $(grep -P 'systematický\snázev\s?=' $1) ]; then
		addReference
		ORIGINALSYSNAME="$(grep -P 'systematický\snázev\s?=' $1)"
		debug "Original sysname: $ORIGINALSYSNAME"
		perl -pi -e "s/systematický\snázev\s?=.*(?=\n)/symboly nebezpečí GHS = ${NEWSYMBOLS}${REFERENCE}
${ORIGINALSYSNAME}/g" $1
# 	else
# 		addReference
# 		ORIGINALTITLE=$(grep -Pzao "\|([^\|][\s\S])+?(?=}})" $1)
# 		#ORIGINALTITLE=$(awk "/\}\}\[\\s\\S\]\+\?\(\?=\\'\{3\}\)/")
# 		debug "ORIGINAL TITLE: ${ORIGINALTITLE}"
# 		#PERL=$(perl -0pi -e "s/}}[\s\S]+?(?=\'{3})/BLAHBLAH/" $1)
# 		#echo "PERL: $PERL"
# 		perl -0pi -e "s/}}[\s\S]+?(?=\'{3})/| symboly nebezpečí GHS = ${NEWSYMBOLS}${REFERENCE}
# ${ORIGINALTITLE}/g" $1
# 		debug "Replaced done"
	fi
}

commentCat() {
	debug "Commenting categories"
	perl -pi -e "s/\[\[Kategorie.+(?=\]\])/\[\[nocat/g" $1
}

if [[ $ENABLE == "true" ]]; then
    getlogintoken
    login
    getedittoken
fi

getcategorymembers $LISTPAGEURL

IFS=$'\n'
if [ $GETLISTOFREPL = "true" ]; then
	touch data/blah.txt
	for PAGE in $(cat $STAGEDPAGES | tr -d '\r' | tr ' ' '_')
	#for PAGE in "arsenitan_sodný"
	do
		getpagewikitext $PAGE
		BLAH=$(grep -1 "symboly" data/stagedtext.txt)
		echo "$PAGE" >> data/blah.txt
		echo "$BLAH" >> data/blah.txt
		echo "------------" >> data/blah.txt
		cleanstaged
	done
fi

for PAGE in $(cat $STAGEDPAGES | tr -d '\r')
#for PAGE in "1-aminopropan-2-on"
do
	if [[ ! $BLACKLIST =~ (^| )$x($| ) ]]; then
		getpagewikitext $PAGE
		if [ "$STAGEDTEXT" != "" ]; then
			getCID data/stagedtext.txt
			if [ ! $(grep '<ref name=pubchem_cid_' data/stagedtext.txt) ]; then
				if [ "$CID" != "" ]; then
					getGHSbyCID $CID
					getEnglishCompoundNameFromPubChem
					info "Identified as: $CNAME"
					getSymbolsbyGHS $GHS
					determineNewSymbols
					debug "length: ${#NEWSYMBOLS}"
					if (( ${#NEWSYMBOLS} > 0 )); then
						removeGHSSymbols data/stagedtext.txt
						removeOldSymbols data/stagedtext.txt
						placeNewSymbols data/stagedtext.txt
						verbose $(cat data/stagedtext.txt)
						if [ $TEST = "true" ]; then
							commentCat data/stagedtext.txt
							editpage $TESTPAGE
							echo "$PAGE | https://pubchem.ncbi.nlm.nih.gov/compound/$CID" >> data/successful
							echo "$EDITREQUEST" >> data/successful
						else
							editpage $PAGE
							echo "$PAGE | https://pubchem.ncbi.nlm.nih.gov/compound/$CID" >> data/successful
							echo "$EDITREQUEST" >> data/successful
						fi
						if [ $AUTOMATIC != "true" ]; then
							read -n 1 -s -r -p "Press any key to continue"
						fi
					else
						warning "No new symbols. New symbols: $NEWSYMBOLS"
						echo "$PAGE | https://pubchem.ncbi.nlm.nih.gov/compound/$CID" >> data/empty
					fi
				else
					warning "Not possible to get CID for SMILES: $SMILES or CAS: $CAS"
					echo $PAGE >> data/failed
				fi
			else
				info "Skipping $PAGE because it's been already fixed before"
			fi
			cleanstaged
		fi
	else
		info "Skipped $PAGE because it's blacklisted"
		cleanstaged
	fi
	info "====DONE===="
done