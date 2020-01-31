import wptools
import pywikibot
import os
import json
import requests
import urllib
from urllib.error import HTTPError
#import urllib.parse
import pyjq
import re
import regex
import shutil
from shutil import copyfile
from pathlib import Path
from collections import OrderedDict
import subprocess
import ast
import mwparserfromhell
from pywikibot import textlib
from datetime import date

templateToFind = 'Infobox - chemická sloučenina'

cswp = pywikibot.Site('cs','wikipedia')
members = []
cid = 0
dataDirName = './data'
categoryName = 'Kategorie:Údržba:Články obsahující staré symboly nebezpečí'
pubChemAPIurl = 'https://pubchem.ncbi.nlm.nih.gov/rest/'
pubChemAPIpug = 'pug/compound/'
pubChemAPIpugView = 'pug_view/data/compound/'
pubChemGHSparams = 'JSON?heading=GHS+Classification'
blacklist = []
ghsTitle = ""
testPush = True
automaticPush = False
automaticRun = True
debug = False
quiet = False

def debug(text):
    global debug
    if debug == True:
        print("[ DEBUG ] " + text)

def info(text):
    global quiet
    if quiet != True:
        print("[INFO   ] " + text)

def warning(text):
    print("[WARNING] " + text)

def cleanStaged(path):
    global cid
    cid = 0
    shutil.rmtree(path, ignore_errors=True)

def createDirectory(path):
    try:
        os.mkdir(path)
        info("Directory " + path + " Created ") 
    except FileExistsError:
        info("Directory " + path + " already exists")

def getCategoryMembers(name):
    global members
    cat = wptools.category(name)
    cat.get_members()
    members = cat.data['members']

def trimLineEnd(data):
    return re.sub('\r?\n', '', str(data))

def trimEscapedChars(data):
    data = data.replace('\\\\', '\\')
    data = data.replace('\\\'', '\'')
    return data
    #return data.replace('\\\\', '\\', str(data.replace('\\\'', '\'', str(data))))

def trimInfobox(infobox):
    for item in infobox:
        item.value = trimLineEnd(str(item.value))
        item.name = trimLineEnd(str(item.name))
        item.value = trimEscapedChars(str(item.value))
        item.name = trimEscapedChars(str(item.name))

def convertToDict(infobox):
    newInfobox = {}
    for item in infobox:
        newInfobox[str(item.name)] = str(item.value)
    return newInfobox

def getInfobox(pageTitle):
    page = pywikibot.Page(cswp, pageTitle)
    wikitext = page.get()               
    wikicode = mwparserfromhell.parse(wikitext)
    templates = wikicode.filter_templates()
    for template in templates:
        debug(template.name)
        if trimLineEnd(template.name).strip().lower() == templateToFind.lower():
            infobox = template.params
            debug(str(infobox))
            return infobox
    # print("---")
    # #trimInfobox(infobox)
    # print(infobox)
    # print("---")
    # #infobox = convertToDict(infobox)
    # print(infobox)
    

def removeOldSymbols(data, objType):
    if objType == 2:
        for item in data:
            debug(item.name)
            if str(item.name).strip() == 'symboly nebezpečí' or str(item.name).strip() == 'symboly nebezpečí GHS':
                info("Removing " + str(item.name))
                data.remove(item)
    else:
        if 'symboly nebezpečí' in data:
            del data['symboly nebezpečí']
        if 'symboly nebezpečí GHS' in data:
            del data['symboly nebezpečí GHS']
    return data

def fixInfobox(data):
    for key in list(data.keys()):
        if key != 'boxes' and key != 'count':
            if "|=|" in data[key]:
                data[key] = regex.sub(r'\|=\|', ' = ', data[key])
    return data

def fixSMILES(smiles):
    dividers = ['<br>', '<br \\>', '<br\\>', ' ']
    for divider in dividers:
        if divider in dividers:
            smiles = smiles.split(divider)[0]
    debug(smiles)
    return smiles

