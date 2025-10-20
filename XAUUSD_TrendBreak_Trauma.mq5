//+------------------------------------------------------------------+
//|                              XAUUSD_TrendBreak_Trauma.mq5       |
//|                               Copyright 2025, AlgoAct           |
//|                        https://lordgaruda.github.io/AlgoAct/    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, AlgoAct"
#property link      "https://lordgaruda.github.io/AlgoAct/"
#property version   "1.00"
#property description "XAUUSD Trend Line Break + Trauma + RSI Strategy"
#property description "Buy: Price above Trauma → Trend Break Signal → Exit at RSI > 70"
#property description "Sell: Price below Trauma → Trend Break Signal → Exit at RSI < 30"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Strategy Settings ==="
input string Symbol_Trade = "XAUUSD";
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H1;
input int MagicNumber = 789456;

input group "=== RSI Settings ==="
input int RSI_Period = 14;
input ENUM_APPLIED_PRICE RSI_AppliedPrice = PRICE_CLOSE;
input double RSI_Overbought = 70.0;
input double RSI_Oversold = 30.0;

input group "=== Trauma Indicator Settings ==="
input int Trauma_Period = 21;           // EMA period for Trauma line
input int Trauma_Multiplier = 2;        // ATR multiplier for Trauma bands
input int ATR_Period = 14;

input group "=== Trend Line Break Detection ==="
input int TrendLine_LookbackBars = 50;  // Bars to analyze for trend lines
input int TrendLine_MinTouches = 3;     // Minimum touches to form valid trend line
input double TrendLine_Tolerance = 0.0005; // Price tolerance for trend line (0.05%)
input int BreakoutConfirmBars = 2;      // Bars to confirm breakout

input group "=== Risk Management ==="
input double LotSize = 0.01;
input bool UseDynamicLots = true;
input double RiskPercent = 2.0;
input double StopLossPips = 100.0;
input double TakeProfitPips = 200.0;
input bool UseTrailingStop = false;
input double TrailingStopPips = 50.0;

input group "=== Time Filter ==="
input bool UseTimeFilter = true;
input int StartHour = 0;
input int EndHour = 23;
input bool TradeOnFriday = true;

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
int rsiHandle;
int emaHandle;
int atrHandle;

datetime lastBarTime = 0;
datetime lastTradeTime = 0;

struct TrendLine {
    double slope;
    double intercept;
    datetime startTime;
    datetime endTime;
    int touchCount;
    bool isSupport;     // true = support, false = resistance
    bool isBroken;
    datetime breakTime;
};

TrendLine currentSupportLine;
TrendLine currentResistanceLine;

enum TRADE_SIGNAL {
    SIGNAL_NONE,
    SIGNAL_BUY,
    SIGNAL_SELL
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(10);
    
    // Initialize RSI
    rsiHandle = iRSI(Symbol_Trade, TimeFrame, RSI_Period, RSI_AppliedPrice);
    if(rsiHandle == INVALID_HANDLE) {
        Print("Failed to create RSI indicator handle");
        return(INIT_FAILED);
    }
    
    // Initialize EMA for Trauma line
    emaHandle = iMA(Symbol_Trade, TimeFrame, Trauma_Period, 0, MODE_EMA, PRICE_CLOSE);
    if(emaHandle == INVALID_HANDLE) {
        Print("Failed to create EMA indicator handle");
        return(INIT_FAILED);
    }
    
    // Initialize ATR for Trauma bands
    atrHandle = iATR(Symbol_Trade, TimeFrame, ATR_Period);
    if(atrHandle == INVALID_HANDLE) {
        Print("Failed to create ATR indicator handle");
        return(INIT_FAILED);
    }
    
    // Initialize trend lines
    ZeroMemory(currentSupportLine);
    ZeroMemory(currentResistanceLine);
    
    Print("XAUUSD Trend Break + Trauma Strategy initialized successfully");
    Print("Timeframe: ", EnumToString(TimeFrame));
    Print("RSI Period: ", RSI_Period, " | Overbought: ", RSI_Overbought, " | Oversold: ", RSI_Oversold);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
    if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
    if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
    
