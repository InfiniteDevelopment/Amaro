set -ue  # Bomb on uninitialized variables and non-zero exit statuses
set -o pipefail  # Pass the first non-zero exit status through a pipe

BOOTSTRAP_REPO="git://github.com/crushlovely/Amaro.git"
BOOTSTRAP_WEBSITE="https://github.com/crushlovely/Amaro"
BOOTSTRAP_BRANCH=master

# These are values that are replaced by user input
BOOTSTRAP_PREFIX=CRBS
BOOTSTRAP_PROJECT_NAME=CrushBootstrap
BOOTSTRAP_ORG="Crush & Lovely"
BOOTSTRAP_DOMAIN="com.crushlovely"


DEFAULT_FULLNAME=$(dscl . read /Users/`whoami` RealName | sed -n $'s/^[\t ]*//;2p')

set +e
DEFAULT_ORG=$(/usr/libexec/PlistBuddy -c 'Print :IDETemplateOptions:organizationName' "${HOME}/Library/Preferences/com.apple.dt.Xcode.plist")
set -e
[[ -z "$DEFAULT_ORG" ]] && DEFAULT_ORG="MyCompany"



####################
### Utilities
####################

die() {
    echo -e "\n💀  $1"
    exit 1
}

trim() {
    echo $1 | sed $'s/^[\t ]*//;s/[\t ]*$//'
}

removeAllWhitespace() {
    echo $1 | sed $'s/[\t ]*//g'
}

edit() {
    set +u
    if [[ -n "$VISUAL" ]]; then $VISUAL "$1"
    elif [[ -n "$EDITOR" ]]; then $EDITOR "$1"
    else nano "$1"; fi
    set -u
}

friendlyGrep() {
    local INPUT=""
    # Grep returns a nonzero exit status if it doesn't match any lines, which we don't want.
    while read LINE; do
        if [[ "$LINE" != "\n" && -n "$LINE" ]]; then
            if [[ -z "$INPUT" ]]; then INPUT="$LINE"
            else INPUT="$LINE\n$INPUT"; fi
        fi
    done

    set +e
    echo -e "$INPUT" | grep "$@"
    set -e
    return 0
}

set +u
_OLD_LC_CTYPE="$LC_CTYPE"
_OLD_LANG="$LANG"
set -u

switchToCLocale() {
    # Without these magical incantations, sed barfs on some unicode.
    # But, we can't set them globally because Cocoapods wants a real locale.
    export LC_CTYPE=C
    export LANG=C
}

resetLocale() {
    export LC_CTYPE="$_OLD_LC_CTYPE"
    export LANG="$_OLD_LANG"
}



####################
### Crashlytics
####################