def getPubChemCID(data, dataType):
    global cid
    pubChemAPI = pubChemAPIurl + pubChemAPIpug
    if dataType == 1:
        ids = {'SMILES': 'smiles', 'číslo CAS': 'name'}
        for id in ids.keys():
            for item in data:
                if id == str(item.name).strip():
                    debug("Found: " + id + " " + str(item.name).strip())
                    value = str(item.value).strip()
                    pubChemReqURL = pubChemAPI + ids[id] +'/' + urllib.parse.quote(value) + '/cids/TXT'
                    info("REQUEST " + pubChemReqURL)
                    try:
                        response = urllib.request.urlopen(pubChemReqURL)
                        if response.getcode() == 200:
                            string = response.read().decode('utf-8')
                            cid = json.loads(string.split('\n')[0])
                            info("Found CID: " + str(cid))
                            return cid
                    except HTTPError as err:
                        warning('Not found based on: ' + id + ': ' + value)
                        print(err)
    if dataType == 2:
        ids = {'SMILES (P233)': 'smiles', 'číslo CAS (P231)': 'name'}
        for id in ids.keys():
            for itemKey in data.keys():
                if id == itemKey:
                    value = data[itemKey]
    #print("SMILES: " + data)
    # for id in ids:
    #     if id in data:
    #         value = data[id]
    #         if id == 'SMILES' and ('<br>' in value or '<br \\>' in value or '<br\\>' in value or ' ' in value):
    #             value = fixSMILES(value)
                    pubChemReqURL = pubChemAPI + ids[id] +'/' + urllib.parse.quote(value) + '/cids/TXT'
                    info("REQUEST " + pubChemReqURL)
                    try:
                        response = urllib.request.urlopen(pubChemReqURL)
                        if response.getcode() == 200:
                            string = response.read().decode('utf-8')
                            cid = json.loads(string.split('\n')[0])
                            info("Found CID: " + str(cid))
                            return cid
                    except HTTPError as err:
                        warning('Not found based on: ' + id + ': ' + value)
                        print(err)
    return cid

def getGHSbyCID(cid):
    global ghsTitle
    pubChemReqURL = pubChemAPIurl + pubChemAPIpugView + str(cid) + '/' + pubChemGHSparams
    debug(pubChemReqURL)
    try:
        response = urllib.request.urlopen(pubChemReqURL)
        string = response.read().decode('utf-8')
        json_obj = json.loads(string)
        ghsWords = pyjq.all('.Record.Section[].Section[].Section[].Information[]?.Value?.StringWithMarkup[]?.Markup[]?.Extra?', json_obj)
        ghsTitle = pyjq.first('.Record.RecordTitle', json_obj)
        debug("GHS: " + str(ghsWords))
    except HTTPError as err:
        if err.code == 404 or err.code == 400:
            warning("Invalid response from PubChem or no GHS symbols defined.")
            print(err)
            return ""
        else:
            raise
    return ghsWords

def getNewSymbol(word):
    switcher = {
        'Explosive':'{{GHS01}}',
        'Flammable':'{{GHS02}}',
        'Oxidizing':'{{GHS03}}',
        'Compressed Gas':'{{GHS04}}',
        'Corrosive':'{{GHS05}}',
        'Toxic':'{{GHS06}}',
        'Acute Toxic':'{{GHS06}}',
        'Irritant':'{{GHS07}}',
        'Health Hazard':'{{GHS08}}',
        'Environmental Hazard':'{{GHS09}}'
    }
    return switcher.get(word, "")

def getNewSymbols(data, dataType):
    global cid
    cid = getPubChemCID(data, dataType)
    newSymbols = []
    if cid != 0:
        ghsWords = getGHSbyCID(cid)
        if len(ghsWords) > 0:
            for word in ghsWords:
                if word != None:
                    newSymbols.append(getNewSymbol(word))
            newSymbols = sorted(list(filter(None, set(newSymbols)))) #Remove duplicities converting to set, filter out epty strings and sort
            return "".join(newSymbols)
        else:
            return ""
    else:
        warning("No CID found.")
        return ""

