#!/bin/bash

VERSION="1.4.1"

git add .
git commit -m "chore: alpha v$VERSION"
git tag v$VERSION
git push
git push --tags
