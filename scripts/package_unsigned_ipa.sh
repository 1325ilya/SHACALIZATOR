#!/bin/bash
set -euo pipefail

# ============================================================
#  Package Shacalizator.app into an unsigned IPA
#  Run this AFTER xcodebuild has completed successfully.
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_NAME="Shacalizator"
BUILD_DIR="build"
IPA_NAME="Shacalizator_unsigned.ipa"

echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}  Packaging unsigned IPA${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo ""

# ── Clean previous artifacts ───────────────────────────────
rm -rf Payload
rm -f "${IPA_NAME}"

# ── Find .app ──────────────────────────────────────────────
echo -e "${YELLOW}[1/3] Searching for ${PROJECT_NAME}.app...${NC}"
APP_PATH=$(find "${BUILD_DIR}" -name "${PROJECT_NAME}.app" -type d | head -n 1)

if [ -z "${APP_PATH}" ]; then
  echo -e "${RED}❌ ${PROJECT_NAME}.app not found in ${BUILD_DIR}/${NC}"
  echo "   Build directory contents:"
  find "${BUILD_DIR}" -maxdepth 5 -type d 2>/dev/null || true
  exit 1
fi

echo -e "${GREEN}   ✅ Found: ${APP_PATH}${NC}"

# ── Create Payload ─────────────────────────────────────────
echo -e "${YELLOW}[2/3] Creating Payload structure...${NC}"
mkdir -p Payload
cp -R "${APP_PATH}" "Payload/${PROJECT_NAME}.app"
echo -e "${GREEN}   ✅ Payload/${PROJECT_NAME}.app created${NC}"

# ── Zip into IPA ───────────────────────────────────────────
echo -e "${YELLOW}[3/3] Zipping into ${IPA_NAME}...${NC}"
zip -qr "${IPA_NAME}" Payload/

# ── Verification ───────────────────────────────────────────
echo ""
echo -e "${CYAN}── Verification ─────────────────────────${NC}"

if [ ! -f "${IPA_NAME}" ]; then
  echo -e "${RED}❌ IPA was not created!${NC}"
  exit 1
fi

IPA_SIZE=$(du -h "${IPA_NAME}" | cut -f1)
echo -e "${GREEN}✅ IPA created: ${IPA_NAME} (${IPA_SIZE})${NC}"

# Verify Payload structure
if unzip -l "${IPA_NAME}" | grep -q "Payload/${PROJECT_NAME}.app/Info.plist"; then
  echo -e "${GREEN}✅ Info.plist present${NC}"
else
  echo -e "${RED}❌ Info.plist missing!${NC}"
  exit 1
fi

if unzip -l "${IPA_NAME}" | grep -q "Payload/${PROJECT_NAME}.app/${PROJECT_NAME}$"; then
  echo -e "${GREEN}✅ Executable present${NC}"
else
  # Try without exact end match (in case of trailing data)
  if unzip -l "${IPA_NAME}" | grep "Payload/${PROJECT_NAME}.app/${PROJECT_NAME}"; then
    echo -e "${GREEN}✅ Executable present${NC}"
  else
    echo -e "${YELLOW}⚠️  Executable not verified (may still work)${NC}"
  fi
fi

# Check bundle ID
TEMP_DIR=$(mktemp -d)
unzip -o "${IPA_NAME}" "Payload/${PROJECT_NAME}.app/Info.plist" -d "${TEMP_DIR}" > /dev/null 2>&1 || true
if [ -f "${TEMP_DIR}/Payload/${PROJECT_NAME}.app/Info.plist" ]; then
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${TEMP_DIR}/Payload/${PROJECT_NAME}.app/Info.plist" 2>/dev/null || echo "unknown")
  echo -e "${GREEN}📦 Bundle ID: ${BUNDLE_ID}${NC}"
fi
rm -rf "${TEMP_DIR}"

# Check code signature absence
if unzip -l "${IPA_NAME}" | grep -q "_CodeSignature"; then
  echo -e "${YELLOW}⚠️  CodeSignature directory exists (may be empty)${NC}"
else
  echo -e "${GREEN}✅ No code signature (unsigned)${NC}"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Unsigned IPA ready: ${IPA_NAME}${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo "  Full path: $(pwd)/${IPA_NAME}"