def getInfoboxOrder(key):
    order = ['název', 'obrázek', 'velikost obrázku', 'popisek', 'obrázek2', 'velikost obrázku2', 'popisek2', 'obrázek3', 'velikost obrázku3', 'popisek3', 'systematický název', 'triviální název', 'ostatní názvy', 'latinský název', 'anglický název', 'německý název', 'funkční vzorec', 'sumární vzorec', 'vzhled', 'číslo CAS', 'další čísla CAS', 'číslo EINECS', 'indexové číslo', 'číslo EC', 'PubChem', 'ChEBI', 'UN kód', 'SMILES', 'InChI', 'číslo RTECS', 'molární hmotnost', 'molární koncentrace', 'molární objem', 'teplota tání', 'teplota varu', 'teplota sublimace', 'teplota rozkladu', 'teplota změny modifikace', 'teplota skelného přechodu', 'teplota dehydratace', 'hustota', 'viskozita', 'dynamický viskozitní koeficient', 'kinematický viskozitní koeficient', 'index lomu', 'tvrdost', 'kritická teplota', 'kritický tlak', 'kritická hustota', 'teplota trojného bodu', 'tlak trojného bodu', 'pKa', 'pKb', 'autoionizační konstanta', 'rozpustnost', 'rozpustnost polární', 'rozpustnost nepolární', 'součin rozpustnosti', 'parametr rozpustnosti', 'ebulioskopická konstanta', 'kryoskopická konstanta', 'relativní permitivita', 'tlak páry', 'Van der Waalsovy konstanty', 'izoelektrický bod', 'součinitel elektrické vodivosti', 'součinitel tepelné vodivosti', 'součinitel elektrického odporu', 'součinitel délkové roztažnosti', 'součinitel objemové roztažnosti', 'měrná magnetická susceptibilita', 'měrná vodivost', 'měrný elektrický odpor', 'ionizační energie', 'povrchové napětí', 'průměrný výskyt', 'rychlost zvuku', 'optická otáčivost', 'krystalová struktura', 'hrana mřížky', 'koordinační geometrie', 'tvar molekuly', 'dipólový moment', 'standardní slučovací entalpie', 'standardní molární spalná entalpie', 'entalpie tání', 'entalpie varu', 'entalpie rozpouštění', 'entalpie sublimace', 'entalpie změny modifikace', 'standardní molární entropie', 'standardní slučovací Gibbsova energie', 'měrné teplo', 'izobarické měrné teplo', 'izochorické měrné teplo', 'symboly nebezpečí GHS', 'H-věty', 'P-věty', 'symboly nebezpečí', 'R-věty', 'S-věty', 'NFPA 704', 'zdraví', 'hořlavost', 'reaktivita', 'ostatní rizika', 'teplota vzplanutí', 'teplota hoření', 'teplota vznícení', 'meze výbušnosti']
    if key == 'boxes' or key == 'count':
        return 1
    else:
        return order.index(key)

