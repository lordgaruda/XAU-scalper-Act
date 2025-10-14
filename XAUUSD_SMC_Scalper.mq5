//+------------------------------------------------------------------+
//|                                        XAUUSD_SMC_Scalper.mq5   |
//|                               Copyright 2025, AlgoAct           |
//|                        https://lordgaruda.github.io/AlgoAct/    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, AlgoAct"
#property link      "https://lordgaruda.github.io/AlgoAct/"
#property version   "1.00"
#property description "XAUUSD Auto Scalper - Smart Money Concepts Strategy"

#include <Trade\Trade.mqh>

input group "=== Strategy Settings ==="
input string Symbol = "XAUUSD";
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M15;
input double LotSize = 0.01;
input int MagicNumber = 789123;
input double RiskRewardRatio = 2.0;
input bool UseTrailingStop = true;
input double TrailingStopDistance = 50.0;

input group "=== SMC Parameters ==="
input int CHoCH_LookbackPeriods = 50;
input int FVG_MinSizePips = 5;
input int OrderBlock_LookbackPeriods = 20;
input double FVG_EntryPercent = 50.0;

input group "=== Risk Management ==="
input double MaxRiskPercent = 2.0;
input double StopLossPips = 100.0;
input bool UseATRStopLoss = true;
input int ATR_Period = 14;
input double ATR_Multiplier = 2.0;

input group "=== Time Filter ==="
input int StartHour = 8;
input int EndHour = 18;
input bool TradeOnFriday = false;

CTrade trade;
bool chochDetected = false;
double fvgHigh = 0, fvgLow = 0;
double orderBlockHigh = 0, orderBlockLow = 0;
datetime lastTradeTime = 0;
int atrHandle;

struct SMC_Data {
    bool isBullishCHoCH;
    double fvgUpperLevel;
    double fvgLowerLevel;
    double fvgMidLevel;
    double orderBlockLevel;
    bool hasFVG;
    bool hasOrderBlock;
    datetime chochTime;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    
    if(Symbol != "XAUUSD") {
        Print("Warning: This EA is optimized for XAUUSD");
    }
    
    atrHandle = iATR(Symbol, TimeFrame, ATR_Period);
    if(atrHandle == INVALID_HANDLE) {
        Print("Failed to create ATR indicator handle");
        return(INIT_FAILED);
    }
    
