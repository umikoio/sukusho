##########################################################
#                                                        #
# Author: Umiko (https://github.com/umikoio)             #
# Project: Sukusho (https://github.com/umikoio/sukusho)  #
#                                                        #
##########################################################

VERSION="0.1.0"

APP_BUNDLE="sukusho.app"
ZIP_BUNDLE="Sukusho_v$VERSION.zip"
APP_EXE="$APP_BUNDLE/Contents/MacOS/Sukusho"

function build_app() {
    swiftc Sources/Sukusho/Core.swift Sources/Sukusho/Main.swift \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework AppKit -framework SwiftUI -framework CoreGraphics -framework Carbon \
    -o Sukusho
}

function configure_icon() {
    mkdir -p tmp.iconset
    sips -z 16 16 assets/AppIcon.png --out tmp.iconset/icon_16x16.png
    sips -z 32 32 assets/AppIcon.png --out tmp.iconset/icon_16x16@2x.png
    sips -z 32 32 assets/AppIcon.png --out tmp.iconset/icon_32x32.png
    sips -z 64 64 assets/AppIcon.png --out tmp.iconset/icon_32x32@2x.png
    sips -z 128 128 assets/AppIcon.png --out tmp.iconset/icon_128x128.png
    sips -z 256 256 assets/AppIcon.png --out tmp.iconset/icon_128x128@2x.png
    sips -z 256 256 assets/AppIcon.png --out tmp.iconset/icon_256x256.png
    sips -z 512 512 assets/AppIcon.png --out tmp.iconset/icon_256x256@2x.png
    sips -z 512 512 assets/AppIcon.png --out tmp.iconset/icon_512x512.png
    cp assets/AppIcon.png tmp.iconset/icon_512x512@2x.png
    iconutil -c icns tmp.iconset -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf tmp.iconset

    if [[ ! -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]]; then
        echo "Successfully built icons"
    fi
}

function generate_bundle() {
    if [[ -d "$APP_BUNDLE" ]]; then
        echo "Removing outdated app bundle directory"
        rm -r $APP_BUNDLE
    fi

    if [[ ! -d "$APP_BUNDLE" ]]; then
        echo "Creating fresh app bundle directory"
        mkdir $APP_BUNDLE
    fi

    echo "Seting up bundle environment"
    mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
    cp -f Info.plist "$APP_BUNDLE/Contents/"

    echo "Building icons"
    configure_icon

    echo "Building application"
    build_app

    if [[ -f "Sukusho" ]]; then
        mv Sukusho "$APP_EXE"
        chmod +x "$APP_EXE"
    fi

    echo "Successfully built $APP_BUNDLE"

    if [[ $1="--zip" ]]; then
        echo "Zipping for release"
        zip -r "$ZIP_BUNDLE" "$APP_BUNDLE"
    fi
}

generate_bundle
