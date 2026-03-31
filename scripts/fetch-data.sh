#!/bin/bash
# Fetch River token data and append to history JSON
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"
HISTORY_FILE="$DATA_DIR/history.json"
SIGNALS_FILE="$DATA_DIR/signals.json"

mkdir -p "$DATA_DIR"

# Initialize files if not exist
[ -f "$HISTORY_FILE" ] || echo '[]' > "$HISTORY_FILE"
[ -f "$SIGNALS_FILE" ] || echo '[]' > "$SIGNALS_FILE"

CONTRACT="0xda7ad9dea9397cffddae2f8a052b82f1484252b3"
CHAIN="56"
NOW_MS=$(date +%s)000
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Fetch dynamic data
DYN=$(curl -sf "https://web3.binance.com/bapi/defi/v4/public/wallet-direct/buw/wallet/market/token/dynamic/info?chainId=${CHAIN}&contractAddress=${CONTRACT}" \
  -H 'Accept-Encoding: identity' 2>/dev/null || echo '{"data":null}')

if echo "$DYN" | jq -e '.data.price' > /dev/null 2>&1; then
  # Extract fields
  SNAPSHOT=$(echo "$DYN" | jq --arg ts "$NOW_ISO" '{
    timestamp: $ts,
    price: (.data.price | tonumber),
    marketCap: (.data.marketCap | tonumber),
    volume24h: (.data.volume24h | tonumber),
    volume24hBuy: (.data.volume24hBuy | tonumber),
    volume24hSell: (.data.volume24hSell | tonumber),
    holders: (.data.holders | tonumber),
    smartMoneyHolders: (.data.smartMoneyHolders | tonumber),
    smartMoneyHoldingPercent: ((.data.smartMoneyHoldingPercent // "0") | tonumber),
    kolHolders: ((.data.kolHolders // "0") | tonumber),
    kolHoldingPercent: ((.data.kolHoldingPercent // "0") | tonumber),
    proHolders: ((.data.proHolders // "0") | tonumber),
    proHoldingPercent: ((.data.proHoldingPercent // "0") | tonumber),
    newWalletHolders: ((.data.newWalletHolders // "0") | tonumber),
    newWalletHoldingPercent: ((.data.newWalletHoldingPercent // "0") | tonumber),
    bundlerHoldingPercent: ((.data.bundlerHoldingPercent // "0") | tonumber),
    liquidity: (.data.liquidity | tonumber),
    top10HoldersPercentage: (.data.top10HoldersPercentage | tonumber),
    percentChange24h: ((.data.percentChange24h // "0") | tonumber),
    fdv: (.data.fdv | tonumber),
    priceHigh24h: (.data.priceHigh24h | tonumber),
    priceLow24h: (.data.priceLow24h | tonumber)
  }')

  # Fetch OI data from Binance Futures
  OI_RAW=$(curl -sf "https://fapi.binance.com/fapi/v1/openInterest?symbol=RIVERUSDT" 2>/dev/null || echo '{}')
  OI_VAL=$(echo "$OI_RAW" | jq -r '.openInterest // "0"')
  
  # Fetch OI + mark price for value calculation
  MARK_RAW=$(curl -sf "https://fapi.binance.com/fapi/v1/premiumIndex?symbol=RIVERUSDT" 2>/dev/null || echo '{}')
  MARK_PRICE=$(echo "$MARK_RAW" | jq -r '.markPrice // "0"')
  FUNDING_RATE=$(echo "$MARK_RAW" | jq -r '.lastFundingRate // "0"')

  # Add OI fields to snapshot
  SNAPSHOT=$(echo "$SNAPSHOT" | jq --arg oi "$OI_VAL" --arg mp "$MARK_PRICE" --arg fr "$FUNDING_RATE" '. + {
    openInterest: ($oi | tonumber),
    markPrice: ($mp | tonumber),
    fundingRate: ($fr | tonumber)
  }')

  # Fetch long/short ratio
  LSR_RAW=$(curl -sf "https://fapi.binance.com/futures/data/globalLongShortAccountRatio?symbol=RIVERUSDT&period=5m&limit=1" 2>/dev/null || echo '[]')
  LSR_VAL=$(echo "$LSR_RAW" | jq -r '.[0].longShortRatio // "0"')
  LONG_PCT=$(echo "$LSR_RAW" | jq -r '.[0].longAccount // "0"')
  SHORT_PCT=$(echo "$LSR_RAW" | jq -r '.[0].shortAccount // "0"')

  # Top trader long/short (position ratio)
  TLS_RAW=$(curl -sf "https://fapi.binance.com/futures/data/topLongShortPositionRatio?symbol=RIVERUSDT&period=5m&limit=1" 2>/dev/null || echo '[]')
  TLS_VAL=$(echo "$TLS_RAW" | jq -r '.[0].longShortRatio // "0"')

  # Binance Smart Money overview (futures)
  SM_RAW=$(curl -sf "https://www.binance.com/bapi/futures/v1/public/future/smart-money/signal/overview?symbol=RIVERUSDT" 2>/dev/null || echo '{"data":{}}')

  SNAPSHOT=$(echo "$SNAPSHOT" | jq --arg lsr "$LSR_VAL" --arg lp "$LONG_PCT" --arg sp "$SHORT_PCT" \
    --arg tls "$TLS_VAL" --argjson sm "$(echo "$SM_RAW" | jq '.data // {}')" '. + {
    longShortRatio: ($lsr | tonumber),
    longPercent: ($lp | tonumber),
    shortPercent: ($sp | tonumber),
    topTraderLSRatio: ($tls | tonumber),
    smLongShortRatio: ($sm.longShortRatio // 0),
    smTotalPositions: ($sm.totalPositions // 0),
    smTotalTraders: ($sm.totalTraders // 0),
    smLongTraders: ($sm.longTraders // 0),
    smShortTraders: ($sm.shortTraders // 0),
    smLongNotional: (($sm.longTradersQty // 0) * ($sm.longTradersAvgEntryPrice // 0)),
    smShortNotional: (($sm.shortTradersQty // 0) * ($sm.shortTradersAvgEntryPrice // 0)),
    smLongWhales: ($sm.longWhales // 0),
    smShortWhales: ($sm.shortWhales // 0),
    smLongWhaleNotional: (($sm.longWhalesQty // 0) * ($sm.longWhalesAvgEntryPrice // 0)),
    smShortWhaleNotional: (($sm.shortWhalesQty // 0) * ($sm.shortWhalesAvgEntryPrice // 0)),
    smLongProfitTraders: ($sm.longProfitTraders // 0),
    smShortProfitTraders: ($sm.shortProfitTraders // 0),
    smLongProfitWhales: ($sm.longProfitWhales // 0),
    smShortProfitWhales: ($sm.shortProfitWhales // 0)
  }')

  # Append to history (keep last 2000 entries ~41 days at 30min intervals)
  jq --argjson snap "$SNAPSHOT" '. + [$snap] | .[-2000:]' "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
  echo "✅ Snapshot saved at $NOW_ISO - Price: $(echo "$SNAPSHOT" | jq '.price') - OI: $OI_VAL"
else
  echo "❌ Failed to fetch data"
  exit 1
fi

# Fetch smart money signals
SIGS=$(curl -sf 'https://web3.binance.com/bapi/defi/v1/public/wallet-direct/buw/wallet/web/signal/smart-money' \
  -H 'Content-Type: application/json' -H 'Accept-Encoding: identity' \
  -d "{\"smartSignalType\":\"\",\"page\":1,\"pageSize\":100,\"chainId\":\"${CHAIN}\"}" 2>/dev/null || echo '{"data":[]}')

echo "$SIGS" | jq '[.data[] | {
  signalId, ticker, direction, contractAddress,
  smartMoneyCount, alertPrice: (.alertPrice | tonumber),
  currentPrice: (.currentPrice | tonumber),
  maxGain: ((.maxGain // "0") | tonumber),
  exitRate, status,
  signalTriggerTime: (.signalTriggerTime / 1000 | strftime("%Y-%m-%dT%H:%M:%SZ")),
  totalTokenValue: (.totalTokenValue | tonumber)
}] | sort_by(.signalTriggerTime) | reverse | .[:50]' > "$SIGNALS_FILE.tmp" && mv "$SIGNALS_FILE.tmp" "$SIGNALS_FILE"

echo "✅ Signals updated: $(jq length "$SIGNALS_FILE") entries"
