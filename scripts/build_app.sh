#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

if [ -z "$DEVELOPER_DIR" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [ -n "$GITHUB_REF_NAME" ]; then
    VERSION="${GITHUB_REF_NAME#v}"
else
    VERSION="${VERSION:-2.0.9}"
fi
BUILD_NUMBER="${BUILD_NUMBER:-1}"

echo "==> Building Pulsar v${VERSION} in release mode..."
swift build -c release

APP_NAME="Pulsar"
APP_BUNDLE="$PROJECT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creating macOS App Bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 拷贝二进制执行文件
cp "$PROJECT_DIR/.build/release/Pulsar" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# 拷贝 Pulsar 官方图标
if [ -f "$PROJECT_DIR/Resources/AppIcon_Pulsar.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon_Pulsar.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# 拷贝或下载嵌入式 grpcurl 执行引擎 (保障开箱即用真实网络调用能力)
mkdir -p "$RESOURCES_DIR/bin"
if [ -f "$PROJECT_DIR/Resources/bin/grpcurl" ]; then
    cp "$PROJECT_DIR/Resources/bin/grpcurl" "$RESOURCES_DIR/bin/grpcurl"
elif [ -f "/tmp/grpcurl" ]; then
    cp "/tmp/grpcurl" "$RESOURCES_DIR/bin/grpcurl"
elif command -v grpcurl >/dev/null 2>&1; then
    cp "$(command -v grpcurl)" "$RESOURCES_DIR/bin/grpcurl"
else
    echo "==> Downloading grpcurl binary for embedding..."
    curl -sL https://github.com/fullstorydev/grpcurl/releases/download/v1.9.2/grpcurl_1.9.2_osx_arm64.tar.gz | tar -xz -C "$RESOURCES_DIR/bin"
fi
chmod +x "$RESOURCES_DIR/bin/grpcurl"


# 生成 Info.plist
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.lucklyt.pulsar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Pulsar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# 清理可能存在的临时属性与隔离标志
xattr -cr "$APP_BUNDLE" 2>/dev/null || xattr -c "$APP_BUNDLE" 2>/dev/null || true
find "$APP_BUNDLE" -exec xattr -c {} + 2>/dev/null || true

echo "==> Code signing ${APP_NAME}.app (Ad-Hoc with deep resource sealing)..."
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Successfully packaged and signed ${APP_NAME}.app at: $APP_BUNDLE"

if [ "$1" = "--dmg" ] || [ "$1" = "--package" ] || [ -n "$PACKAGE" ]; then
    echo "==> Packaging DMG and ZIP installers..."
    cd "$PROJECT_DIR/build"
    rm -f "${APP_NAME}-macOS-arm64.zip" "${APP_NAME}-macOS-arm64.dmg"

    # 1. 压缩 ZIP 便携包
    zip -r -y "${APP_NAME}-macOS-arm64.zip" "${APP_NAME}.app"

    # 2. 组装 DMG Staging 镜像目录 (包含拖拽安装快捷方式与辅助工具)
    DMG_STAGING="$PROJECT_DIR/build/dmg_staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"

    # 拷贝已签名的 App
    cp -R "${APP_NAME}.app" "$DMG_STAGING/"

    # 创建 Applications 软链接快捷方式 (提示用户拖拽安装)
    ln -s /Applications "$DMG_STAGING/Applications"

    # 拷贝双击修复脚本与使用指引
    if [ -f "$PROJECT_DIR/Resources/无法打开请双击修复.command" ]; then
        cp "$PROJECT_DIR/Resources/无法打开请双击修复.command" "$DMG_STAGING/"
        chmod +x "$DMG_STAGING/无法打开请双击修复.command"
    fi
    if [ -f "$PROJECT_DIR/Resources/安装与打开说明.txt" ]; then
        cp "$PROJECT_DIR/Resources/安装与打开说明.txt" "$DMG_STAGING/"
    fi

    # 清除 staging 中可能的扩展属性
    xattr -cr "$DMG_STAGING" 2>/dev/null || xattr -c "$DMG_STAGING" 2>/dev/null || true
    find "$DMG_STAGING" -exec xattr -c {} + 2>/dev/null || true

    # 生成包含拖拽快捷方式的全新 DMG 镜像
    hdiutil create -volname "${APP_NAME}" -srcfolder "$DMG_STAGING" -ov -format UDZO "${APP_NAME}-macOS-arm64.dmg"
    rm -rf "$DMG_STAGING"

    echo "==> Package installers created in $PROJECT_DIR/build:"
    ls -lh "${APP_NAME}-macOS-arm64".*
fi

echo "You can open it now by running: open $APP_BUNDLE"
