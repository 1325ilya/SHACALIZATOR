#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_NAME="Shacalizator"
SCHEME="Shacalizator"
BUILD_DIR="$(pwd)/build"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
IPA_NAME="Shacalizator_unsigned.ipa"
IPA_PATH="$(pwd)/${IPA_NAME}"

echo -e "${YELLOW}=== Shacalizator Unsigned IPA Builder ===${NC}"
echo ""

# Step 1: Clean
echo -e "${YELLOW}[1/5] Cleaning previous build...${NC}"
rm -rf "${BUILD_DIR}"
rm -f "${IPA_PATH}"
xcodebuild clean -project "${PROJECT_NAME}.xcodeproj" -scheme "${SCHEME}" 2>/dev/null || true

# Step 2: Build
echo -e "${YELLOW}[2/5] Building ${PROJECT_NAME}...${NC}"
xcodebuild build \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  ONLY_ACTIVE_ARCH=NO

# Step 3: Find .app
echo -e "${YELLOW}[3/5] Locating .app bundle...${NC}"
APP_PATH=$(find "${BUILD_DIR}" -name "${PROJECT_NAME}.app" -type d | head -1)

if [ -z "${APP_PATH}" ]; then
  echo -e "${RED}ERROR: ${PROJECT_NAME}.app not found in build output!${NC}"
  exit 1
fi

echo "Found: ${APP_PATH}"

# Step 4: Create Payload
echo -e "${YELLOW}[4/5] Creating Payload structure...${NC}"
mkdir -p "${PAYLOAD_DIR}"
cp -R "${APP_PATH}" "${PAYLOAD_DIR}/"

# Step 5: Create IPA
echo -e "${YELLOW}[5/5] Creating unsigned IPA...${NC}"
cd "${BUILD_DIR}"
zip -r "${IPA_PATH}" Payload/
cd ..

# Verification
echo ""
echo -e "${GREEN}=== Build Verification ===${NC}"

if [ -f "${IPA_PATH}" ]; then
  IPA_SIZE=$(du -h "${IPA_PATH}" | cut -f1)
  echo -e "${GREEN}✅ IPA created successfully: ${IPA_PATH}${NC}"
  echo -e "${GREEN}   Size: ${IPA_SIZE}${NC}"

  # Verify IPA contents
  echo -e "${YELLOW}   Verifying IPA contents...${NC}"
  if unzip -l "${IPA_PATH}" | grep -q "Payload/${PROJECT_NAME}.app/Info.plist"; then
    echo -e "${GREEN}   ✅ Info.plist found in IPA${NC}"
  else
    echo -e "${RED}   ❌ Info.plist NOT found in IPA${NC}"
  fi

  if unzip -l "${IPA_PATH}" | grep -q "Payload/${PROJECT_NAME}.app/${PROJECT_NAME}"; then
    echo -e "${GREEN}   ✅ Executable found in IPA${NC}"
  else
    echo -e "${RED}   ❌ Executable NOT found in IPA${NC}"
  fi

  # Check bundle ID from Info.plist
  TEMP_DIR=$(mktemp -d)
  unzip -o "${IPA_PATH}" "Payload/${PROJECT_NAME}.app/Info.plist" -d "${TEMP_DIR}" > /dev/null 2>&1
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${TEMP_DIR}/Payload/${PROJECT_NAME}.app/Info.plist" 2>/dev/null || echo "unknown")
  echo -e "${GREEN}   Bundle ID: ${BUNDLE_ID}${NC}"
  rm -rf "${TEMP_DIR}"

  # Check for code signature (should be absent)
  if unzip -l "${IPA_PATH}" | grep -q "_CodeSignature"; then
    echo -e "${YELLOW}   ⚠️  Code signature directory found (might be empty)${NC}"
  else
    echo -e "${GREEN}   ✅ No code signature (unsigned as expected)${NC}"
  fi

  echo ""
  echo -e "${GREEN}=== Done! ===${NC}"
  echo -e "IPA location: ${IPA_PATH}"
  echo -e "Sign it with your certificate and deploy."
else
  echo -e "${RED}❌ ERROR: IPA file was not created!${NC}"
  exit 1
fi
