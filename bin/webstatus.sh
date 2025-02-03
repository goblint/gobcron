#!/bin/bash

# import communication with zulip
SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPTDIR/../lib/library.sh"


function f {
    # ExposeAuthInfo yes in /etc/ssh/sshd_config

    echo -n "<h1>Goblint/SV-Comp Running:</h1>"
    echo "<p>Folder: $(conf "instance.basedir")</p>"
    if [ -f "$SSH_USER_AUTH" ]; then
        local username; username = $(grep "$(cat $SSH_USER_AUTH | awk '{ print $3} ')" .ssh/authorized_keys | awk '{ print $3} ')
        echo "<p>User: $username</p>"
    fi
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