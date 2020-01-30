import pywikibot
import mwparserfromhell
import re
from pywikibot import textlib

templateToFind = 'Infobox - chemická sloučenina'

cswp = pywikibot.Site('cs','wikipedia')
page = pywikibot.Page(cswp, '1,8-diazabicyklo(5.4.0)undec-7-en')            
wikitext = page.get()               
wikicode = mwparserfromhell.parse(wikitext)
templates = wikicode.filter_templates()
infobox = "empty"

def trimLineEnd(data):
    return re.sub('\r?\n', '', str(data))

def trimInfobox(infobox):
    for item in infobox:
        item.value = trimLineEnd(item.value)

def convertToDict(infobox):
    newInfobox = {}
    for item in infobox:
        newInfobox[str(item.name)] = str(item.value)
    return newInfobox

for template in templates:
    print(template.name)
    name = template.name
    if trimLineEnd(template.name) == templateToFind:
        infobox = template.params
print(infobox)
print("---")
trimInfobox(infobox)
print(infobox)
print("---")
infobox = convertToDict(infobox)
print(infobox)
print("")