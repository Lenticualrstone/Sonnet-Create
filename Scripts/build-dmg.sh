#!/bin/bash
# Sonnet Create — 배포용 DMG 빌드 스크립트.
# 1) Release 빌드 → 2) DMG 배경/볼륨 아이콘 준비 → 3) create-dmg로 패키징 → 4) 체크섬 기록.
# 튜토리얼(가이드) 프로젝트는 더 이상 DMG에 번들하지 않는다 — Scripts/build-guide-projects.sh로
# 별도 빌드해 GitHub 릴리스 자산으로 올리면, 앱의 "가이드 프로젝트 생성" 버튼이 내려받는다.
# 결과물은 전부 dist/ (gitignore됨)에 생성되며, DMG 자체는 저장소에 커밋하지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg가 설치되어 있지 않습니다. 'brew install create-dmg' 실행 후 다시 시도하세요." >&2
  exit 1
fi

VERSION=$(grep 'MARKETING_VERSION' App/project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
APP_NAME="SonnetCreate"
VOL_NAME="Sonnet Create $VERSION"
DMG_PATH="dist/Sonnet Create $VERSION.dmg"

echo "==> Sonnet Create $VERSION DMG 빌드 시작"

rm -rf dist/build dist/dmg-root dist/dmg-assets "dist/Sonnet Create $VERSION.dmg"
mkdir -p dist/dmg-root dist/dmg-assets

echo "==> 1/4 xcodegen"
(cd App && xcodegen generate)

echo "==> 2/4 Release 빌드 (애드혹 서명 — Developer ID 미보유, 개인 배포용)"
xcodebuild \
  -workspace SonnetCreate.xcworkspace \
  -scheme SonnetCreate \
  -configuration Release \
  -derivedDataPath dist/build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build

cp -R "dist/build/Build/Products/Release/${APP_NAME}.app" dist/dmg-root/
cp "Scripts/dmg-assets/Read Me.txt" dist/dmg-root/

echo "==> 3/4 배경 이미지 + 볼륨 아이콘"
python3 Scripts/dmg-assets/make_background.py

mkdir -p dist/dmg-assets/VolumeIcon.iconset
cp App/SonnetCreate/Assets.xcassets/AppIcon.appiconset/icon_*.png dist/dmg-assets/VolumeIcon.iconset/
iconutil -c icns dist/dmg-assets/VolumeIcon.iconset -o dist/dmg-assets/VolumeIcon.icns

echo "==> 4/4 DMG 패키징"
create-dmg \
  --volname "$VOL_NAME" \
  --volicon "dist/dmg-assets/VolumeIcon.icns" \
  --background "dist/dmg-assets/background.png" \
  --window-pos 200 120 \
  --window-size 700 460 \
  --icon-size 96 \
  --text-size 12 \
  --icon "${APP_NAME}.app" 220 160 \
  --app-drop-link 480 160 \
  --icon "Read Me.txt" 350 330 \
  --hide-extension "${APP_NAME}.app" \
  --no-internet-enable \
  "$DMG_PATH" \
  "dist/dmg-root/"

shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"
echo "==> 완료: $DMG_PATH"

# GitHub 릴리스에 DMG 첨부 — 앱 내 업데이트의 '다운로드 및 열기' 경로가 이 자산을 쓴다.
#    해당 버전의 릴리스가 이미 있을 때만 업로드한다 (릴리스 생성은 별도 단계).
echo "==> GitHub 릴리스에 DMG 첨부"
REPO="Lenticualrstone/Sonnet-Create"
if command -v gh >/dev/null 2>&1 && gh release view "v${VERSION}" -R "$REPO" >/dev/null 2>&1; then
  gh release upload "v${VERSION}" "$DMG_PATH" "$DMG_PATH.sha256" -R "$REPO" --clobber
  echo "    업로드 완료 → https://github.com/$REPO/releases/tag/v${VERSION}"
else
  echo "    (gh 미설치 또는 v${VERSION} 릴리스 없음 — 업로드 건너뜀)"
fi
