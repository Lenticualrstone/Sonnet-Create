#!/bin/bash
# Sonnet Create — 언어별 가이드(튜토리얼) 프로젝트 빌드 스크립트.
# ko/ja/en 각각 GuideProjectGenerator로 생성 → .scproj로 압축 →
# 해당 버전의 GitHub 릴리스에 자산으로 첨부한다 (build-dmg.sh의 DMG 업로드와 동일한 패턴).
# 앱의 "가이드 프로젝트 생성" 버튼은 이 자산을 받아 워크스페이스로 가져온다.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep 'MARKETING_VERSION' App/project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
REPO="Lenticualrstone/Sonnet-Create"

echo "==> Sonnet Create $VERSION 가이드 프로젝트 빌드 시작"

rm -rf dist/guide-build
mkdir -p dist/guide-build dist

LANGS=(ko ja en)
ASSETS=()

for lang in "${LANGS[@]}"; do
  echo "==> [$lang] 생성"
  outdir="dist/guide-build/$lang"
  mkdir -p "$outdir"
  whatsnew="Scripts/GuideProjectContent/whatsnew-$lang.md"
  if [ -f "$whatsnew" ]; then
    swift run --package-path Scripts/GuideProjectGenerator GuideProjectGenerator "$(pwd)/$outdir" "$lang" "$(pwd)/$whatsnew"
  else
    swift run --package-path Scripts/GuideProjectGenerator GuideProjectGenerator "$(pwd)/$outdir" "$lang"
  fi

  projectDir=$(find "$outdir" -mindepth 1 -maxdepth 1 -type d | head -1)
  if [ -z "$projectDir" ]; then
    echo "error: [$lang] 생성된 프로젝트 폴더를 찾지 못했습니다" >&2
    exit 1
  fi

  assetPath="dist/SonnetCreate-Guide-$lang.scproj"
  rm -f "$assetPath"
  /usr/bin/ditto -ck --sequesterRsrc "$projectDir" "$assetPath"
  ASSETS+=("$assetPath")
  echo "    -> $assetPath"
done

echo "==> GitHub 릴리스에 가이드 프로젝트 첨부"
if command -v gh >/dev/null 2>&1 && gh release view "v${VERSION}" -R "$REPO" >/dev/null 2>&1; then
  gh release upload "v${VERSION}" "${ASSETS[@]}" -R "$REPO" --clobber
  echo "    업로드 완료 → https://github.com/$REPO/releases/tag/v${VERSION}"
else
  echo "    (gh 미설치 또는 v${VERSION} 릴리스 없음 — 업로드 건너뜀)"
fi

echo "==> 완료"