    Print("XAUUSD Trend Break + Trauma Strategy deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new bar
    datetime currentBarTime = iTime(Symbol_Trade, TimeFrame, 0);
    if(currentBarTime == lastBarTime)
        return;
    
    lastBarTime = currentBarTime;
    
    // Check time filter
    if(!IsTradingTime())
        return;
    
    // Manage existing positions
    if(HasOpenPosition())
    {
        ManageOpenPosition();
        return;
    }
    
    // Analyze market and generate signals
    TRADE_SIGNAL signal = AnalyzeMarket();
    
    if(signal == SIGNAL_BUY)
    {
        ExecuteBuyTrade();
    }
    else if(signal == SIGNAL_SELL)
    {
        ExecuteSellTrade();
    }
}

//+------------------------------------------------------------------+
//| Analyze market for trading signals                              |
//+------------------------------------------------------------------+
TRADE_SIGNAL AnalyzeMarket()
{
    // Get current price
    double close[];
    ArraySetAsSeries(close, true);
    if(CopyClose(Symbol_Trade, TimeFrame, 0, 3, close) != 3)
        return SIGNAL_NONE;
    
    double currentPrice = close[0];
    
    // Get Trauma line value
    double traumaValue = GetTraumaValue();
    if(traumaValue == 0)
        return SIGNAL_NONE;
    
    // Get RSI value
    double rsiValue = GetRSIValue();
    if(rsiValue == 0)
        return SIGNAL_NONE;
    
    // Detect trend lines
    DetectTrendLines();
    
    // Check for BUY signal
    // Condition: Price above Trauma + Bullish trend line breakout
    if(currentPrice > traumaValue)
    {
        if(currentSupportLine.isBroken && !currentSupportLine.isSupport) // Resistance broken upward
        {
            // Confirm breakout is recent
            int barsSinceBreak = Bars(Symbol_Trade, TimeFrame, currentSupportLine.breakTime, TimeCurrent());
            if(barsSinceBreak <= BreakoutConfirmBars + 1)
            {
                Print("BUY SIGNAL: Price above Trauma (", traumaValue, ") + Bullish breakout detected");
                return SIGNAL_BUY;
            }
        }
    }
    
    // Check for SELL signal
    // Condition: Price below Trauma + Bearish trend line breakout
    if(currentPrice < traumaValue)
    {
        if(currentResistanceLine.isBroken && currentResistanceLine.isSupport) // Support broken downward
        {
            // Confirm breakout is recent
            int barsSinceBreak = Bars(Symbol_Trade, TimeFrame, currentResistanceLine.breakTime, TimeCurrent());
            if(barsSinceBreak <= BreakoutConfirmBars + 1)
            {
                Print("SELL SIGNAL: Price below Trauma (", traumaValue, ") + Bearish breakout detected");
                return SIGNAL_SELL;
            }
        }
    }
    
    return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Get Trauma indicator value (EMA)                                |
//+------------------------------------------------------------------+
double GetTraumaValue()
{
    double ema[];
    ArraySetAsSeries(ema, true);
    
    if(CopyBuffer(emaHandle, 0, 0, 1, ema) != 1)
        return 0;
    
    return ema[0];
}

//+------------------------------------------------------------------+
//| Get RSI value                                                    |
//+------------------------------------------------------------------+
double GetRSIValue()
{
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    if(CopyBuffer(rsiHandle, 0, 0, 1, rsi) != 1)
        return 0;
    
    return rsi[0];
}

//+------------------------------------------------------------------+
//| Detect trend lines (simplified algorithm)                       |
//+------------------------------------------------------------------+
void DetectTrendLines()
{
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    int bars = TrendLine_LookbackBars;
    if(CopyHigh(Symbol_Trade, TimeFrame, 0, bars, high) != bars) return;
    if(CopyLow(Symbol_Trade, TimeFrame, 0, bars, low) != bars) return;
    if(CopyClose(Symbol_Trade, TimeFrame, 0, bars, close) != bars) return;
    
    // Detect resistance trend line (connecting highs)
    DetectResistanceLine(high, close);
    
    // Detect support trend line (connecting lows)
    DetectSupportLine(low, close);
}

//+------------------------------------------------------------------+
//| Detect resistance trend line                                     |
//+------------------------------------------------------------------+
void DetectResistanceLine(const double &high[], const double &close[])
{
    // Find recent swing highs
    int swingHighs[];
    ArrayResize(swingHighs, 0);
    
    for(int i = 2; i < TrendLine_LookbackBars - 2; i++)
    {
        if(high[i] > high[i-1] && high[i] > high[i-2] && 
           high[i] > high[i+1] && high[i] > high[i+2])
        {
            int size = ArraySize(swingHighs);
            ArrayResize(swingHighs, size + 1);
            swingHighs[size] = i;
        }
    }
    
    if(ArraySize(swingHighs) < 2)
        return;
    
    // Create trend line from recent swing highs
    int idx1 = swingHighs[0];
    int idx2 = swingHighs[ArraySize(swingHighs) > 1 ? 1 : 0];
    
    if(idx1 == idx2 && ArraySize(swingHighs) > 2)
        idx2 = swingHighs[2];
    
    double price1 = high[idx1];
    double price2 = high[idx2];
    
    // Calculate slope
    currentResistanceLine.slope = (price2 - price1) / (idx1 - idx2);
    currentResistanceLine.intercept = price1;
    currentResistanceLine.isSupport = false;
    currentResistanceLine.touchCount = ArraySize(swingHighs);
    
    // Check if broken
    double trendLinePrice = currentResistanceLine.intercept;
    if(close[0] > trendLinePrice * (1.0 + TrendLine_Tolerance))
    {
        if(!currentResistanceLine.isBroken)
        {
            currentResistanceLine.isBroken = true;
            currentResistanceLine.breakTime = iTime(Symbol_Trade, TimeFrame, 0);
            Print("RESISTANCE BREAKOUT: Price broke above resistance trend line at ", close[0]);
        }
    }
    else
    {
        currentResistanceLine.isBroken = false;
    }
}

//+------------------------------------------------------------------+
//| Detect support trend line                                        |
//+------------------------------------------------------------------+
void DetectSupportLine(const double &low[], const double &close[])
{
    // Find recent swing lows
    int swingLows[];
    ArrayResize(swingLows, 0);
    
    for(int i = 2; i < TrendLine_LookbackBars - 2; i++)
    {
        if(low[i] < low[i-1] && low[i] < low[i-2] && 
           low[i] < low[i+1] && low[i] < low[i+2])
        {
            int size = ArraySize(swingLows);
            ArrayResize(swingLows, size + 1);
            swingLows[size] = i;
        }
    }
    
    if(ArraySize(swingLows) < 2)
        return;
    
    // Create trend line from recent swing lows
    int idx1 = swingLows[0];
    int idx2 = swingLows[ArraySize(swingLows) > 1 ? 1 : 0];
    
    if(idx1 == idx2 && ArraySize(swingLows) > 2)
        idx2 = swingLows[2];
    
    double price1 = low[idx1];
    double price2 = low[idx2];
    
    // Calculate slope
    currentSupportLine.slope = (price2 - price1) / (idx1 - idx2);
    currentSupportLine.intercept = price1;
    currentSupportLine.isSupport = true;
    currentSupportLine.touchCount = ArraySize(swingLows);
    
    // Check if broken
    double trendLinePrice = currentSupportLine.intercept;
    if(close[0] < trendLinePrice * (1.0 - TrendLine_Tolerance))
    {
        if(!currentSupportLine.isBroken)
        {
            currentSupportLine.isBroken = true;
            currentSupportLine.breakTime = iTime(Symbol_Trade, TimeFrame, 0);
            Print("SUPPORT BREAKDOWN: Price broke below support trend line at ", close[0]);
        }
    }
    else
    {
        currentSupportLine.isBroken = false;
    }
}

//+------------------------------------------------------------------+
//| Execute buy trade                                                |
//+------------------------------------------------------------------+
void ExecuteBuyTrade()
{
    double ask = SymbolInfoDouble(Symbol_Trade, SYMBOL_ASK);
    double point = SymbolInfoDouble(Symbol_Trade, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol_Trade, SYMBOL_DIGITS);
    
    // Calculate stop loss and take profit
    double stopLoss = ask - (StopLossPips * point * 10);
    double takeProfit = ask + (TakeProfitPips * point * 10);
    
    stopLoss = NormalizeDouble(stopLoss, digits);
    takeProfit = NormalizeDouble(takeProfit, digits);
    
    // Calculate lot size
    double lots = UseDynamicLots ? CalculateLotSize(ask, stopLoss) : LotSize;
    
    string comment = "TrendBreak_BUY";
    
    if(trade.Buy(lots, Symbol_Trade, ask, stopLoss, takeProfit, comment))
    {
        lastTradeTime = TimeCurrent();
        Print("BUY ORDER EXECUTED: Price=", ask, " SL=", stopLoss, " TP=", takeProfit, " Lots=", lots);
        Print("Exit condition: RSI > ", RSI_Overbought);
    }
    else
    {
        Print("BUY ORDER FAILED: Error ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Execute sell trade                                               |
//+------------------------------------------------------------------+
void ExecuteSellTrade()
{
    double bid = SymbolInfoDouble(Symbol_Trade, SYMBOL_BID);
    double point = SymbolInfoDouble(Symbol_Trade, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol_Trade, SYMBOL_DIGITS);
    
    // Calculate stop loss and take profit
    double stopLoss = bid + (StopLossPips * point * 10);
    double takeProfit = bid - (TakeProfitPips * point * 10);
    
    stopLoss = NormalizeDouble(stopLoss, digits);
    takeProfit = NormalizeDouble(takeProfit, digits);
    
    // Calculate lot size
    double lots = UseDynamicLots ? CalculateLotSize(bid, stopLoss) : LotSize;
    
    string comment = "TrendBreak_SELL";
    
    if(trade.Sell(lots, Symbol_Trade, bid, stopLoss, takeProfit, comment))
    {
        lastTradeTime = TimeCurrent();
        Print("SELL ORDER EXECUTED: Price=", bid, " SL=", stopLoss, " TP=", takeProfit, " Lots=", lots);
        Print("Exit condition: RSI < ", RSI_Oversold);
    }
    else
    {
        Print("SELL ORDER FAILED: Error ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Manage open position                                             |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
    if(!PositionSelect(Symbol_Trade))
        return;
    
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double profit = PositionGetDouble(POSITION_PROFIT);
    
    // Get RSI value
    double rsiValue = GetRSIValue();
    if(rsiValue == 0)
        return;
    
    bool shouldClose = false;
    string reason = "";
    
    // BUY position: Exit when RSI is overbought
    if(posType == POSITION_TYPE_BUY)
    {
        if(rsiValue >= RSI_Overbought)
        {
            shouldClose = true;
            reason = StringFormat("RSI Overbought (%.2f >= %.2f)", rsiValue, RSI_Overbought);
        }
        
        // Optional: Trailing stop
        if(UseTrailingStop && profit > 0)
        {
            UpdateTrailingStop(true);
        }
    }
    // SELL position: Exit when RSI is oversold
    else if(posType == POSITION_TYPE_SELL)
    {
        if(rsiValue <= RSI_Oversold)
        {
            shouldClose = true;
            reason = StringFormat("RSI Oversold (%.2f <= %.2f)", rsiValue, RSI_Oversold);
        }
        
        // Optional: Trailing stop
        if(UseTrailingStop && profit > 0)
        {
            UpdateTrailingStop(false);
        }
    }
    
    // Close position if exit condition met
    if(shouldClose)
    {
        if(trade.PositionClose(Symbol_Trade))
        {
            Print("POSITION CLOSED: ", reason, " | Profit: ", profit);
        }
        else
        {
            Print("FAILED TO CLOSE POSITION: Error ", trade.ResultRetcode());
        }
    }
}

//+------------------------------------------------------------------+
//| Update trailing stop                                             |
//+------------------------------------------------------------------+
void UpdateTrailingStop(bool isBuy)
{
    double stopLoss = PositionGetDouble(POSITION_SL);
    double takeProfit = PositionGetDouble(POSITION_TP);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    
    double point = SymbolInfoDouble(Symbol_Trade, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol_Trade, SYMBOL_DIGITS);
    double trailDistance = TrailingStopPips * point * 10;
    
    if(isBuy)
    {
        double newStopLoss = NormalizeDouble(currentPrice - trailDistance, digits);
        
        if(newStopLoss > stopLoss && newStopLoss < currentPrice)
        {
            if(trade.PositionModify(Symbol_Trade, newStopLoss, takeProfit))
            {
                Print("BUY Trailing Stop Updated: New SL = ", newStopLoss);
            }
        }
    }
    else
    {
        double newStopLoss = NormalizeDouble(currentPrice + trailDistance, digits);
        
        if((stopLoss == 0 || newStopLoss < stopLoss) && newStopLoss > currentPrice)
        {
            if(trade.PositionModify(Symbol_Trade, newStopLoss, takeProfit))
            {
                Print("SELL Trailing Stop Updated: New SL = ", newStopLoss);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size based on risk                         |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (RiskPercent / 100.0);
    
    double pointValue = SymbolInfoDouble(Symbol_Trade, SYMBOL_TRADE_TICK_VALUE);
    double point = SymbolInfoDouble(Symbol_Trade, SYMBOL_POINT);
    double stopDistance = MathAbs(entryPrice - stopLoss);
    
    double calculatedLots = riskAmount / (stopDistance / point * pointValue);
    
    // Normalize lot size
    double minLot = SymbolInfoDouble(Symbol_Trade, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol_Trade, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol_Trade, SYMBOL_VOLUME_STEP);
    
    calculatedLots = MathMax(minLot, MathMin(maxLot, calculatedLots));
    calculatedLots = MathRound(calculatedLots / lotStep) * lotStep;
    
    return calculatedLots;
}

//+------------------------------------------------------------------+
//| Check if there's an open position                                |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    return PositionSelect(Symbol_Trade);
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
    if(!UseTimeFilter)
        return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Check Friday trading
    if(!TradeOnFriday && dt.day_of_week == 5)
        return false;
    
    // Check hour range
    return (dt.hour >= StartHour && dt.hour < EndHour);
}
