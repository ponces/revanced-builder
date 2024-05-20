#!/bin/bash

echo
echo "---------------------------------"
echo "         ReVanced Builder        "
echo "               by                "
echo "             ponces              "
echo "---------------------------------"

set -e

export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
export PATH=$JAVA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$JAVA_HOME/lib:$LD_LIBRARY_PATH

outDir="$PWD/out"

clean() {
    rm -rf "$outDir"
    rm -rf $HOME/.local/share/apktool
}

getAppInfo() {
    filter=".id==\"$1\""
    if [ -f "$1" ]; then
        filter=".packageName==\"$1\""
    fi

    app=$(cat "$PWD"/config.json | jq -r ".[] | select($filter)")
    id=$(echo $app | jq -r ".id")
    org=$(echo $app | jq -r ".org")
    version=$(echo $app | jq -r ".version")
    moduleName=$(echo $app | jq -r ".moduleName")
    branch=$(echo $app | jq -r ".branch")
    build=$(echo $app | jq -r ".build")
    module=$(echo $app | jq -r ".module")
    integrations=$(echo $app | jq -r ".integrations")
    patchOptions=$(echo $app | jq -r ".patchOptions")
    patches=$(echo $app | jq -r ".patches[]")

    options=""
    if [[ "$integrations" == "true" ]]; then
        options+="-m $outDir/revanced-integrations.apk"
    fi
    while IFS= read -r patch; do
        options+=" -i \"$patch\""
    done <<< "$patches"
}

getDownloadVersion() {
    if [[ "$version" == "compatible" ]]; then
        lastTag=$(curl -s https://api.github.com/repos/revanced/revanced-patches/releases | \
                jq -r 'map(select(.prerelease)) | first | .tag_name')
        if [[ "$id" == "youtube" ]]; then
            downVersion=$(curl -s "https://api.revanced.app/v2/patches/$lastTag" | \
                          jq -r "[.patches[] | select(.compatiblePackages[0].name==\"com.google.android.youtube\" and \
                                  .compatiblePackages[0].versions != null)] | first | .compatiblePackages[0].versions | last")
        fi
    else
        downVersion="$version"
    fi
}

downloadApk() {
    getDownloadVersion
    downFile="./downloads/original.apk"
    if [[ "$downVersion" != "latest" ]]; then
        versionFilter=",\"version\":\"$downVersion\""
    fi
    mkdir "$outDir"/down
    pushd "$outDir"/down &>/dev/null
    wget -q https://github.com/tanishqmanuja/apkmirror-downloader/releases/latest/download/apkmd && chmod +x apkmd
    json="{\"options\":{\"arch\":\"arm64-v8a\"},\"apps\":[{\"name\":\"original\",\"org\":\"$org\",\"repo\":\"$id\"$versionFilter}]}"
    echo "$json" | ./apkmd /dev/stdin &>/dev/null
    if [ ! -f "$downFile" ] || [ ! -s "$downFile" ]; then
        json="{\"options\":{\"arch\":\"universal\"},\"apps\":[{\"name\":\"original\",\"org\":\"$org\",\"repo\":\"$id\"$versionFilter}]}"
        echo "$json" | ./apkmd /dev/stdin &>/dev/null
    fi
    if [ -f "$downFile" ] && [ -s "$downFile" ]; then
        cp "$downFile" "$outDir"/original.apk
    fi
    popd &>/dev/null
}

getApkInfo() {
    apkInfo=$(aapt2 dump badging "$1")
    applicationName=$(echo "$apkInfo" | grep "application-label:" | sed -e "s/.*application-label:'//" -e "s/'.*//")
    packageName=$(echo "$apkInfo" | grep name | sed -e "s/.* name='//" -e "s/' .*//" | head -1)
    outVersion=$(echo "$apkInfo" | grep versionName | sed -e "s/.* versionName='//" -e "s/' .*//" | head -1)
    echo "  - Application: $applicationName"
    echo "  - Package: $packageName"
    echo "  - Version: $outVersion"
}