    Print("XAUUSD SMC Scalper initialized successfully");
    Print("Monitoring for Bullish CHoCH on ", EnumToString(TimeFrame));
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(atrHandle != INVALID_HANDLE)
        IndicatorRelease(atrHandle);
    Print("XAUUSD SMC Scalper deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!IsTradingTime())
        return;
    
    if(HasOpenPosition())
    {
        ManageOpenPosition();
        return;
    }
    
    SMC_Data smcData;
    AnalyzeSMCStructure(smcData);
    
    if(smcData.isBullishCHoCH && smcData.hasFVG && smcData.hasOrderBlock)
    {
        ExecuteScalpTrade(smcData);
    }
}

//+------------------------------------------------------------------+
//| Analyze Smart Money Concept structure                           |
//+------------------------------------------------------------------+
void AnalyzeSMCStructure(SMC_Data &data)
{
    ZeroMemory(data);
    
    data.isBullishCHoCH = DetectBullishCHoCH();
    
    if(data.isBullishCHoCH)
    {
        data.hasFVG = DetectBullishFVG(data.fvgUpperLevel, data.fvgLowerLevel);
        if(data.hasFVG)
        {
            data.fvgMidLevel = (data.fvgUpperLevel + data.fvgLowerLevel) / 2.0;
            data.hasOrderBlock = DetectBearishOrderBlock(data.orderBlockLevel);
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Bullish Change of Character (CHoCH)                      |
//+------------------------------------------------------------------+
bool DetectBullishCHoCH()
{
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyHigh(Symbol, TimeFrame, 0, CHoCH_LookbackPeriods, high) != CHoCH_LookbackPeriods)
        return false;
    if(CopyLow(Symbol, TimeFrame, 0, CHoCH_LookbackPeriods, low) != CHoCH_LookbackPeriods)
        return false;
    if(CopyClose(Symbol, TimeFrame, 0, CHoCH_LookbackPeriods, close) != CHoCH_LookbackPeriods)
        return false;
    
    // Find recent swing low and high
    double recentSwingLow = low[ArrayMinimum(low, 5, 20)];
    double recentSwingHigh = high[ArrayMaximum(high, 5, 20)];
    
    // Check for break of structure (BOS) indicating CHoCH
    double currentPrice = close[0];
    
    // Look for higher high after lower low (bullish CHoCH pattern)
    bool foundLowerLow = false;
    bool foundHigherHigh = false;
    
    for(int i = 1; i < CHoCH_LookbackPeriods - 10; i++)
    {
        if(!foundLowerLow && low[i] < recentSwingLow)
        {
            foundLowerLow = true;
            continue;
        }
        
        if(foundLowerLow && high[i] > recentSwingHigh)
        {
            foundHigherHigh = true;
            break;
        }
    }
    
    // Confirm current price is above the swing high
    return (foundLowerLow && foundHigherHigh && currentPrice > recentSwingHigh);
}

//+------------------------------------------------------------------+
//| Detect Bullish Fair Value Gap (FVG)                            |
//+------------------------------------------------------------------+
bool DetectBullishFVG(double &fvgHigh, double &fvgLow)
{
    double high[], low[], open[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);
    
    if(CopyHigh(Symbol, TimeFrame, 0, 10, high) != 10) return false;
    if(CopyLow(Symbol, TimeFrame, 0, 10, low) != 10) return false;
    if(CopyOpen(Symbol, TimeFrame, 0, 10, open) != 10) return false;
    if(CopyClose(Symbol, TimeFrame, 0, 10, close) != 10) return false;
    
    double point = SymbolInfoDouble(Symbol, SYMBOL_POINT);
    double minGapSize = FVG_MinSizePips * point * 10; // Convert pips to price
    
    // Check for 3-candle bullish FVG pattern
    for(int i = 2; i < 8; i++)
    {
        // Bullish FVG: candle[i+1].low > candle[i-1].high
        if(low[i-1] > high[i+1])
        {
            double gapSize = low[i-1] - high[i+1];
            if(gapSize >= minGapSize)
            {
                fvgHigh = low[i-1];
                fvgLow = high[i+1];
                
                // Check if current price is approaching FVG
                double currentPrice = close[0];
                return (currentPrice >= fvgLow && currentPrice <= fvgHigh);
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Bearish Order Block above FVG                           |
//+------------------------------------------------------------------+
bool DetectBearishOrderBlock(double &orderBlockLevel)
{
    double high[], low[], open[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);
    
    if(CopyHigh(Symbol, TimeFrame, 0, OrderBlock_LookbackPeriods, high) != OrderBlock_LookbackPeriods) return false;
    if(CopyLow(Symbol, TimeFrame, 0, OrderBlock_LookbackPeriods, low) != OrderBlock_LookbackPeriods) return false;
    if(CopyOpen(Symbol, TimeFrame, 0, OrderBlock_LookbackPeriods, open) != OrderBlock_LookbackPeriods) return false;
    if(CopyClose(Symbol, TimeFrame, 0, OrderBlock_LookbackPeriods, close) != OrderBlock_LookbackPeriods) return false;
    
    // Look for bearish order block (strong bearish candle followed by displacement)
    for(int i = 3; i < OrderBlock_LookbackPeriods - 3; i++)
    {
        // Identify strong bearish candle
        bool isBearishCandle = close[i] < open[i];
        double candleRange = high[i] - low[i];
        double bodySize = MathAbs(open[i] - close[i]);
        
        if(isBearishCandle && bodySize > candleRange * 0.7) // Strong bearish body
        {
            // Check for displacement after order block
            bool hasDisplacement = false;
            for(int j = i - 1; j >= MathMax(0, i - 3); j--)
            {
                if(low[j] < low[i]) // Price moved lower
                {
                    hasDisplacement = true;
                    break;
                }
            }
            
            if(hasDisplacement)
            {
                orderBlockLevel = high[i]; // Use high of bearish order block
                
                // Ensure order block is above current FVG levels
                return (orderBlockLevel > fvgHigh);
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Execute scalp trade                                             |
//+------------------------------------------------------------------+
void ExecuteScalpTrade(SMC_Data &data)
{
    double currentPrice = SymbolInfoDouble(Symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol, SYMBOL_DIGITS);
    
    // Entry at FVG mid-line
    double entryPrice = data.fvgMidLevel;
    
    // Calculate stop loss
    double stopLoss = CalculateStopLoss(entryPrice, true);
    
    // Calculate take profit based on order block or RR ratio
    double takeProfit = CalculateTakeProfit(entryPrice, stopLoss, data.orderBlockLevel);
    
    // Normalize prices
    entryPrice = NormalizeDouble(entryPrice, digits);
    stopLoss = NormalizeDouble(stopLoss, digits);
    takeProfit = NormalizeDouble(takeProfit, digits);
    
    // Check if current price is near FVG mid-line
    double priceDistance = MathAbs(currentPrice - entryPrice);
    double maxDistance = 20 * point * 10; // 20 pips tolerance
    
    if(priceDistance <= maxDistance)
    {
        string comment = StringFormat("SMC_Scalp_%.2f", RiskRewardRatio);
        
        if(trade.Buy(LotSize, Symbol, currentPrice, stopLoss, takeProfit, comment))
        {
            lastTradeTime = TimeCurrent();
            Print("SMC Scalp BUY executed: Entry=", currentPrice, " SL=", stopLoss, " TP=", takeProfit);
        }
        else
        {
            Print("Failed to execute SMC scalp trade. Error: ", trade.ResultRetcode());
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate dynamic stop loss                                     |
//+------------------------------------------------------------------+
double CalculateStopLoss(double entryPrice, bool isBuy)
{
    double stopLoss;
    double point = SymbolInfoDouble(Symbol, SYMBOL_POINT);
    
    if(UseATRStopLoss)
    {
        double atr[];
        ArraySetAsSeries(atr, true);
        
        if(CopyBuffer(atrHandle, 0, 0, 1, atr) == 1)
        {
            double atrValue = atr[0] * ATR_Multiplier;
            stopLoss = isBuy ? entryPrice - atrValue : entryPrice + atrValue;
        }
        else
        {
            // Fallback to fixed pips
            stopLoss = isBuy ? entryPrice - (StopLossPips * point * 10) : entryPrice + (StopLossPips * point * 10);
        }
    }
    else
    {
        stopLoss = isBuy ? entryPrice - (StopLossPips * point * 10) : entryPrice + (StopLossPips * point * 10);
    }
    
    return stopLoss;
}

//+------------------------------------------------------------------+
//| Calculate take profit                                           |
//+------------------------------------------------------------------+
double CalculateTakeProfit(double entryPrice, double stopLoss, double orderBlockLevel)
{
    double takeProfit;
    
    // Option 1: Use order block level as target
    if(orderBlockLevel > 0 && orderBlockLevel > entryPrice)
    {
        double distanceToOB = orderBlockLevel - entryPrice;
        double stopDistance = entryPrice - stopLoss;
        
        // Check if order block provides good RR ratio
        if(distanceToOB >= stopDistance * 1.5) // At least 1.5:1 RR
        {
            takeProfit = orderBlockLevel - (10 * SymbolInfoDouble(Symbol, SYMBOL_POINT) * 10); // 10 pips before OB
            return takeProfit;
        }
    }
    
    // Option 2: Use fixed RR ratio
    double stopDistance = MathAbs(entryPrice - stopLoss);
    takeProfit = entryPrice + (stopDistance * RiskRewardRatio);
    
    return takeProfit;
}

//+------------------------------------------------------------------+
//| Manage open position with trailing stop                        |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
    if(!PositionSelect(Symbol))
        return;
    
    double positionProfit = PositionGetDouble(POSITION_PROFIT);
    double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double stopLoss = PositionGetDouble(POSITION_SL);
    double takeProfit = PositionGetDouble(POSITION_TP);
    
    if(UseTrailingStop && positionProfit > 0)
    {
        double point = SymbolInfoDouble(Symbol, SYMBOL_POINT);
        double trailDistance = TrailingStopDistance * point * 10;
        
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        if(posType == POSITION_TYPE_BUY)
        {
            double newStopLoss = currentPrice - trailDistance;
            
            if(newStopLoss > stopLoss)
            {
                if(trade.PositionModify(Symbol, newStopLoss, takeProfit))
                {
                    Print("Trailing stop updated: New SL = ", newStopLoss);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if there's an open position                              |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    return PositionSelect(Symbol);
}

//+------------------------------------------------------------------+
//| Check trading time                                              |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    if(!TradeOnFriday && dt.day_of_week == 5)
        return false;
    
    return (dt.hour >= StartHour && dt.hour < EndHour);
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                          |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entryPrice, double stopLoss)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (MaxRiskPercent / 100.0);
    
    double pointValue = SymbolInfoDouble(Symbol, SYMBOL_TRADE_TICK_VALUE);
    double stopDistance = MathAbs(entryPrice - stopLoss);
    
    double calculatedLots = riskAmount / (stopDistance / SymbolInfoDouble(Symbol, SYMBOL_POINT) * pointValue);
    
    // Normalize lot size
    double minLot = SymbolInfoDouble(Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol, SYMBOL_VOLUME_STEP);
    
    calculatedLots = MathMax(minLot, MathMin(maxLot, calculatedLots));
    calculatedLots = MathRound(calculatedLots / lotStep) * lotStep;
    
    return calculatedLots;
}