def sortInfobox(data):
    keyOrder = {k:v for v,k in enumerate(['název', ' název ', ' název', 'název ', 'obrázek', ' obrázek ', ' obrázek', 'obrázek ', 'velikost obrázku', ' velikost obrázku ', ' velikost obrázku', 'velikost obrázku ', 'popisek', ' popisek ', ' popisek', 'popisek ', 'obrázek2', ' obrázek2 ', ' obrázek2', 'obrázek2 ', 'velikost obrázku2', ' velikost obrázku2 ', ' velikost obrázku2', 'velikost obrázku2 ', 'popisek2', ' popisek2 ', ' popisek2', 'popisek2 ', 'obrázek3', ' obrázek3 ', ' obrázek3', 'obrázek3 ', 'velikost obrázku3', ' velikost obrázku3 ', ' velikost obrázku3', 'velikost obrázku3 ', 'popisek3', ' popisek3 ', ' popisek3', 'popisek3 ', 'systematický název', ' systematický název ', ' systematický název', 'systematický název ', 'triviální název', ' triviální název ', ' triviální název', 'triviální název ', 'ostatní názvy', ' ostatní názvy ', ' ostatní názvy', 'ostatní názvy ', 'latinský název', ' latinský název ', ' latinský název', 'latinský název ', 'anglický název', ' anglický název ', ' anglický název', 'anglický název ', 'německý název', ' německý název ', ' německý název', 'německý název ', 'funkční vzorec', ' funkční vzorec ', ' funkční vzorec', 'funkční vzorec ', 'sumární vzorec', ' sumární vzorec ', ' sumární vzorec', 'sumární vzorec ', 'vzhled', ' vzhled ', ' vzhled', 'vzhled ', 'číslo CAS', ' číslo CAS ', ' číslo CAS', 'číslo CAS ', 'další čísla CAS', ' další čísla CAS ', ' další čísla CAS', 'další čísla CAS ', 'číslo EINECS', ' číslo EINECS ', ' číslo EINECS', 'číslo EINECS ', 'indexové číslo', ' indexové číslo ', ' indexové číslo', 'indexové číslo ', 'číslo EC', ' číslo EC ', ' číslo EC', 'číslo EC ', 'PubChem', ' PubChem ', ' PubChem', 'PubChem ', 'ChEBI', ' ChEBI ', ' ChEBI', 'ChEBI ', 'UN kód', ' UN kód ', ' UN kód', 'UN kód ', 'SMILES', ' SMILES ', ' SMILES', 'SMILES ', 'InChI', ' InChI ', ' InChI', 'InChI ', 'číslo RTECS', ' číslo RTECS ', ' číslo RTECS', 'číslo RTECS ', 'molární hmotnost', ' molární hmotnost ', ' molární hmotnost', 'molární hmotnost ', 'molární koncentrace', ' molární koncentrace ', ' molární koncentrace', 'molární koncentrace ', 'molární objem', ' molární objem ', ' molární objem', 'molární objem ', 'teplota tání', ' teplota tání ', ' teplota tání', 'teplota tání ', 'teplota varu', ' teplota varu ', ' teplota varu', 'teplota varu ', 'teplota sublimace', ' teplota sublimace ', ' teplota sublimace', 'teplota sublimace ', 'teplota rozkladu', ' teplota rozkladu ', ' teplota rozkladu', 'teplota rozkladu ', 'teplota změny modifikace', ' teplota změny modifikace ', ' teplota změny modifikace', 'teplota změny modifikace ', 'teplota skelného přechodu', ' teplota skelného přechodu ', ' teplota skelného přechodu', 'teplota skelného přechodu ', 'teplota dehydratace', ' teplota dehydratace ', ' teplota dehydratace', 'teplota dehydratace ', 'hustota', ' hustota ', ' hustota', 'hustota ', 'viskozita', ' viskozita ', ' viskozita', 'viskozita ', 'dynamický viskozitní koeficient', ' dynamický viskozitní koeficient ', ' dynamický viskozitní koeficient', 'dynamický viskozitní koeficient ', 'kinematický viskozitní koeficient', ' kinematický viskozitní koeficient ', ' kinematický viskozitní koeficient', 'kinematický viskozitní koeficient ', 'index lomu', ' index lomu ', ' index lomu', 'index lomu ', 'tvrdost', ' tvrdost ', ' tvrdost', 'tvrdost ', 'kritická teplota', ' kritická teplota ', ' kritická teplota', 'kritická teplota ', 'kritický tlak', ' kritický tlak ', ' kritický tlak', 'kritický tlak ', 'kritická hustota', ' kritická hustota ', ' kritická hustota', 'kritická hustota ', 'teplota trojného bodu', ' teplota trojného bodu ', ' teplota trojného bodu', 'teplota trojného bodu ', 'tlak trojného bodu', ' tlak trojného bodu ', ' tlak trojného bodu', 'tlak trojného bodu ', 'pKa', ' pKa ', ' pKa', 'pKa ', 'pKb', ' pKb ', ' pKb', 'pKb ', 'autoionizační konstanta', ' autoionizační konstanta ', ' autoionizační konstanta', 'autoionizační konstanta ', 'rozpustnost', ' rozpustnost ', ' rozpustnost', 'rozpustnost ', 'rozpustnost polární', ' rozpustnost polární ', ' rozpustnost polární', 'rozpustnost polární ', 'rozpustnost nepolární', ' rozpustnost nepolární ', ' rozpustnost nepolární', 'rozpustnost nepolární ', 'součin rozpustnosti', ' součin rozpustnosti ', ' součin rozpustnosti', 'součin rozpustnosti ', 'parametr rozpustnosti', ' parametr rozpustnosti ', ' parametr rozpustnosti', 'parametr rozpustnosti ', 'ebulioskopická konstanta', ' ebulioskopická konstanta ', ' ebulioskopická konstanta', 'ebulioskopická konstanta ', 'kryoskopická konstanta', ' kryoskopická konstanta ', ' kryoskopická konstanta', 'kryoskopická konstanta ', 'relativní permitivita', ' relativní permitivita ', ' relativní permitivita', 'relativní permitivita ', 'tlak páry', ' tlak páry ', ' tlak páry', 'tlak páry ', 'Van der Waalsovy konstanty', ' Van der Waalsovy konstanty ', ' Van der Waalsovy konstanty', 'Van der Waalsovy konstanty ', 'izoelektrický bod', ' izoelektrický bod ', ' izoelektrický bod', 'izoelektrický bod ', 'součinitel elektrické vodivosti', ' součinitel elektrické vodivosti ', ' součinitel elektrické vodivosti', 'součinitel elektrické vodivosti ', 'součinitel tepelné vodivosti', ' součinitel tepelné vodivosti ', ' součinitel tepelné vodivosti', 'součinitel tepelné vodivosti ', 'součinitel elektrického odporu', ' součinitel elektrického odporu ', ' součinitel elektrického odporu', 'součinitel elektrického odporu ', 'součinitel délkové roztažnosti', ' součinitel délkové roztažnosti ', ' součinitel délkové roztažnosti', 'součinitel délkové roztažnosti ', 'součinitel objemové roztažnosti', ' součinitel objemové roztažnosti ', ' součinitel objemové roztažnosti', 'součinitel objemové roztažnosti ', 'měrná magnetická susceptibilita', ' měrná magnetická susceptibilita ', ' měrná magnetická susceptibilita', 'měrná magnetická susceptibilita ', 'měrná vodivost', ' měrná vodivost ', ' měrná vodivost', 'měrná vodivost ', 'měrný elektrický odpor', ' měrný elektrický odpor ', ' měrný elektrický odpor', 'měrný elektrický odpor ', 'ionizační energie', ' ionizační energie ', ' ionizační energie', 'ionizační energie ', 'povrchové napětí', ' povrchové napětí ', ' povrchové napětí', 'povrchové napětí ', 'průměrný výskyt', ' průměrný výskyt ', ' průměrný výskyt', 'průměrný výskyt ', 'rychlost zvuku', ' rychlost zvuku ', ' rychlost zvuku', 'rychlost zvuku ', 'optická otáčivost', ' optická otáčivost ', ' optická otáčivost', 'optická otáčivost ', 'krystalová struktura', ' krystalová struktura ', ' krystalová struktura', 'krystalová struktura ', 'hrana mřížky', ' hrana mřížky ', ' hrana mřížky', 'hrana mřížky ', 'koordinační geometrie', ' koordinační geometrie ', ' koordinační geometrie', 'koordinační geometrie ', 'tvar molekuly', ' tvar molekuly ', ' tvar molekuly', 'tvar molekuly ', 'dipólový moment', ' dipólový moment ', ' dipólový moment', 'dipólový moment ', 'standardní slučovací entalpie', ' standardní slučovací entalpie ', ' standardní slučovací entalpie', 'standardní slučovací entalpie ', 'standardní molární spalná entalpie', ' standardní molární spalná entalpie ', ' standardní molární spalná entalpie', 'standardní molární spalná entalpie ', 'entalpie tání', ' entalpie tání ', ' entalpie tání', 'entalpie tání ', 'entalpie varu', ' entalpie varu ', ' entalpie varu', 'entalpie varu ', 'entalpie rozpouštění', ' entalpie rozpouštění ', ' entalpie rozpouštění', 'entalpie rozpouštění ', 'entalpie sublimace', ' entalpie sublimace ', ' entalpie sublimace', 'entalpie sublimace ', 'entalpie změny modifikace', ' entalpie změny modifikace ', ' entalpie změny modifikace', 'entalpie změny modifikace ', 'standardní molární entropie', ' standardní molární entropie ', ' standardní molární entropie', 'standardní molární entropie ', 'standardní slučovací Gibbsova energie', ' standardní slučovací Gibbsova energie ', ' standardní slučovací Gibbsova energie', 'standardní slučovací Gibbsova energie ', 'měrné teplo', ' měrné teplo ', ' měrné teplo', 'měrné teplo ', 'izobarické měrné teplo', ' izobarické měrné teplo ', ' izobarické měrné teplo', 'izobarické měrné teplo ', 'izochorické měrné teplo', ' izochorické měrné teplo ', ' izochorické měrné teplo', 'izochorické měrné teplo ', 'symboly nebezpečí GHS', ' symboly nebezpečí GHS ', ' symboly nebezpečí GHS', 'symboly nebezpečí GHS ', 'H-věty', ' H-věty ', ' H-věty', 'H-věty ', 'P-věty', ' P-věty ', ' P-věty', 'P-věty ', 'symboly nebezpečí', ' symboly nebezpečí ', ' symboly nebezpečí', 'symboly nebezpečí ', 'R-věty', ' R-věty ', ' R-věty', 'R-věty ', 'S-věty', ' S-věty ', ' S-věty', 'S-věty ', 'NFPA 704', ' NFPA 704 ', ' NFPA 704', 'NFPA 704 ', 'zdraví', ' zdraví ', ' zdraví', 'zdraví ', 'hořlavost', ' hořlavost ', ' hořlavost', 'hořlavost ', 'reaktivita', ' reaktivita ', ' reaktivita', 'reaktivita ', 'ostatní rizika', ' ostatní rizika ', ' ostatní rizika', 'ostatní rizika ', 'teplota vzplanutí', ' teplota vzplanutí ', ' teplota vzplanutí', 'teplota vzplanutí ', 'teplota hoření', ' teplota hoření ', ' teplota hoření', 'teplota hoření ', 'teplota vznícení', ' teplota vznícení ', ' teplota vznícení', 'teplota vznícení ', 'meze výbušnosti', ' meze výbušnosti ', ' meze výbušnosti', 'meze výbušnosti '])}
    return OrderedDict(sorted(data.items(), key=lambda i:keyOrder.get(i[0])))

