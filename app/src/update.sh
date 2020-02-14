#!/bin/sh
#
#  update.sh: functions for updating/or creating Epichrome apps
#
#  Copyright (C) 2020  David Marmor
#
#  https://github.com/dmarmor/epichrome
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#


# PATH TO THIS SCRIPT'S EPICHROME APP BUNDLE

updateEpichromePath="${BASH_SOURCE[0]%/Contents/Resources/Scripts/update.sh}"
updateEpichromeRuntime="$updateEpichromePath/Contents/Resources/Runtime"


# BOOTSTRAP MY VERSION OF CORE.SH

source "$updateEpichromeRuntime/Contents/Resources/Scripts/core.sh"
[[ "$?" = 0 ]] || ( echo "$myLogApp: Unable to load core script into update script." >> "$myLogFile" ; exit 1 )


# FUNCTION DEFINITIONS

# UPDATEAPP: function that populates an app bundle
function updateapp { # ( updateAppPath )
    
    # only run if we're OK
    [[ "$ok" ]] || return 1
    
    # set app path
    local updateAppPath="$1" ; shift
    
    
    # LOAD FILTER.SH

    safesource "$updateEpichromeRuntime/Contents/Resources/Scripts/filter.sh"
    [[ "$ok" ]] || return 1
    
    
    # SET UNIQUE APP ID
    
    if [[ ! "$SSBIdentifier" ]] ; then
	
	# no ID found
	
	# see if we can pull it from CFBundleIdentifier
	SSBIdentifier="${CFBundleIdentifier#$appIDBase.}"
	if [[ "$SSBIdentifier" = "$CFBundleIdentifier" ]] ; then
	    
	    # no identifier found, so create a new ID
	    
	    # get max length for SSBIdentifier, given that CFBundleIdentifier
	    # must be 30 characters or less (the extra 1 accounts for the .
	    # we will need to add to the base
	    
	    local maxidlength=$((30 - \
				    ((${#appIDBase} > ${#appEngineIDBase} ? \
						    ${#appIDBase} : \
						    ${#appEngineIDBase} ) + 1) ))
	    
	    # first attempt is to just use the bundle name with
	    # illegal characters removed
	    SSBIdentifier="${CFBundleName//[^-a-zA-Z0-9_]/}"
	    
	    # if trimmed away to nothing, use a default name
	    [ ! "$SSBIdentifier" ] && SSBIdentifier="generic"
	    
	    # trim down to max length
	    SSBIdentifier="${SSBIdentifier::$maxidlength}"
	    
	    # check for any apps that already have this ID
	    
	    # get a length that's the smaller of the length of the
	    # full ID or the max allowed length - 3 to accommodate
	    # adding random digits at the end
	    local idbaselength="${SSBIdentifier::$(($maxidlength - 3))}"
	    idbaselength="${#idbaselength}"
	    
	    # initialize status variables
	    local appidfound=
	    local engineidfound=
	    local randext=
	    
	    # determine if Spotlight is enabled for the root volume
	    local spotlight=$(mdutil -s / 2> /dev/null)
	    if [[ "$spotlight" =~ 'Indexing enabled' ]] ; then
		spotlight=1
	    else
		spotlight=
	    fi
	    
	    # loop until we randomly hit a unique ID
	    while true ; do
		
		if [[ "$spotlight" ]] ; then
		    try 'appidfound=' mdfind \
			"kMDItemCFBundleIdentifier == '$appIDBase.$SSBIdentifier'" \
			'Unable to search system for app bundle identifier.'
		    try 'engineidfound=' mdfind \
			"kMDItemCFBundleIdentifier == '$appEngineIDBase.$SSBIdentifier'" \
			'Unable to search system for engine bundle identifier.'
		    
		    # exit loop on error, or on not finding this ID
		    [[ "$ok" && ( "$appidfound" || "$engineidfound" ) ]] || break
		fi
		
		# try to create a new unique ID
		randext=$(((${RANDOM} * 100 / 3279) + 1000))  # 1000-1999
		
		SSBIdentifier="${SSBIdentifier::$idbaselength}${randext:1:3}"
		
		# if we don't have spotlight we'll just use the first randomly-generated ID
		[[ ! "$spotlight" ]] && break
		
	    done
	    
	    # if we got out of the loop, we have a unique-ish ID (or we got an error)
	fi
    fi
    if [[ ! "$ok" ]] ; then rmtemp "$contentsTmp" 'Contents folder' ; return 1 ; fi
    
    # set app bundle ID
    local myAppBundleID="$appIDBase.$SSBIdentifier"
    
    
    # SET APP VERSION
    
    SSBVersion="$coreVersion"
    
    
    # BEGIN POPULATING APP BUNDLE
    
    # put updated bundle in temporary Contents directory
    local contentsTmp="$(tempname "$updateAppPath/Contents")"
    
    # copy in the boilerplate for the app
    try /bin/cp -PR "$updateEpichromeRuntime/Contents" "$contentsTmp" 'Unable to populate app bundle.'
    if [[ ! "$ok" ]] ; then rmtemp "$contentsTmp" 'Contents folder' ; return 1 ; fi

    # decrypt executable into place
    try /bin/mkdir -p "$contentsTmp/MacOS" \
	'Unable to create app executable directory.'
    try /usr/bin/openssl AES-128-CBC -d -k data \
	-in "$updateEpichromeRuntime/epichrome_data" \
	-out "$contentsTmp/MacOS/Epichrome" \
	'Unable to copy app executable.'
    try /bin/chmod +x "$contentsTmp/MacOS/Epichrome" \
	'Unable to set app executable permissions.'
    
    
    # FILTER APP INFO.PLIST INTO PLACE
    
    # set up default PlistBuddy commands
    local filterCommands=( "set :CFBundleDisplayName $CFBundleDisplayName" \
			       "set :CFBundleName $CFBundleName" \
			       "set :CFBundleIdentifier $myAppBundleID" )
    
    # if not registering as browser, delete URI handlers
    [[ "$SSBRegisterBrowser" = "No" ]] && \
	filterCommands+=( "Delete :CFBundleURLTypes" )
    
    # filter boilerplate Info.plist with info for this app
    filterplist "$updateEpichromeRuntime/Filter/Info.plist" \
		"$contentsTmp/Info.plist" \
		"app Info.plist" \
		"${filterCommands[@]}"


    # FILTER APP MAIN SCRIPT INTO PLACE
    
    filterfile "$updateEpichromeRuntime/Filter/AppExec" \
	       "$contentsTmp/Resources/script" \
	       'app executable' \
	       APPID "$(formatscalar "$SSBIdentifier")" \
	       APPENGINETYPE "$(formatscalar "$SSBEngineType")" \
	       APPDISPLAYNAME "$(formatscalar "$CFBundleDisplayName")" \
	       APPBUNDLENAME "$(formatscalar "$CFBundleName")" \
	       APPCUSTOMICON "$(formatscalar "$SSBCustomIcon")" \
	       APPCOMMANDLINE "$(formatarray "${SSBCommandLine[@]}")"
    
    
    # GET ICON SOURCE

    # determine source of icons
    local iconSourcePath=
    if [[ "$SSBCustomIcon" = Yes ]] ; then
	iconSourcePath="$updateAppPath/Contents/Resources"
    else
	iconSourcePath="$updateEpichromeRuntime/Icons"
    fi
    
    
    # COPY ICONS TO MAIN APP
    
    safecopy "$iconSourcePath/$CFBundleIconFile" \
	     "$contentsTmp/Resources/$CFBundleIconFile" "app icon"
    safecopy "$iconSourcePath/$CFBundleTypeIconFile" \
	     "$contentsTmp/Resources/$CFBundleTypeIconFile" "document icon"
    
    
    # FILTER NATIVE MESSAGING HOST INTO PLACE

    # $$$$ fix display & bundle names to python-escape things
    local updateNMHFile="$contentsTmp/Resources/NMH/$appNMHFile"
    filterfile "$updateEpichromeRuntime/Filter/$appNMHFile" \
	       "$updateNMHFile" \
	       'native messaging host' \
	       APPID "$SSBIdentifier" \
	       APPDISPLAYNAME "$CFBundleDisplayName" \
	       APPBUNDLENAME "$CFBundleName"
    try /bin/chmod 755 "$updateNMHFile" \
	'Unable to set permissions for native messaging host.'

    if [[ ! "$ok" ]] ; then rmtemp "$contentsTmp" 'Contents folder' ; return 1 ; fi


    # POPULATE ENGINE
    
    # path to engine
    local updateEnginePath="$contentsTmp/Resources/Engine"
    
    # create engine directory
    try mkdir -p "$updateEnginePath" 'Unable to create app engine.'

    if [[ "$SSBEngineType" = 'Google Chrome' ]] ; then

	# GOOGLE CHROME ENGINE

	# filter placeholder executable into place
	filterfile "$updateEpichromeRuntime/Engine/Filter/PlaceholderExec" \
		   "$updateEnginePath/PlaceholderExec" \
		   'Google Chrome app engine placeholder executable' \
		   APPID "$(formatscalar "$SSBIdentifier")" \
		   APPBUNDLEID "$(formatscalar "$myAppBundleID")"
	try /bin/chmod 755 "$updateEnginePath/PlaceholderExec" \
	    'Unable to set permissions for Google Chrome app engine placeholder executable.'
	
	# copy in core script
	try /bin/mkdir -p "$updateEnginePath/Scripts" \
	    'Unable to create Google Chrome app engine placeholder scripts.'
	try /bin/cp "$updateEpichromeRuntime/Contents/Resources/Scripts/core.sh" \
	    "$updateEnginePath/Scripts" \
	    'Unable to copy core to Google Chrome app engine placeholder.'

    else
	
	# CHROMIUM ENGINE

	# CREATE PAYLOAD
	
	# copy in main payload
	try /bin/cp -PR "$updateEpichromeRuntime/Engine/Payload" \
	    "$updateEnginePath" \
	    'Unable to populate app engine payload.'

	# path to payload
	local updatePayloadPath="$updateEnginePath/Payload"
	
	# decrypt executable into place
	try /bin/mkdir -p "$updatePayloadPath/MacOS" \
	    'Unable to create app engine payload executable directory.'
	try /usr/bin/openssl AES-128-CBC -d -k data \
	    -in "$updateEpichromeRuntime/Engine/chromium_data" \
	    -out "$updatePayloadPath/MacOS/Chromium" \
	    'Unable to copy app engine payload executable.'
	try /bin/chmod +x "$updatePayloadPath/MacOS/Chromium" \
	    'Unable to set app engine payload executable permissions.'
	
	# filter payload Info.plist into place
	filterplist "$updateEpichromeRuntime/Engine/Filter/Info.plist" \
		    "$updatePayloadPath/Info.plist" \
		"app engine payload Info.plist" \
		"Set :CFBundleDisplayName $CFBundleDisplayName" \
		"Set :CFBundleName $CFBundleName" \
		"Set :CFBundleIdentifier ${appEngineIDBase}.$SSBIdentifier"
	
	# filter localization strings in place
	filterlproj "$updatePayloadPath/Resources" 'app engine' Chromium
	
	# # copy icons to payload  $$$ MOVED TO LAUNCH
	# safecopy "$iconSourcePath/$CFBundleIconFile" \
	# 	 "$updatePayloadPath/Resources/$CFBundleIconFile" \
	# 	 "engine app icon"
	# safecopy "$iconSourcePath/$CFBundleTypeIconFile" \
	# 	 "$updatePayloadPath/Resources/$CFBundleTypeIconFile" \
	# 	 "engine document icon"


	# CREATE PLACEHOLDER
	
	# path to placeholder
	local updatePlaceholderPath="$updateEnginePath/Placeholder"
	
	# make sure placeholder exists
	try /bin/mkdir -p "$updatePlaceholderPath/MacOS" 'Unable to create app engine placeholder.'
	
	# filter placeholder Info.plist from payload
	filterplist "$updatePayloadPath/Info.plist" \
		    "$updatePlaceholderPath/Info.plist" \
		"app engine placeholder Info.plist" \
		'Add :LSUIElement bool true'
	
	# filter placeholder executable into place
	local updatePlaceholderExec="$updatePlaceholderPath/MacOS/Chromium"
	filterfile "$updateEpichromeRuntime/Engine/Filter/PlaceholderExec" \
		   "$updatePlaceholderExec" \
		   'app engine placeholder executable' \
		   APPID "$(formatscalar "$SSBIdentifier")" \
		   APPBUNDLEID "$(formatscalar "$myAppBundleID")"
	try /bin/chmod 755 "$updatePlaceholderExec" \
	    'Unable to set permissions for app engine placeholder executable.'
	
	# # copy Resources directory from payload  $$$$ MOVED TO LAUNCH
	# try /bin/cp -PR "$updatePayloadPath/Resources" "$updatePlaceholderPath" \
	#     'Unable to copy resources from app engine payload to placeholder.'

	# # copy in core script
	# try /bin/mkdir -p "$updatePlaceholderPath/Resources/Scripts" \
	#     'Unable to create app engine placeholder scripts.'
	# try /bin/cp "$updateEpichromeRuntime/Contents/Resources/Scripts/core.sh" \
	#     "$updatePlaceholderPath/Resources/Scripts" \
	#     'Unable to copy core to placeholder.'
    fi
    
    
    # MOVE CONTENTS TO PERMANENT HOME
    
    if [[ "$ok" ]] ; then
	permanent "$contentsTmp" "$updateAppPath/Contents" "app bundle Contents directory"
    else
	# remove temp contents on error
	[[ "$contentsTmp" && -d "$contentsTmp" ]] && rmtemp "$contentsTmp" 'Contents folder'

	# return
	return 1
    fi

    # return code
    [[ "$ok" ]] && return 0 || return 1
}
