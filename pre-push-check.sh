#!/bin/bash

# Pre-Open Source Security Check
# Run this before pushing to public repository

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}🔍 X402 Pre-Open Source Security Check${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

ERRORS=0
WARNINGS=0

# 1. Check for .env files in git
echo -e "${YELLOW}[1/8] Checking for .env files in git...${NC}"
if git ls-files 2>/dev/null | grep -q "\.env$"; then
    echo -e "${RED}❌ CRITICAL: .env files are tracked in git!${NC}"
    git ls-files | grep "\.env$" | while read file; do
        echo -e "${RED}   - $file${NC}"
    done
    ((ERRORS++))
else
    echo -e "${GREEN}✅ No .env files tracked${NC}"
fi
echo ""

# 2. Check for .env files in directory (should not exist or be in .gitignore)
echo -e "${YELLOW}[2/8] Checking for .env files in directory...${NC}"
ENV_FILES=$(find . -name ".env" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)
if [ -n "$ENV_FILES" ]; then
    echo -e "${YELLOW}⚠️  WARNING: .env files exist in directory:${NC}"
    echo "$ENV_FILES" | while read file; do
        echo -e "${YELLOW}   - $file${NC}"
    done
    echo -e "${YELLOW}   Make sure they're in .gitignore!${NC}"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ No .env files in directory${NC}"
fi
echo ""

# 3. Verify .gitignore exists and is correct
echo -e "${YELLOW}[3/8] Verifying .gitignore...${NC}"
if [ -f .gitignore ] && grep -q "^\.env$" .gitignore; then
    echo -e "${GREEN}✅ .gitignore properly configured${NC}"
else
    echo -e "${RED}❌ CRITICAL: .gitignore missing or doesn't block .env!${NC}"
    ((ERRORS++))
fi
echo ""

# 4. Check for hardcoded private keys (excluding docs)
echo -e "${YELLOW}[4/8] Scanning for hardcoded private keys...${NC}"
KEY_FILES=$(grep -r "0x[a-fA-F0-9]\{64\}" \
    --exclude-dir=node_modules \
    --exclude-dir=.git \
    --exclude-dir=lib \
    --exclude="*.md" \
    --exclude="pre-push-check.sh" \
    . 2>/dev/null || true)

if [ -n "$KEY_FILES" ]; then
    KEY_COUNT=$(echo "$KEY_FILES" | wc -l | tr -d ' ')
    echo -e "${YELLOW}⚠️  WARNING: Found $KEY_COUNT potential private keys:${NC}"
    echo "$KEY_FILES" | head -5
    if [ "$KEY_COUNT" -gt 5 ]; then
        echo -e "${YELLOW}   ... and $((KEY_COUNT - 5)) more${NC}"
    fi
    echo -e "${YELLOW}   Review these files manually!${NC}"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ No hardcoded keys found in source code${NC}"
fi
echo ""

# 5. Verify LICENSE is non-commercial
echo -e "${YELLOW}[5/8] Verifying LICENSE...${NC}"
if [ -f LICENSE ] && grep -q "NonCommercial" LICENSE; then
    echo -e "${GREEN}✅ CC BY-NC 4.0 license present${NC}"
else
    echo -e "${RED}❌ CRITICAL: LICENSE missing or incorrect!${NC}"
    ((ERRORS++))
fi
echo ""

# 6. Verify README has security warnings
echo -e "${YELLOW}[6/8] Checking README.md...${NC}"
if [ -f README.md ]; then
    if grep -q "NOT AUDITED" README.md || grep -q "NOT been audited" README.md; then
        echo -e "${GREEN}✅ README has security warnings${NC}"
    else
        echo -e "${YELLOW}⚠️  WARNING: README missing audit warning${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}❌ CRITICAL: README.md missing!${NC}"
    ((ERRORS++))
fi
echo ""

# 7. Verify SECURITY.md exists
echo -e "${YELLOW}[7/8] Checking SECURITY.md...${NC}"
if [ -f SECURITY.md ]; then
    echo -e "${GREEN}✅ SECURITY.md present${NC}"
else
    echo -e "${YELLOW}⚠️  WARNING: SECURITY.md missing (recommended)${NC}"
    ((WARNINGS++))
fi
echo ""

# 8. Check git history for .env files
echo -e "${YELLOW}[8/8] Checking git history for .env files...${NC}"
if git rev-parse --git-dir > /dev/null 2>&1; then
    HISTORY_ENV=$(git log --all --full-history --format="%H" -- "*/.env" "**/.env" 2>/dev/null | head -1)
    if [ -n "$HISTORY_ENV" ]; then
        echo -e "${RED}❌ CRITICAL: .env files found in git history!${NC}"
        echo -e "${RED}   You MUST clean git history before pushing!${NC}"
        echo -e "${RED}   See OPEN_SOURCE_CHECKLIST.md section 'Clean Git History'${NC}"
        ((ERRORS++))
    else
        echo -e "${GREEN}✅ No .env files in git history${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Not a git repository (will need to initialize)${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}📊 Summary${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL CHECKS PASSED!${NC}"
    echo ""
    echo -e "${GREEN}You're ready to open source this repository!${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Create new GitHub repository"
    echo "  2. git remote add origin <url>"
    echo "  3. git push -u origin main"
    echo "  4. Create release tag v2.0.0-testnet"
    echo ""
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  $WARNINGS WARNING(S) - Review recommended${NC}"
    echo ""
    echo -e "${YELLOW}You can proceed but should address warnings first.${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ $ERRORS CRITICAL ERROR(S) FOUND!${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $WARNINGS WARNING(S)${NC}"
    fi
    echo ""
    echo -e "${RED}DO NOT push to public repository yet!${NC}"
    echo -e "${RED}Fix all critical errors first.${NC}"
    echo ""
    echo "See OPEN_SOURCE_CHECKLIST.md for detailed fixes."
    echo ""
    exit 1
fi
