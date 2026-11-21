#!/usr/bin/env bash
# Yeni sürüm yayınlar: ./scripts/release.sh 0.2.0 ["Sürüm notları"]
# Uygulamayı derler, zip'ler ve GitHub Release olarak yükler. Uygulama içi güncelleyici bu zip'i indirir.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:?Kullanım: ./scripts/release.sh <sürüm> [notlar]}"
NOTES="${2:-}"
ZIP="build/FCleaner-${VERSION}.zip"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "❌ Commit edilmemiş değişiklikler var." >&2
    exit 1
fi

# Etiket, zip'in derlendiği commit'e bağlanır; bunun için commit'in GitHub'da olması gerekir.
COMMIT="$(git rev-parse HEAD)"
git push origin HEAD

swift test
VERSION="$VERSION" ./scripts/build-app.sh

rm -f "$ZIP"
ditto -c -k --keepParent build/FCleaner.app "$ZIP"

# Notlar verilmediyse CHANGELOG.md'deki ilgili bölüm kullanılır.
if [[ -z "$NOTES" ]]; then
    NOTES="$(awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" {found=1; next} found && /^## \[/ {exit} found' CHANGELOG.md)"
fi

if [[ -n "$NOTES" ]]; then
    gh release create "v${VERSION}" "$ZIP" --target "$COMMIT" --title "FCleaner ${VERSION}" --notes "$NOTES"
else
    gh release create "v${VERSION}" "$ZIP" --target "$COMMIT" --title "FCleaner ${VERSION}" --generate-notes
fi
echo "✅ v${VERSION} yayınlandı"
