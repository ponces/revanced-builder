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

if [ ! -f "$PWD/config.json" ]; then
    echo
    echo "--!> No app info file found!"
    echo
    echo "Exiting..."
    echo
    exit 1
fi

if [ ! -f "$HOME/.gradle/gradle.properties" ]; then
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
    exit 1
fi

clean() {
    rm -rf "$outDir"
    rm -rf $HOME/.local/share/apktool
}

getAppInfo() {
    filter=".id==\"$1\""
    if [ -f "$1" ]; then
        filter=".packageName==\"$1\""
    fi

    app=$(cat "$PWD"/config.json | jq -rc ".[] | select($filter)")
    id=$(echo $app | jq -rc ".id")
    packageName=$(echo $app | jq -rc ".packageName")
    moduleId=$(echo $app | jq -rc ".moduleId")
    moduleName=$(echo $app | jq -rc ".moduleName")
    branch=$(echo $app | jq -rc ".branch")
    build=$(echo $app | jq -rc ".build")
    magisk=$(echo $app | jq -rc ".magisk")
    integrations=$(echo $app | jq -rc ".integrations")
    patchOptions=$(echo $app | jq -rc ".patchOptions")
    patches=$(echo $app | jq -rc ".patches[]")

    options=""
    if [[ "$integrations" == "true" ]]; then
        options+="-m $outDir/revanced-integrations.apk"
    fi
    while IFS= read -r patch; do
        options+=" -i \"$patch\""
    done <<< "$patches"
}

getLastVersion() {
    if [[ "$packageName" == "com.google.android.youtube" ]]; then
        compatVersion=$(eval curl -s "https://api.revanced.app/v2/patches/latest" | \
            jq -rc "[.patches[] | select(.compatiblePackages[0].name==\"$packageName\" and \
                     .compatiblePackages[0].versions != null)] | first | .compatiblePackages[0].versions | last")
        downVersion="phone-$compatVersion-apk"
    else
        downVersion="phone-apk"
    fi
}

downloadApk() {
    getLastVersion
    link=$(eval curl -s "https://apkcombo.com/$id/$packageName/download/$downVersion" | grep "arm64-v8a" -A10 | \
        grep -oPm1 "(?<=href=\")https://download.apkcombo.com/.*?(?=\")")\&$(curl -s "https://apkcombo.com/checkin")
    wget -q "$link" -O "$outDir"/original.apk || true
    if [ ! -f "$outDir"/original.apk ] || [ ! -s "$outDir"/original.apk ]; then
        link=$(eval curl -s -A "Mozilla/5.0 \(X11\; Linux x86_64\; rv:60.0\) Gecko/20100101 Firefox/81.0" \
            "https://d.apkpure.com/b/APK/$packageName?version=latest" | sed -n 's/.*href="\([^"]*\).*/\1/p' | sed 's/\&amp;/\&/g')
        wget -q "$link" -O "$outDir"/original.apk || true
    fi
}

getApkInfo() {
    applicationName=$(aapt2 dump badging "$1" | grep "application-label:" | sed -e "s/.*application-label:'//" -e "s/'.*//")
    outVersion=$(aapt2 dump badging "$1" | grep versionName | sed -e "s/.*versionName='//" -e "s/' .*//")
    echo "    - Application: $applicationName"
    echo "    - Package: $packageName"
    echo "    - Version: $outVersion"
}

