//+------------------------------------------------------------------+
//|                           SMC_Utils.mqh - Utility Functions     |
//|                    Helper functions for SMC strategy            |
//+------------------------------------------------------------------+

#ifndef SMC_UTILS_H
#define SMC_UTILS_H

// Structure definitions
struct SwingPoint {
    double price;
    datetime time;
    int index;
    bool isHigh;
};

struct FairValueGap {
    double upperLevel;
    double lowerLevel;
    double midLevel;
    datetime startTime;
    datetime endTime;
    bool isBullish;
    bool isMitigated;
};

struct OrderBlock {
    double upperLevel;
    double lowerLevel;
    double triggerPrice;
    datetime formationTime;
    bool isBearish;
    bool isTriggered;
    int strength; // 1-5 scale
};

struct LiquidityZone {
    double level;
    datetime time;
    bool isHigh; // true for equal highs, false for equal lows
    bool isSwept;
    int touchCount;
};

//+------------------------------------------------------------------+
//| SMC Utility Class                                               |
//+------------------------------------------------------------------+
class SMCUtils {
public:
    // Market structure analysis
    static bool IsStructureBreak(double priceArray[], int startIndex, int endIndex, bool checkUpward);
    static bool IsChoch(double highArray[], double lowArray[], int lookback);
    static bool IsBOS(double priceArray[], double previousSwing, bool isUpward);
    
    // Fair Value Gap detection
    static bool DetectFVG(double highArray[], double lowArray[], int index, FairValueGap &fvg);
    static bool IsFVGMitigated(const FairValueGap &fvg, double currentHigh, double currentLow);
    static double GetFVGMidPoint(const FairValueGap &fvg);
    
    // Order Block detection
    static bool DetectOrderBlock(double openArray[], double highArray[], double lowArray[], 
                               double closeArray[], int index, OrderBlock &ob);
    static int GetOrderBlockStrength(const OrderBlock &ob, double volumeArray[], int index);
    static bool IsOrderBlockTriggered(const OrderBlock &ob, double currentPrice);
    
    // Liquidity detection
    static bool DetectLiquidityZone(double priceArray[], int lookback, LiquidityZone &lz);
    static bool IsLiquiditySwept(const LiquidityZone &lz, double currentHigh, double currentLow);
    
    // Price action utilities
    static bool IsEngulfingCandle(double open1, double high1, double low1, double close1,
                                double open2, double high2, double low2, double close2);
    static bool IsDoji(double open, double high, double low, double close, double threshold = 0.1);
    static bool IsHammer(double open, double high, double low, double close);
    static bool IsStar(double open, double high, double low, double close);
    
    // Mathematical utilities
    static double CalculateATR(double highArray[], double lowArray[], double closeArray[], int period);
    static double GetHighestHigh(double highArray[], int period);
    static double GetLowestLow(double lowArray[], int period);
    static double CalculateRSI(double closeArray[], int period);
    
    // Time and session utilities
    static bool IsLondonSession(datetime time);
    static bool IsNewYorkSession(datetime time);
    static bool IsAsianSession(datetime time);
    static bool IsSessionOverlap(datetime time);
    static bool IsHighImpactNewsTime(datetime time);
    
    // Risk management utilities
    static double CalculateOptimalLotSize(double accountBalance, double riskPercent, 
                                        double stopLossPips, string symbol);
    static double GetMaxDrawdownPercent(double equity[], int period);
    static double CalculateExpectedValue(double winRate, double avgWin, double avgLoss);
    
    // Chart pattern recognition
    static bool IsDoubleTop(double highArray[], int lookback, double tolerance = 0.001);
    static bool IsDoubleBottom(double lowArray[], int lookback, double tolerance = 0.001);
    static bool IsTripleTop(double highArray[], int lookback, double tolerance = 0.001);
    static bool IsHeadAndShoulders(double highArray[], int lookback);
    
    // Divergence detection
    static bool IsBullishDivergence(double priceArray[], double indicatorArray[], int lookback);
    static bool IsBearishDivergence(double priceArray[], double indicatorArray[], int lookback);
    static bool IsHiddenBullishDivergence(double priceArray[], double indicatorArray[], int lookback);
    
