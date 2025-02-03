#!/bin/bash

# import communication with zulip
SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/../lib/library.sh"


function f {
    echo -n "<h1>Goblint/SV-Comp Running:</h1>"
    echo "<p>Folder: $(conf "instance.basedir")</p>"
    echo "<p>Tag: $(conf "instance.tag")</p>"
    echo "<p>Goblintversion: $(conf "instance.gitrepo")[$(conf "instance.branch")]@$(conf "instance.commit")</p>"
    ./bin/progress.sh
}

echo "$$"
basedir="$(conf "instance.basedir")"
cd "$basedir"
while true; do
{ echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n"; echo "<html><body>"; f ; echo "</body></html>"; } | nc -l -q 2 -p 8080
done