def addNewSymbols(infobox, newSymbols, objType):
    global cid
    today = date.today().strftime("%Y-%m-%d")
    infobox = convertToDict(infobox)
    reference = '<ref name=pubchem_cid_' + str(cid) + '>{{Citace elektronického periodika | titul = ' + ghsTitle + ' | periodikum = pubchem.ncbi.nlm.nih.gov | vydavatel = PubChem | url = https://pubchem.ncbi.nlm.nih.gov/compound/' + str(cid) + ' | jazyk = en | datum přístupu = ' + today + ' }}</ref>'
    GHSsymbolsTitle = ' symboly nebezpečí GHS '
    GHSsymbolsValue = ' ' + newSymbols + reference
    if objType == 2:
        infobox[GHSsymbolsTitle] = GHSsymbolsValue
        #infobox.append(mwparserfromhell.parse(GHSsymbolsTitle + GHSsymbolsValue))
        
    else:
        infobox['symboly nebezpečí GHS'] = newSymbols + reference
    debug("------")
    debug("INFOBOX 2")
    debug(infobox)
    return sortInfobox(infobox)

def removeOldInfobox(file):
    debug("Removing")
    stagedFile = open(file, "r+")
    stagedContents = stagedFile.read()
    stagedContents = regex.sub(r'(?=\{[I|i]nfobox)(\{([^{}]|(?1))*\})', 'NEW_INFOBOX', stagedContents)
    stagedFile.close()
    debug(stagedContents)
    #os.remove(file)
    stagedFile = open(file, "w+")
    stagedFile.write(stagedContents)
    stagedFile.close()
    debug("")