    // Volume analysis
    static bool IsVolumeSpike(long volumeArray[], int index, double multiplier = 2.0);
    static bool IsVolumeClimaxing(long volumeArray[], double priceArray[], int lookback);
    static double GetVolumeProfile(double priceArray[], long volumeArray[], double targetPrice, int lookback);
    
    // Trend analysis
    static int GetTrendDirection(double priceArray[], int period);
    static double GetTrendStrength(double priceArray[], int period);
    static bool IsTrendChanging(double priceArray[], int shortPeriod, int longPeriod);
    
    // Support and resistance
    static double FindNearestSupport(double priceArray[], double currentPrice, int lookback);
    static double FindNearestResistance(double priceArray[], double currentPrice, int lookback);
    static bool IsPriceAtSupport(double currentPrice, double supportLevel, double tolerance);
    static bool IsPriceAtResistance(double currentPrice, double resistanceLevel, double tolerance);
    
private:
    static double CalculateStandardDeviation(double array[], int period);
    static int FindPivotHigh(double highArray[], int index, int leftBars, int rightBars);
    static int FindPivotLow(double lowArray[], int index, int leftBars, int rightBars);
};

//+------------------------------------------------------------------+
//| Structure break detection                                        |
//+------------------------------------------------------------------+
bool SMCUtils::IsStructureBreak(double priceArray[], int startIndex, int endIndex, bool checkUpward) {
    if(startIndex >= endIndex || endIndex >= ArraySize(priceArray))
        return false;
    
    double referenceLevel = checkUpward ? GetHighestHigh(priceArray, endIndex - startIndex) 
                                       : GetLowestLow(priceArray, endIndex - startIndex);
    
    double currentPrice = priceArray[0];
    
    return checkUpward ? (currentPrice > referenceLevel) : (currentPrice < referenceLevel);
}

//+------------------------------------------------------------------+
//| Change of Character detection                                    |
//+------------------------------------------------------------------+
bool SMCUtils::IsChoch(double highArray[], double lowArray[], int lookback) {
    if(ArraySize(highArray) < lookback || ArraySize(lowArray) < lookback)
        return false;
    
    // Find recent swing high and low
    double recentHigh = GetHighestHigh(highArray, lookback);
    double recentLow = GetLowestLow(lowArray, lookback);
    
    // Look for break of structure pattern
    bool foundLowerLow = false;
    bool foundHigherHigh = false;
    
    for(int i = 1; i < lookback - 5; i++) {
        if(!foundLowerLow && lowArray[i] < recentLow) {
            foundLowerLow = true;
            continue;
        }
        
        if(foundLowerLow && highArray[i] > recentHigh) {
            foundHigherHigh = true;
            break;
        }
    }
    
    return (foundLowerLow && foundHigherHigh);
}

