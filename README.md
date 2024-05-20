# revanced-builder

A script builder of ReVanced on Magisk for my own usage.

It is also compatible with KernelSU and APatch.

It works for YouTube, YouTube Music, Reddit and Twitter.

Feel free to fork this repo and add your favourite apps and patches to the JSON configuration file.

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
bash revanced.sh <path to base APK file or name of app to download>
```

## Configuration

- By default, ReVanced artifacts will be downloaded from official repos using the latest **prerelease** tag and a Magisk/KernelSU/APatch module will be created at the end.
- If you want to build ReVanced from source, update the `build` element on the `config.json`
- If you want to target another branch while building or using latest artifacts instead of prerelease, update the `branch` element on the `config.json`
- If you **don't** want to generate the module and you are only insterested in the generated APK, update the `module` element on the `config.json`

## Example:

Using a remote APK:
```
bash revanced.sh [youtube|music|reddit|twitter]
```

Using a local APK:
```
bash revanced.sh com.google.android.youtube_v19.11.43.apk
```
