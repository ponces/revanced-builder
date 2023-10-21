# revanced-builder
A script builder of ReVanced on Magisk for my own usage.

It works for YouTube, YouTube Music and Reddit.

Feel free to fork this repo and add your favourite apps and patches to the JSON file.

## Pre-Requisites
- Linux
- Java 17
- git
- curl
- wget
- aapt2
- jq

## Usage:
```
bash revanced.sh <path to base APK file or name of app to download> <options>
```

## Examples:

Downloading the APK:
```
bash revanced.sh [youtube|music|reddit]
```

Using local APK:
```
bash revanced.sh $HOME/base.apk
```

Using local APK and building ReVanced from source:
```
bash revanced.sh $HOME/base.apk --build
```

Using local APK and generating a Magisk module with the output:
```
bash revanced.sh $HOME/base.apk --magisk
```

Using a local APK and pre-release ReVanced binaries:
```
bash revanced.sh $HOME/base.apk --dev
```