//+------------------------------------------------------------------+
//| Fair Value Gap detection                                         |
//+------------------------------------------------------------------+
bool SMCUtils::DetectFVG(double highArray[], double lowArray[], int index, FairValueGap &fvg) {
    if(index < 2 || index >= ArraySize(highArray) - 1)
        return false;
    
    // Check for 3-candle gap pattern
    if(lowArray[index-1] > highArray[index+1]) {
        // Bullish FVG
        fvg.upperLevel = lowArray[index-1];
        fvg.lowerLevel = highArray[index+1];
        fvg.midLevel = (fvg.upperLevel + fvg.lowerLevel) / 2.0;
        fvg.isBullish = true;
        fvg.isMitigated = false;
        return true;
    }
    else if(highArray[index-1] < lowArray[index+1]) {
        // Bearish FVG
        fvg.upperLevel = highArray[index-1];
        fvg.lowerLevel = lowArray[index+1];
        fvg.midLevel = (fvg.upperLevel + fvg.lowerLevel) / 2.0;
        fvg.isBullish = false;
        fvg.isMitigated = false;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Order Block detection                                            |
//+------------------------------------------------------------------+
bool SMCUtils::DetectOrderBlock(double openArray[], double highArray[], double lowArray[], 
                              double closeArray[], int index, OrderBlock &ob) {
    if(index < 1 || index >= ArraySize(openArray) - 3)
        return false;
    
    // Look for strong directional candle followed by displacement
    double bodySize = MathAbs(closeArray[index] - openArray[index]);
    double totalRange = highArray[index] - lowArray[index];
    
    if(bodySize < totalRange * 0.6) // Body must be at least 60% of total range
        return false;
    
    bool isBearishCandle = closeArray[index] < openArray[index];
    
    if(isBearishCandle) {
        // Check for downward displacement after bearish candle
        bool hasDisplacement = false;
        for(int i = index - 1; i >= MathMax(0, index - 3); i--) {
            if(lowArray[i] < lowArray[index]) {
                hasDisplacement = true;
                break;
            }
        }
        
        if(hasDisplacement) {
            ob.upperLevel = highArray[index];
            ob.lowerLevel = lowArray[index];
            ob.triggerPrice = ob.upperLevel;
            ob.isBearish = true;
            ob.isTriggered = false;
            ob.strength = GetOrderBlockStrength(ob, NULL, index);
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calculate optimal lot size                                       |
//+------------------------------------------------------------------+
double SMCUtils::CalculateOptimalLotSize(double accountBalance, double riskPercent, 
                                       double stopLossPips, string symbol) {
    double riskAmount = accountBalance * (riskPercent / 100.0);
    double pointValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    double stopLossInPrice = stopLossPips * point * 10; // Convert pips to price
    double lotSize = riskAmount / (stopLossInPrice / point * pointValue);
    
    // Normalize to valid lot size
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = MathRound(lotSize / lotStep) * lotStep;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Session time detection                                           |
//+------------------------------------------------------------------+
bool SMCUtils::IsLondonSession(datetime time) {
    MqlDateTime dt;
    TimeToStruct(time, dt);
    return (dt.hour >= 8 && dt.hour < 17); // 8 AM to 5 PM GMT
}

bool SMCUtils::IsNewYorkSession(datetime time) {
    MqlDateTime dt;
    TimeToStruct(time, dt);
    return (dt.hour >= 13 && dt.hour < 22); // 1 PM to 10 PM GMT
}

bool SMCUtils::IsAsianSession(datetime time) {
    MqlDateTime dt;
    TimeToStruct(time, dt);
    return (dt.hour >= 23 || dt.hour < 8); // 11 PM to 8 AM GMT
}

bool SMCUtils::IsSessionOverlap(datetime time) {
    return IsLondonSession(time) && IsNewYorkSession(time);
}

//+------------------------------------------------------------------+
//| Utility helper functions                                         |
//+------------------------------------------------------------------+
double SMCUtils::GetHighestHigh(double highArray[], int period) {
    if(ArraySize(highArray) < period)
        return 0;
    
    double highest = highArray[0];
    for(int i = 1; i < period; i++) {
        if(highArray[i] > highest)
            highest = highArray[i];
    }
    return highest;
}

double SMCUtils::GetLowestLow(double lowArray[], int period) {
    if(ArraySize(lowArray) < period)
        return 0;
    
    double lowest = lowArray[0];
    for(int i = 1; i < period; i++) {
        if(lowArray[i] < lowest && lowArray[i] > 0)
            lowest = lowArray[i];
    }
    return lowest;
}

int SMCUtils::GetOrderBlockStrength(const OrderBlock &ob, double volumeArray[], int index) {
    // Calculate strength based on candle size, volume, and displacement
    double range = ob.upperLevel - ob.lowerLevel;
    
    // Basic strength calculation (1-5 scale)
    if(range > 0) {
        if(range > 50 * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10) // > 50 pips
            return 5;
        else if(range > 30 * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10) // > 30 pips
            return 4;
        else if(range > 20 * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10) // > 20 pips
            return 3;
        else if(range > 10 * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10) // > 10 pips
            return 2;
        else
            return 1;
    }
    
    return 1;
}

#endif // SMC_UTILS_H