buildRepo() {
    git clone -q https://github.com/"$1"/"$2" -b "$3" "$outDir"/repos/"$2"
    pushd "$outDir"/repos/"$2" >/dev/null
    patchRepo "$2"
    [[ "$2" == "revanced-integrations" ]] && bash ./gradlew assembleRelease || bash ./gradlew build
    popd >/dev/null
    cp "$outDir"/repos/"$2"/app/build/outputs/apk/release/*.apk "$4" 2>/dev/null || true
    cp "$outDir"/repos/"$2"/build/libs/*.jar "$4" 2>/dev/null || true
    cp "$outDir"/repos/"$2"/build/libs/*-all.jar "$4" 2>/dev/null || true
    rm -rf "$outDir"/repos/"$2"
}

patchRepo() {
    echo
}

downloadBins() {
    if [[ "$3" == "dev" ]]; then
        link=$(curl -s https://api.github.com/repos/"$1"/"$2"/releases | \
               jq -r '.[0].assets[] | .browser_download_url | select(endswith(".apk") or endswith(".jar"))')
    else
        link=$(curl -s https://api.github.com/repos/"$1"/"$2"/releases/latest | \
               jq -r '.assets[] | .browser_download_url | select(endswith(".apk") or endswith(".jar"))')
    fi
    wget -q $link -O "$4" || true
    if [ ! -f "$4" ] || [ ! -s "$4" ]; then
        echo "--!> No valid release of $2 was found!"
    fi
}

patchApk() {
    mkdir -p "$outDir"/tmp
    echo "$patchOptions" > "$outDir"/options.json
    echo
    eval java -jar "$outDir"/revanced-cli.jar patch \
              --patch-bundle "$outDir"/revanced-patches.jar \
              --options "$outDir"/options.json \
              --exclusive "$options" \
              --out "$outDir"/revanced.apk \
              --temporary-files-path "$outDir"/tmp \
              --force --warn "$baseApk" 2>&1 | tee "$outDir"/revanced.log
    if grep -q -e WARN -e SEVERE "$outDir"/revanced.log; then
        rm -f "$outDir"/revanced.apk
    fi
}

downloadDetach() {
    link=$(curl -s https://api.github.com/repos/j-hc/zygisk-detach/releases/latest | \
               jq -r '.assets[] | .browser_download_url | select(endswith(".zip"))')
    wget -q $link -O "$outDir"/detach.zip
    unzip -q "$outDir"/detach.zip -d "$outDir"/detach
    cp "$outDir"/detach/system/bin/detach-arm64 "$outDir"/module/system/bin/detach
    cp -r "$outDir"/detach/zygisk "$outDir"/module
}

buildModule() {
    moduleId="revanced-$id"
    mkdir -p "$outDir"/module/META-INF/com/google/android
    mkdir -p "$outDir"/module/common
    mkdir -p "$outDir"/module/system/bin
    downloadDetach
    cp "$baseApk" "$outDir"/module/common/original.apk
    cp "$outDir"/revanced.apk "$outDir"/module/common/revanced.apk
    echo "#MAGISK" > "$outDir"/module/META-INF/com/google/android/updater-script
    wget -q https://github.com/topjohnwu/Magisk/raw/master/scripts/module_installer.sh -O "$outDir"/module/META-INF/com/google/android/update-binary
    echo "$packageName" >> "$outDir"/module/detach.txt
    tee "$outDir"/module/module.prop >/dev/null << EOF
id=$moduleId
name=$moduleName
version=$outVersion
versionCode=$(echo $outVersion | sed 's/\.//g')
author=ReVanced
description=Continuing the legacy of Vanced
EOF
    tee "$outDir"/module/customize.sh >/dev/null << EOF
#!/system/bin/sh
[ "\$BOOTMODE" == "false" ] && abort "Installation failed! Module must be installed via module manager!"
versionName=\$(dumpsys package $packageName | grep versionName | awk -F"=" '{print \$2}')
[[ "\$versionName" != "$outVersion" ]] && pm install -r \$MODPATH/common/original.apk
[ -f /system/bin/detach ] && [ ! -f \$NVBASE/modules/$moduleId/system/bin/detach ] && rm -rf \$MODPATH/system
DMODPATH=/data/adb/modules/zygisk-detach
mkdir -p \$DMODPATH
touch \$DMODPATH/disable
grep -q "$packageName" \$DMODPATH/detach.txt || echo "$packageName" >> \$DMODPATH/detach.txt
detach --serialize \$DMODPATH/detach.txt \$DMODPATH/detach.bin
EOF
    tee "$outDir"/module/post-fs-data.sh >/dev/null << EOF
#!/system/bin/sh
stock_path=\$(pm path $packageName | grep base | sed 's/package://g')
[ ! -z \$stock_path ] && umount -l \$stock_path
EOF
    tee "$outDir"/module/service.sh >/dev/null << EOF
#!/system/bin/sh
while [ "\$(getprop sys.boot_completed | tr -d '\r')" != "1" ]; do sleep 1; done
MODPATH=\${0%/*}
base_path=\$MODPATH/common/revanced.apk
stock_path=\$(pm path $packageName | grep base | sed 's/package://g')
if [ ! -z \$stock_path ]; then
    mount -o bind \$base_path \$stock_path
    chcon u:object_r:apk_data_file:s0 \$base_path
fi
EOF
    pushd "$outDir"/module >/dev/null
    zip -qr "$outDir"/../"$moduleId"_v"$outVersion".zip *
    popd >/dev/null
}

echo
echo "--> Starting"
clean
mkdir -p "$outDir"

if [ ! -f "$PWD/config.json" ]; then
    echo
    echo "--!> No app info file found!"
    echo
    echo "Exiting..."
    echo
    clean
    exit 1
fi

echo
echo "--> Getting application info"
getAppInfo "$1"

if [[ "$build" == "true" ]] && [ ! -f "$HOME/.gradle/gradle.properties" ]; then
    echo
    echo "You need to create a Github PAT token with the link below and add it to ~/.gradle/gradle.properties"
    echo "https://github.com/settings/tokens/new?scopes=read:packages&description=ReVanced"
    echo
    echo "Example:"
    echo " $ cat ~/.gradle/gradle.properties"
    echo " gpr.user = <github username>"
    echo " gpr.key = <token>"
    echo
    echo "Exiting..."
    echo
    clean
    exit 1
fi

if [ -f "$1" ]; then
    baseApk="$1"
else
    echo
    echo "--> Downloading APK"
    downloadApk
    baseApk="$outDir"/original.apk
fi

if [ -f "$baseApk" ] && [ -s "$baseApk" ]; then
    getApkInfo "$baseApk"
    if [[ "$build" == "true" ]]; then
        echo
        echo "--> Building revanced-patcher"
        buildRepo revanced revanced-patcher "$branch" "$outDir"/revanced-patcher.jar

        echo
        echo "--> Building revanced-cli"
        buildRepo revanced revanced-cli "$branch" "$outDir"/revanced-cli.jar

        echo
        echo "--> Building revanced-patches"
        buildRepo revanced revanced-patches "$branch" "$outDir"/revanced-patches.jar

        if [[ "$integrations" == "true" ]]; then
            echo
            echo "--> Building revanced-integrations"
            buildRepo revanced revanced-integrations "$branch" "$outDir"/revanced-integrations.apk
        fi
    else
        echo
        echo "--> Downloading revanced-cli"
        downloadBins revanced revanced-cli "$branch" "$outDir"/revanced-cli.jar

        echo
        echo "--> Downloading revanced-patches"
        downloadBins revanced revanced-patches "$branch" "$outDir"/revanced-patches.jar

        if [[ "$integrations" == "true" ]]; then
            echo
            echo "--> Downloading revanced-integrations"
            downloadBins revanced revanced-integrations "$branch" "$outDir"/revanced-integrations.apk
        fi
    fi

    echo
    echo "--> Patching APK"
    patchApk

    if [ -f "$outDir"/revanced.apk ]; then
        if [[ "$module" == "true" ]]; then
            echo
            echo "--> Building ReVanced module"
            buildModule
        else
            cp "$outDir"/revanced.apk "$outDir"/../"$moduleId"_v"$outVersion".apk
        fi
    else
        echo
        echo "--!> Patching APK failed!"
    fi
else
    echo
    echo "--!> No valid APK was downloaded or found!"
fi

echo
echo "--> Finishing"
clean
echo