buildRepo() {
    git clone -q https://github.com/"$1"/"$2" -b "$3" "$outDir"/repos/"$2"
    pushd "$outDir"/repos/"$2" >/dev/null
    patchRepo "$2"
    bash ./gradlew "$4"
    popd >/dev/null
    cp "$outDir"/repos/"$2"/app/build/outputs/apk/release/*.apk "$5" 2>/dev/null || true
    cp "$outDir"/repos/"$2"/build/libs/*.jar "$5" 2>/dev/null || true
    cp "$outDir"/repos/"$2"/build/libs/*-all.jar "$5" 2>/dev/null || true
    rm -rf "$outDir"/repos/"$2"
}

patchRepo() {
    echo
}

downloadBins() {
    if [[ "$3" == "dev" ]]; then
        link=$(curl -s https://api.github.com/repos/"$1"/"$2"/releases | \
            jq --raw-output '.[0].assets[] | .browser_download_url | select(endswith(".apk") or endswith(".jar"))')
    else
        link=$(curl -s https://api.github.com/repos/"$1"/"$2"/releases/latest | \
            jq --raw-output '.assets[] | .browser_download_url | select(endswith(".apk") or endswith(".jar"))')
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
              --resource-cache "$outDir"/tmp \
              --force "$baseApk"
}

buildMagisk() {
    detachBin="detach-$id"
    mkdir -p "$outDir"/magisk/META-INF/com/google/android
    mkdir -p "$outDir"/magisk/common
    mkdir -p "$outDir"/magisk/common/cron
    mkdir -p "$outDir"/magisk/system/bin
    cp "$baseApk" "$outDir"/magisk/common/original.apk
    cp "$outDir"/revanced.apk "$outDir"/magisk/common/revanced.apk
    echo "#MAGISK" > "$outDir"/magisk/META-INF/com/google/android/updater-script
    wget -q https://github.com/topjohnwu/Magisk/raw/master/scripts/module_installer.sh -O "$outDir"/magisk/META-INF/com/google/android/update-binary
    {
        echo "id=$moduleId"
        echo "name=$moduleName"
        echo "version=$outVersion"
        echo "versionCode=$(echo $outVersion | sed 's/\.//g')"
        echo "author=ReVanced"
        echo "description=Continuing the legacy of Vanced"
    } > "$outDir"/magisk/module.prop
    {
        echo "#!/system/bin/sh"
        echo "[ \"\$BOOTMODE\" == \"false\" ] && abort \"Installation failed! ReVanced must be installed via Magisk Manager!\""
        echo "versionName=\$(dumpsys package $packageName | grep versionName | awk -F\"=\" '{print \$2}')"
        echo "[[ \"\$versionName\" != \"$outVersion\" ]] && pm install -r \$MODPATH/common/original.apk"
    } > "$outDir"/magisk/customize.sh
    {
        echo "#!/system/bin/sh"
        echo "stock_path=\$(pm path $packageName | grep base | sed 's/package://g')"
        echo "[ ! -z \$stock_path ] && umount -l \$stock_path"
    } > "$outDir"/magisk/post-fs-data.sh
    {
        echo "#!/system/bin/sh"
        echo "while [ \"\$(getprop sys.boot_completed | tr -d '\r')\" != \"1\" ]; do sleep 1; done"
        echo "MODPATH=\${0%/*}"
        echo "base_path=\$MODPATH/common/revanced.apk"
        echo "stock_path=\$(pm path $packageName | grep base | sed 's/package://g')"
        echo "if [ ! -z \$stock_path ]; then"
        echo "    mount -o bind \$base_path \$stock_path"
        echo "    chcon u:object_r:apk_data_file:s0 \$base_path"
        echo "    sleep 10"
        echo "    /data/adb/magisk/busybox crond -b -c \$MODPATH/common/cron"
        echo "fi"
    } > "$outDir"/magisk/service.sh
    echo "0 */1 * * * /system/bin/$detachBin" > "$outDir"/magisk/common/cron/root
    {
        echo "#!/system/bin/sh"
        echo "lib_db=/data/data/com.android.vending/databases/library.db"
        echo "app_db=/data/data/com.android.vending/databases/localappstate.db"
        echo "am force-stop com.android.vending"
        echo "sqlite3 \$lib_db \"UPDATE ownership SET doc_type = '25' WHERE doc_id = '$packageName'\""
        echo "sqlite3 \$app_db \"UPDATE appstate SET auto_update = '2' WHERE package_name = '$packageName'\""
        echo "rm -rf /data/data/com.android.vending/cache"
    } > "$outDir"/magisk/system/bin/$detachBin
    pushd "$outDir"/magisk >/dev/null
    zip -qr "$outDir"/../"$moduleId"_v"$outVersion".zip *
    popd >/dev/null
}

echo
echo "--> Starting"
clean
mkdir -p "$outDir"

echo
echo "--> Getting application info"
getAppInfo "$1"

if [ -f "$1" ]; then
    baseApk="$1"
else
    echo
    echo "--> Downloading APK"
    downloadApk
    baseApk="$outDir"/original.apk
fi
getApkInfo "$baseApk"

if [ -f "$baseApk" ] && [ -s "$baseApk" ]; then
    if [[ "$build" == "true" ]]; then
        echo
        echo "--> Building revanced-patcher"
        buildRepo revanced revanced-patcher "$branch" build "$outDir"/revanced-patcher.jar

        echo
        echo "--> Building revanced-cli"
        buildRepo revanced revanced-cli "$branch" build "$outDir"/revanced-cli.jar

        echo
        echo "--> Building revanced-patches"
        buildRepo revanced revanced-patches "$branch" build "$outDir"/revanced-patches.jar

        if [[ "$integrations" == "true" ]]; then
            echo
            echo "--> Building revanced-integrations"
            buildRepo revanced revanced-integrations "$branch" assembleRelease "$outDir"/revanced-integrations.apk
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
        if [[ "$magisk" == "true" ]]; then
            echo
            echo "--> Building Magisk module"
            buildMagisk
        else
            cp "$outDir"/revanced.apk "$outDir"/../"$moduleId"_v"$outVersion".apk
        fi
    else
        echo
        echo "--!> Patching APK failed!"
    fi
else
    echo
    echo "--!> No valid APK was found!"
fi

echo
echo "--> Finishing"
clean
echo
