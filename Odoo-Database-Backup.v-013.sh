#!/bin/bash

# Copyright (C) 2023. Benoît-Pierre DEMAINE (aka DoubleHP) and Galoula
#
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

# perform full traffic dump:
# https://superuser.com/questions/298655/log-http-and-https-browser-traffic-decrypting-the-latter

# This script will generate (and remove) some temp files in the current dir.

# This script is intended to perform an external backup of main and duplicated DataBases hosted on Odoo-Online. It can be called by cron-weekly or any similar thing you like. Odoo platform would probably be unhappy to see this script run more than once a day.

# Developped for Odoo v16.
# Tested with Odoo v16.0

# Variables
odoo_instance=https://www.odoo.com
username="MyLogin@MyDomain.fun"
password="MyPassword"
dbname="DbName"

# Authentification
login_url="${odoo_instance}/web/login"
dashboard_url="${odoo_instance}/web"
# Create cookies, grab user-cession token
wget -o /dev/null -O loginp.html $login_url \
	--load-cookies cookies.txt --save-cookies cookies.txt --keep-session-cookies
csrf_token=$(grep -o "csrf_token: \"[a-z0-9]*\"" loginp.html | grep -o "[a-z0-9]*" | tail -n1)
rm loginp.html
echo "csrf_token: '$csrf_token'."
# Really login
wget -o /dev/null -O login.html $login_url \
	--load-cookies cookies.txt --save-cookies cookies.txt --keep-session-cookies \
	--post-data "login=$username&password=$password&db=$dbname&csrf_token=${csrf_token}"
[ -f login.html ] && true echo "Server 200 (OK)." || { echo "auth failed - file does not exists." ; exit 1 ; } ;
cat login.html | grep -q -e Login && { echo "* Login FAILED !!! " ; exit 1 ; }
cat login.html | grep -q -e Databases && echo "We are auth" || { echo "* Unknown error !!! " ; exit 1 ; }
rm login.html

# Grab db_uuid . For a given DB, this value will always be the same.
wget -o /dev/null -O databases.html https://www.odoo.com/odoo-enterprise/databases \
	--header="Accept: application/json, text/javascript, */*; q=0.01" \
	--header="Content-Type: application/json" \
	--load-cookies cookies.txt --save-cookies cookies.txt --keep-session-cookies \
	--post-data="{\"jsonrpc\":\"2.0\",\"method\":\"call\",\"params\":{\"share\":false}}"
db_uuid="$(cat databases.html | jq | grep -e id -e db_name -e uuid | grep "\"db_name\": \"${dbname}\"" -A1 | grep '"uuid":' | cut -d '"' -f4)"
rm databases.html
echo "db_uuid: '$db_uuid'."

# Grab user_id (optionnal in fact). This value changes for each connexion, but in fact, 100000000 always works.
# The value should look like 867437904
# but I have not been able to find how to grab it. So I give up, and just set a working constant value.
# Since it seems to change after each login, and the server may need this value to be uniq, I will add a bit of salt in it. Server seems to prefer some ranges over other ones ...
true wget -o /dev/null -O my_id.html https://www.odoo.com/auth/new-token \
	--header="Accept: application/json, text/javascript, */*; q=0.01" \
	--header="Content-Type: application/json" \
	--load-cookies cookies.txt --save-cookies cookies.txt --keep-session-cookies
#idid="100000000" # works
#idid="099999999" # not
# Bash random number generator; could probably be optimised; but I am not assuming bc is available.
#idid="$(len=9 ; while [ $len -gt 0 ] ; do c="$(head -c 1 /dev/urandom 2>/dev/null | tr -cd '0-9' 2>/dev/null)" ; [ $c -gt -1 ] 2>/dev/null || continue ; [ $len -eq 9 -a $c -lt 4 ] && continue ; echo -n "$c" && len=$(($len-1)) ; done )"
# ChatGPT proposed something that, in the forst place was bad, but I could tweak it in something nice and efficient
# The randomness of this is not as good as mine, but it's WAY better than just idid="100000000" (Bash generates RANDOM in 16b, so the max value is 2^16-1; if these random numbers were perfect, applying %10000 gives more weight to values below 2^16-1-60000=5535 . Odoo won't care this detail. )
idid="$(echo $(((1 + (RANDOM % 9)) * 100000000 + ( (RANDOM % 10000) * 10000 ) + RANDOM % 1000)) )"
echo "User ID: '${idid}'."
true rm my_id.html

# Grab dump token (uniq for one download)
wget -o /dev/null -O token.js https://www.odoo.com/auth/new-token \
	--header="Accept: application/json, text/javascript, */*; q=0.01" \
	--header="Referer: https://www.odoo.com/fr_FR/my/databases" \
	--header="Content-Type: application/json" \
	--header="Origin: https://www.odoo.com" \
	--load-cookies cookies.txt --save-cookies cookies.txt --keep-session-cookies \
	--post-data='{"jsonrpc":"2.0","method":"call","params":{"db_uuid":"'"${db_uuid}"'"},"id":'"${idid}}"
dump_token=$(cat token.js | jq '.result.token' | sed 's/"//g')
rm token.js
echo "Dump Token: '${dump_token}'."

MyFile="${dbname}.dump.$(/bin/date +%Y-%m-%d_%H-%M-%S).zip"
wget -O "$MyFile" \
	https://${dbname}.odoo.com/saas_worker/dump?oauth_token=${dump_token} \
	--header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
	|| { echo "Download failed. You should delete '$MyFile'." ; exit 1 ; }
[ -s "$MyFile" ] && echo "Server 200." || { echo "Something failed." ; exit 1 ; } ;
file -s "$MyFile" | grep -q -i -e "Zip archive dat" || { echo "File '$MyFile' is broken, you should delete it (it may contain an error message or a clue about the problem; read it first)." ; exit 1 ; }
rm cookies.txt

exit 0