def constructInfobox(data, addLineEnd = True, addAllSpaces = True):
    Path('data/newInfobox.txt', exist_ok=True).touch()
    newInfoboxFile = open('data/newInfobox.txt', "a+")
    newInfoboxFile.write('{Infobox - chemická sloučenina\n')
    debug("------")
    debug("DATA 2")
    debug(data)
    if addLineEnd:
        lineEnd = '\n'
    else:
        lineEnd = ''
    if addAllSpaces:
        equal = ' = '
        lineBegin = ' | '
    else:
        equal = '='
        lineBegin = '|'
    for key, value in data.items():
        # if not value.strip():
        #     equal = ' ='
        newInfoboxFile.write(lineBegin + key + equal + value + lineEnd)
    newInfoboxFile.write('}')
    newInfoboxFile.close()

def getHeader(file):
    stagedFile = open(file, "r")
    stagedContents = stagedFile.read()
    headerContents = regex.match(r'[\s\S]*(?=\{NEW_INFOBOX\})', stagedContents).group(0)
    stagedFile.close()
    headerFile = open('data/headerFile.txt', 'w+')
    headerFile.write(headerContents)
    headerFile.close()

def getFooter(file):
    stagedFile = open(file, "r")
    stagedContents = stagedFile.read()
    footerContents = regex.match(r'(?<=\{NEW_INFOBOX\})[\s\S]*', stagedContents).group(0)
    stagedFile.close()
    footerFile = open('data/footerFile.txt', 'w+')
    footerFile.write(footerContents)
    footerFile.close()

