#!/bin/bash

# Load .env file
set -a
source .env
set +a

echo "🔍 Verifying Shopify API Credentials..."
echo ""

# Check if credentials are set
if [ "$SHOPIFY_ACCESS_TOKEN" == "your_access_token_here" ] || [ -z "$SHOPIFY_ACCESS_TOKEN" ]; then
  echo "❌ SHOPIFY_ACCESS_TOKEN not set in .env"
  exit 1
fi

if [ "$SHOPIFY_STORE_NAME" == "your-store-name" ] || [ -z "$SHOPIFY_STORE_NAME" ]; then
  echo "❌ SHOPIFY_STORE_NAME not set in .env"
  exit 1
fi

echo "✅ Credentials found"
echo "  Store: $SHOPIFY_STORE_NAME"
echo "  Token: ${SHOPIFY_ACCESS_TOKEN:0:10}...${SHOPIFY_ACCESS_TOKEN: -10}"
echo ""

# Test the API
echo "🧪 Testing GraphQL API..."
echo ""

ENDPOINT="https://$SHOPIFY_STORE_NAME.myshopify.com/admin/api/2025-10/graphql.json"

RESPONSE=$(curl -s -X POST "$ENDPOINT" \
  -H "X-Shopify-Access-Token: $SHOPIFY_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{ shop { name } }"
  }')

echo "Response:"
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
echo ""

# Check for errors
if echo "$RESPONSE" | grep -q '"errors"'; then
  echo "❌ API Error detected"
  exit 1
elif echo "$RESPONSE" | grep -q '"name"'; then
  echo "✅ API Connection successful!"
  exit 0
else
  echo "⚠️  Unexpected response - check credentials"
  exit 1
fi