setUpCrashlytics() {
    read -p 'Crashlytics email: ' CL_EMAIL
    if [ -z "$CL_EMAIL" ]; then
        echo "Aborting Crashlytics setup..."
        return 0
    fi

    read -sp 'Crashlytics password: ' CL_PASSWORD
    echo
    if [ -z "$CL_PASSWORD" ]; then
        echo "Aborting Crashlytics setup..."
        return 0
    fi

    # We're pulling this data from the Crashlytics API, bypassing the GUI.
    # See https://gist.github.com/codebutler/5763818

    PYTHON_CMD=$(cat <<EOF
try:
    import sys, json;
    for org in json.load(sys.stdin)['organizations']:
        print org['name'] + ':', org['api_key']
except:
    pass
EOF)

    set +e

    ORGS_RAW=$(curl -sSf --header "Content-Type: application/json" \
                   --header "X-CRASHLYTICS-DEVELOPER-TOKEN: ed8fc3dc68a7475cc970eb1e9c0cb6603b0a3ea2" \
                   --data "{\"email\":\"$CL_EMAIL\",\"password\":\"$CL_PASSWORD\"}" https://api.crashlytics.com/api/v2/session.json | \
               python -c "$PYTHON_CMD")

    set -e

    if [ -z "$ORGS_RAW" ]; then
        echo "Error talking with the Crashlytics API. Aborting Crashlytics setup..."
        return 0
    fi

    # Split on newlines into an array
    IFS=$'\n' ORGS=($ORGS_RAW)

    # If there's only one organization, use it
    if [ ${#ORGS[@]} -eq 1 ]; then
        installCrashlyticsKeyFromOrg "${ORGS[0]}"
        return 0
    fi

    local PS3="Which organization would you like to use? "
    select ORG in "${ORGS[@]}" "Cancel"; do
        [ "$ORG" = "Cancel" ] && return 0
        if [ -n "$ORG" ]; then
            installCrashlyticsKeyFromOrg "$ORG"
            break
        fi
    done
}

installCrashlyticsKeyFromOrg() {
    # This regex is just a little too much for sed, apparently...
    ORG_NAME=$(echo "$1" | perl -pe 's/^(.*): .+$/\1/')
    KEY=$(echo "$1" | perl -pe 's/^.*: (.+)$/\1/')
    echo " ✨  Using Crashlytics key for $ORG_NAME"

    echo -n "Updating file contents... "
    switchToCLocale
    find . -type f -not \( -path './.git/*' -prune \) -exec sed -i '' "s/<<CrashlyticsAPIKey>>/$KEY/g" {} +
    resetLocale
    echo "👍"

    echo -n "Committing... "
    git add --all
    git commit -q -m "[Amaro] Installed Crashlytics API key"
    echo "👍"
}



####################
### Gathering Info
####################

echo
echo "😸  Amaro v0.1.0!"
echo -e "We'll be using branch $BOOTSTRAP_BRANCH of $BOOTSTRAP_REPO\n"


### Check on deps
echo -n "Checking environment... "
type pod >/dev/null 2>&1 || die "You need CocoaPods installed. http://cocoapods.org/#install"

echo -e "👍\n"


#### Project Name
read -p "New project name: " ORIG_PROJECT_NAME
PROJECT_NAME=$(trim "$ORIG_PROJECT_NAME" | tr -s ' ' | tr ' ' '-')

[[ -z "$PROJECT_NAME" ]] && die "Ya gotta enter something!"
[[ $(dirname -- "$PROJECT_NAME") != "." ]] && die "No paths in your name, silly!"
[[ "$PROJECT_NAME" != "$ORIG_PROJECT_NAME" ]] && echo " ✨  Fixed that for you. Using '$PROJECT_NAME'"
[[ -e "$PROJECT_NAME" ]] && die "A file already exists with that name!"
[[ "$PROJECT_NAME" == "$BOOTSTRAP_PROJECT_NAME" ]] && die "Very funny."


### Prefix
isBlacklistedPrefix() {
    # http://www.fvue.nl/wiki/Bash:_Check_if_array_element_exists
    # This is not a complete list, but certainly hits the highpoints
    BAD_PREFIXES=( AB AC AD AL AU AV CA CB CF CG CI CL CM CV EA EK GC JS MA MC MF MK NK NS PK QL SC SK SL SS TW UI UT )

    local needle=$1
    shift

    set -- ${BAD_PREFIXES[@]}

    for prefix; do
        [[ $prefix == $needle ]] && return 0
    done
    return 1
}

read -p "Class prefix (2 or preferably 3 characters): " ORIG_PREFIX
PREFIX=$(removeAllWhitespace "$ORIG_PREFIX")

PREFIX=$(echo "$PREFIX" | tr '[:lower:]' '[:upper:]')
[[ "$PREFIX" != "$ORIG_PREFIX" ]] && echo " ✨  Fixed that for you. Using '$PREFIX'"
[[ ${#PREFIX} < 2 ]] && die "Prefix is too short"
[[ ${#PREFIX} > 3 ]] && die "Prefix is too long. Ain't nobody got time to type that."
[[ $PREFIX =~ ^[A-Z][A-Z0-9]+$ ]] || die "Prefix is an invalid identifier"
isBlacklistedPrefix "$PREFIX" && die "That prefix is already used by Apple"
[[ "$PREFIX" == "$BOOTSTRAP_PREFIX" ]] && die "Very funny."


### Full name
read -p "Your name (blank for $DEFAULT_FULLNAME): " FULLNAME
FULLNAME=$(trim "$FULLNAME")
if [[ -z "$FULLNAME" ]]; then
    FULLNAME="$DEFAULT_FULLNAME"
    echo " ✨  Using name $FULLNAME"
fi


### Organization Name
read -p "Organization name (blank for $DEFAULT_ORG): " ORG_NAME
ORG_NAME=$(trim "$ORG_NAME")
if [[ -z "$ORG_NAME" ]]; then
    ORG_NAME="$DEFAULT_ORG"
    echo " ✨  Using organization $DEFAULT_ORG"
fi


### Bundle ID domain
DEFAULT_DOMAIN=$(echo "$ORG_NAME" | sed -e 's/[^[:alnum:]]//g' | tr A-Z a-z)
DEFAULT_DOMAIN="com.$DEFAULT_DOMAIN"
read -p "Bundle ID domain (blank for $DEFAULT_DOMAIN): " BUNDLE_DOMAIN
BUNDLE_DOMAIN=$(trim "$BUNDLE_DOMAIN")
if [[ -z "$BUNDLE_DOMAIN" ]]; then
  BUNDLE_DOMAIN="$DEFAULT_DOMAIN"
  echo " ✨  Using domain $DEFAULT_DOMAIN"
fi


echo -e "\n🎉  Thus ends the interrogation."
echo -e "Pausing for 3 seconds in case you change your mind. Ctrl+C to abort."
sleep 3
echo -e "\n"



####################
### Down to business
####################

### Make the directory and bring in the repo

mkdir -- "$PROJECT_NAME"
cd -- "$PROJECT_NAME"

git init -q

# It's a shame we have to do this, really, but you can't do a squashed merge into an empty repo
echo -e "# $PROJECT_NAME\n\n*An iOS project begun with [Amaro]($BOOTSTRAP_WEBSITE)*\n" > README.md
git add README.md
git commit -q -m "[Amaro] Initial commit"

echo -n "Fetching repository... "
git remote add bootstrap "$BOOTSTRAP_REPO"
git fetch -q bootstrap "$BOOTSTRAP_BRANCH" 2>&1 | friendlyGrep -v 'warning: no common commits'
echo "👍"

echo -n "Merging... "
# We're using 'ours' merge option so that our README.md wins
git merge -q --squash -X ours "remotes/bootstrap/$BOOTSTRAP_BRANCH" 2>&1 | friendlyGrep -v 'Squash commit -- not updating HEAD' | friendlyGrep -v 'Automatic merge went well'
git commit -q -m "[Amaro] Bootstrapping..."
echo "👍"


### File renames

renameProjectFile() {
    OLD_NAME="$1"
    NEW_NAME=$(echo "$1" | sed "s/$BOOTSTRAP_PROJECT_NAME/$PROJECT_NAME/")
    git mv "$OLD_NAME" "$NEW_NAME"
}

renamePrefixedFile() {
    OLD_NAME="$1"
    NEW_NAME=$(echo "$1" | sed "s/^$BOOTSTRAP_PREFIX/$PREFIX/")
    git mv "$OLD_NAME" "$NEW_NAME"
}

# Make these variables and functions available to our find -execs below
export -f renameProjectFile
export -f renamePrefixedFile
export BOOTSTRAP_PROJECT_NAME PROJECT_NAME BOOTSTRAP_PREFIX PREFIX FULLNAME

echo -n "Renaming files... "

# The -d is for a depth-first search, which ensures that files get renamed before their parent
# directories, which would break things, obviously.
# Re: the bash -c and $0 craziness, see http://stackoverflow.com/questions/4321456/find-exec-a-shell-function
find . -d -name "*$BOOTSTRAP_PROJECT_NAME*" \( -type f -o -type d \)  -not \( -path './.git/*' -prune \) -execdir bash -c 'renameProjectFile "$0"' {} \;

if [[ "$PREFIX" != "$BOOTSTRAP_PREFIX" ]]; then
    find . -type f -name "$BOOTSTRAP_PREFIX*" -not \( -path './.git/*' -prune \) -execdir bash -c 'renamePrefixedFile "$0"' {} \;
fi

echo "👍"


### Content Changes

echo -n "Updating file contents... "

switchToCLocale

# Any reference to the project name or the prefix in all files:
find . -type f -not \( -path './.git/*' -prune \) -not -path './README.md' -exec sed -i '' "s/$BOOTSTRAP_PROJECT_NAME/$PROJECT_NAME/g;s/$BOOTSTRAP_PREFIX/$PREFIX/g" {} +

# The 'Created by' line in the headers of code files
TODAY=$(date "+%m/%d/%y" | sed 's/^0//g;s/\/0/\//')  # sed nastiness is to remove leading zeroes from the date format
find . -type f \( -name "*.m" -o -name "*.h" \) -not \( -path './.git/*' -prune \) -exec sed -i '' "s#Created by .* on [0-9].*#Created by $FULLNAME on $TODAY#g" {} +

# Replace default bundle domain and organization
find . -type f -not \( -path './.git/*' -prune \) -not -path './README.md' -not -path './Podfile' -exec sed -i '' "s/$BOOTSTRAP_ORG/$ORG_NAME/" {} +
find . -type f -not \( -path './.git/*' -prune \) -not -path './README.md' -not -path './Podfile' -exec sed -i '' "s/$BOOTSTRAP_DOMAIN/$BUNDLE_DOMAIN/" {} +

# Remove ignores and build commands that are only relevant in the bootstrap repo itself
sed -i '' '/.*>>>bootstrap-only/,/.*<<<bootstrap-only/d' .gitignore .travis.yml

resetLocale

echo "👍"


### And commit!

echo -n "Committing... "
git add --all
git commit -q -m "[Amaro] Bootstrapped"
echo "👍"


####################
### Get Usable
####################

read -n1 -p "Would you like to edit your Podfile [y/N]? " EDIT_POD
[[ -z "$EDIT_POD" ]] || echo
[[ "$EDIT_POD" == "y" || "$EDIT_POD" == "Y" ]] && edit Podfile


echo -n "Initializing submodules and CocoaPods... "

git submodule -q update --init --recursive
git submodule --quiet foreach 'git checkout -q master'
pod install --silent

git add --all
git rm -q tiramisu.sh
git rm -rq bootstrap-scripts
git commit -q -m "[Amaro] Install pods and remove init script"

echo "👍"


read -n1 -p "Would you like to set up Crashlytics now [Y/n]? " SET_UP_CRASHLYTICS
[[ -z $"SET_UP_CRASHLYTICS" ]] || echo
[[ -z "$SET_UP_CRASHLYTICS" || "$SET_UP_CRASHLYTICS" == "y" || "$SET_UP_CRASHLYTICS" == "Y" ]] && setUpCrashlytics


echo -n "Cleaning up after ourselves... "

# Squash all of our commits together into one, for prettiness
# See: http://stackoverflow.com/questions/1657017/git-squash-all-commits-into-a-single-commit
git reset $(git commit-tree HEAD^{tree} -m "[Amaro] We have liftoff 🚀")

echo "👍"


####################
### All Done
####################

echo -e "\n\n👌️  You're all set! 👌"
echo "Don't forget to open the .xcworkspace, not the .xcodeproject,"
echo "and add some prose to README.md!"
echo -e "\nXOXO -C&L 💋"
echo

read -n1 -p "Would you like to open the project [Y/n]? " OPEN_PROJECT
[[ -z "$OPEN_PROJECT" || "$OPEN_PROJECT" == "y" || "$OPEN_PROJECT" == "Y" ]] && open "$PROJECT_NAME.xcworkspace"
echo