def createNewFile(infobox):
    constructInfobox(infobox)
    newInfoboxFile = open('data/newInfobox.txt', "r")
    newInfoboxContents = newInfoboxFile.read()
    headerFile = open('data/headerFile.txt', "r")
    headerFileContents = headerFile.read()
    footerFile = open('data/footerFile.txt', "r")
    footerFileContents = footerFile.read()
    stagedFile = open('data/stagedtext.txt', "w+")
    stagedFile.write(headerFileContents)
    stagedFile.close()
    stagedFile = open('data/stagedtext.txt', "a+")
    stagedFile.write(newInfoboxContents)
    stagedFile.write(footerFileContents)
    stagedFile.close()

#def escapeBackslashes(data):
    #return data.replace('')

def addNewInfobox(data, file, addLineEnd = True, addAllSpaces = True):
    debug("------")
    debug("DATA 1")
    debug(data)
    constructInfobox(data, addLineEnd, addAllSpaces)
    newInfoboxFile = open('data/newInfobox.txt', "r")
    newInfoboxContents = newInfoboxFile.read()
    stagedFile = open(file, "r")
    stagedContents = stagedFile.read()
    #stagedContents = regex.sub('NEW_INFOBOX', escapeBackslashes(newInfoboxContents), stagedContents)
    stagedContents = stagedContents.replace('NEW_INFOBOX', newInfoboxContents)
    stagedFile.close()
    debug(stagedContents)
    #os.remove(file)
    stagedFile = open(file, "w+")
    stagedFile.write(stagedContents)
    stagedFile.close()
    debug("FINISHED")
    debug("")


getCategoryMembers(categoryName)

#manualMembers = {'xx': {'title': '1,2,3,3,3-pentafluorpropen', 'pageid': 11}}
for member in members:
    cleanStaged(dataDirName)
    newSymbols = ""
    createDirectory(dataDirName)
    title = member['title']
    pageid = member['pageid']
    #title = '2-ethylhexanoát_cínatý'
    info('-----------------------------------')
    info("Getting: " + title)
    page = wptools.page(title)
    page.get()
    extext = page.data['extext']
    stagedtext = page.data['wikitext']
    textfile = open("data/stagedtext.txt","w+")
    textfile.write(stagedtext)
    textfile.close()
    copyfile('data/stagedtext.txt', 'data/original.txt')
    #infobox = page.data['infobox']
    #lead = page.data['lead']
    #infobox = fixInfobox(infobox)
    infobox = getInfobox(title)
    infobox = removeOldSymbols(infobox, 2)
    if infobox:
        newSymbols = getNewSymbols(infobox, 1)
    else:
        wikidata = page.data['wikidata']
        newSymbols = getNewSymbols(wikidata, 2)
    if newSymbols != "":
        infobox = addNewSymbols(infobox, newSymbols, 2)
        removeOldInfobox("data/stagedtext.txt")
        # getHeader("data/stagedtext.txt")
        # getFooter("data/stagedtext.txt")
        # createNewFile(infobox)
        addNewInfobox(infobox, "data/stagedtext.txt", False, False)
        info("Pushing: " + title)
        if automaticPush != True:
            input("Press Enter to continue...")
        if testPush == True:
            subprocess.call(["./wikipush.sh", "-c=data/stagedtext.txt", "-t=" + title, "--test"])
        else:
            subprocess.call(["./wikipush.sh", "-c=data/stagedtext.txt", "-t=" + title])
    info('-----------------------------------')
    info("DONE: " + title)
    if automaticRun != True:
        input("Press Enter to continue...")
