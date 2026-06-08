#!/bin/sh

#  ci_post_clone.sh
#  Atacama
#
#  Auto-increment build number for Xcode Cloud archive builds.
#  This runs after Xcode Cloud clones the repository.

set -e

echo "Checking build configuration..."

if [ -n "$CI_WORKFLOW" ]; then
    echo "Workflow: $CI_WORKFLOW"

    if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
        echo "Archive build detected; updating build number"

        if [ -n "$CI_BUILD_NUMBER" ]; then
            echo "Using Xcode Cloud build number: $CI_BUILD_NUMBER"
            BUILD_NUMBER=$CI_BUILD_NUMBER
        else
            echo "CI_BUILD_NUMBER not found; using default"
            BUILD_NUMBER=1
        fi

        cd "$(dirname "$0")/.."

        PROJECT_FILE="Atacama.xcodeproj/project.pbxproj"

        if [ -f "$PROJECT_FILE" ]; then
            echo "Updating build number to $BUILD_NUMBER in $PROJECT_FILE"
            sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PROJECT_FILE"
            echo "Build number updated to $BUILD_NUMBER"
        else
            echo "Project file not found: $PROJECT_FILE"
            echo "Current directory: $(pwd)"
            ls -la
            exit 1
        fi
    else
        echo "Not an archive build (action: $CI_XCODEBUILD_ACTION); skipping build number update"
    fi
else
    echo "Not running in Xcode Cloud; skipping"
fi

echo "Post-clone script completed"
