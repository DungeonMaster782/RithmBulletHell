#!/bin/bash

VERSION="1.4.1"
DATE=$(date +%Y-%m-%d)

echo "## [$VERSION] - $DATE" > /tmp/changelog.tmp
git log --oneline --no-merges -5 >> /tmp/changelog.tmp
echo "" >> /tmp/changelog.tmp

# если CHANGELOG уже есть — дописываем сверху
if [ -f CHANGELOG.md ]; then
  cat CHANGELOG.md >> /tmp/changelog.tmp
fi

mv /tmp/changelog.tmp CHANGELOG.md

git add .
git commit -m "chore: alpha v$VERSION"
git tag v$VERSION
git push
git push --tags
