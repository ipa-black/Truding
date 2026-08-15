import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  runApp(const DiamondTradeApp());
}

class DiamondTradeApp extends StatelessWidget {
  const DiamondTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diamond Trade',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        primaryColor: const Color(0xFF00E5FF),
        fontFamily: 'sans-serif',
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: ScalpingDashboard(),
      ),
    );
  }
}

class ScalpingDashboard extends StatefulWidget {
  const ScalpingDashboard({super.key});

  @override
  State<ScalpingDashboard> createState() => _ScalpingDashboardState();
}

class _ScalpingDashboardState extends State<ScalpingDashboard> with SingleTickerProviderStateMixin {
  String selectedTimeframe = "1m";
  
  double oversoldLevel = 35.0;
  double overboughtLevel = 65.0;
  double botSensitivity = 2.0; 
  
  double currentRsi = 50.0;
  String microTrendStatus = "جاري التحليل...";
  String macroTrendStatus = "قراءة ترند 1H...";
  
  String activeSignal = "الرادار في وضع الاستعداد";
  Color activeSignalColor = Colors.white54;
  int winRate = 0;
  String targetPoints = "0";

  bool isScanning = false;
  bool isConnected = false;
  bool isWeekend = false;

  bool isAsiaActive = false;
  bool isLondonActive = false;
  bool isNyActive = false;

  Timer? _scanTimer;
  Timer? _clockTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _checkWeekend();
    _startClock();
    
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _checkWeekend() {
    DateTime now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      setState(() {
        isWeekend = true;
      });
    } else {
      setState(() {
        isWeekend = false;
      });
    }
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final timeDouble = now.hour + (now.minute / 60.0);
      
      bool asia = (timeDouble >= 2.0 && timeDouble < 11.0);
      bool london = (timeDouble >= 10.0 && timeDouble < 19.0);
      bool ny = (timeDouble >= 15.5 || timeDouble < 1.0);

      if (asia && !isAsiaActive) _showNotification("سيولة جديدة: بدأت جلسة طوكيو (آسيا) 🌏");
      if (london && !isLondonActive) _showNotification("سيولة عالية: بدأت جلسة لندن 🌍");
      if (ny && !isNyActive) _showNotification("سيولة ضخمة: بدأت جلسة نيويورك 🌎");

      setState(() {
        isAsiaActive = asia;
        isLondonActive = london;
        isNyActive = ny;
      });

      if (now.second == 0) {
        _checkWeekend();
      }
    });
  }

  void _showNotification(String message) {
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
          ],
        ),
        backgroundColor: const Color(0xFF00E5FF).withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.only(top: 50, left: 16, right: 16),
      )
    );
  }

  void _changeTimeframe(String tf) {
    setState(() {
      selectedTimeframe = tf;
      if (isScanning) {
        _fetchMarketData();
      }
    });
  }

  void _toggleScanning() {
    setState(() {
      isScanning = !isScanning;
    });
    
    if (isScanning) {
      _pulseController.repeat(reverse: true);
      _fetchMarketData();
      _scanTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        _fetchMarketData();
      });
    } else {
      _pulseController.stop();
      _pulseController.animateTo(1.0);
      _scanTimer?.cancel();
      setState(() {
        isConnected = false;
        activeSignal = "الرادار في وضع الاستعداد";
        activeSignalColor = Colors.white54;
        winRate = 0;
        targetPoints = "0";
      });
    }
  }

  Future<void> _fetchMarketData() async {
    String urlMicro = 'https://api.binance.com/api/v3/klines?symbol=PAXGUSDT&interval=$selectedTimeframe&limit=250';
    String urlMacro = 'https://api.binance.com/api/v3/klines?symbol=PAXGUSDT&interval=1h&limit=250';
    
    try {
      final responses = await Future.wait([
        http.get(Uri.parse(urlMicro)),
        http.get(Uri.parse(urlMacro)),
      ]).timeout(const Duration(seconds: 3));

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        List<dynamic> klinesMicro = jsonDecode(responses[0].body);
        List<dynamic> klinesMacro = jsonDecode(responses[1].body);

        List<double> closeMicro = [];
        for (var k in klinesMicro) {
          closeMicro.add(double.parse(k[4].toString()));
        }

        List<double> closeMacro = [];
        for (var k in klinesMacro) {
          closeMacro.add(double.parse(k[4].toString()));
        }

        if (closeMicro.length < 200 || closeMacro.length < 200) return;

        double rsi = _calculateRSI(closeMicro, 20);
        double ema50Micro = _calculateEMA(closeMicro, 50);
        double ema200Micro = _calculateEMA(closeMicro, 200);
        Map<String, double> macdMicro = _calculateMACD(closeMicro);
        double price = closeMicro.last;

        double ema200Macro = _calculateEMA(closeMacro, 200);
        bool isMacroUp = closeMacro.last > ema200Macro;

        setState(() {
          isConnected = true;
          currentRsi = rsi;

          macroTrendStatus = isMacroUp ? "صاعد ⬆️" : "هابط ⬇️";
          
          bool isMicroUp = price > ema200Micro && ema50Micro > ema200Micro;
          bool isMicroDown = price < ema200Micro && ema50Micro < ema200Micro;
          
          if (isMicroUp) {
            microTrendStatus = "صاعد ⬆️";
          } else if (isMicroDown) {
            microTrendStatus = "هابط ⬇️";
          } else {
            microTrendStatus = "عرضي ↔️";
          }

          if (isWeekend) {
            activeSignal = "السوق مغلق (عطلة الأسبوع) 🛑";
            activeSignalColor = const Color(0xFFFF5252);
            winRate = 0;
            targetPoints = "0";
            return; 
          }

          bool macdBullish = macdMicro['hist']! > 0;
          bool macdBearish = macdMicro['hist']! < 0;

          bool signalBuy = false;
          bool signalSell = false;
          int calculatedWinRate = 50;
          String expectedPoints = "0";

          if (botSensitivity == 1.0) {
            signalBuy = rsi <= oversoldLevel && isMicroUp && isMacroUp && macdBullish;
            signalSell = rsi >= overboughtLevel && isMicroDown && !isMacroUp && macdBearish;
            expectedPoints = (selectedTimeframe == "1m" || selectedTimeframe == "3m") ? "15-20" : "30-50";
            if (signalBuy || signalSell) calculatedWinRate = 95;
            
          } else if (botSensitivity == 2.0) {
            signalBuy = rsi <= oversoldLevel && (isMicroUp || isMacroUp) && macdBullish;
            signalSell = rsi >= overboughtLevel && (isMicroDown || !isMacroUp) && macdBearish;
            expectedPoints = (selectedTimeframe == "1m" || selectedTimeframe == "3m") ? "10-15" : "20-30";
            if (signalBuy || signalSell) calculatedWinRate = 85;
            
          } else if (botSensitivity == 3.0) {
            signalBuy = rsi <= oversoldLevel && macdBullish;
            signalSell = rsi >= overboughtLevel && macdBearish;
            expectedPoints = "5-10 (خطف سريع)";
            if (signalBuy || signalSell) calculatedWinRate = 75;
          }

          if (signalBuy) {
            activeSignal = "دخول شراء (Buy) 🚀";
            activeSignalColor = const Color(0xFF00E5FF);
            winRate = calculatedWinRate + ((oversoldLevel - rsi).clamp(0, 4)).toInt(); 
            targetPoints = expectedPoints;
          } else if (signalSell) {
            activeSignal = "دخول بيع (Sell) 🔥";
            activeSignalColor = const Color(0xFFFF1744);
            winRate = calculatedWinRate + ((rsi - overboughtLevel).clamp(0, 4)).toInt();
            targetPoints = expectedPoints;
          } else if (rsi <= oversoldLevel || rsi >= overboughtLevel) {
            activeSignal = "تجهيز... (ننتظر تأكيد الماكدي)";
            activeSignalColor = const Color(0xFFFFEA00);
            winRate = 40;
            targetPoints = "0";
          } else {
            activeSignal = "مراقبة السيولة";
            activeSignalColor = const Color(0xFF64B5F6);
            double distance = rsi > 50 ? (rsi - 50) * 1.2 : (50 - rsi) * 1.2;
            winRate = distance.clamp(10, 50).toInt();
            targetPoints = "0";
          }

          if (isScanning && winRate >= 85) {
            HapticFeedback.mediumImpact();
          }
        });
      }
    } catch (e) {
      setState(() {
        isConnected = false;
      });
    }
  }

  double _calculateRSI(List<double> closes, int period) {
    List<double> recentCloses = closes.sublist(closes.length - 100);
    double gain = 0.0;
    double loss = 0.0;
    
    for (int i = 1; i <= period; i++) {
      double change = recentCloses[i] - recentCloses[i - 1];
      if (change > 0) {
        gain += change;
      } else {
        loss -= change;
      }
    }
    
    double avgGain = gain / period;
    double avgLoss = loss / period;
    
    for (int i = period + 1; i < recentCloses.length; i++) {
      double change = recentCloses[i] - recentCloses[i - 1];
      double currentGain = change > 0 ? change : 0.0;
      double currentLoss = change < 0 ? -change : 0.0;
      
      avgGain = ((avgGain * (period - 1)) + currentGain) / period;
      avgLoss = ((avgLoss * (period - 1)) + currentLoss) / period;
    }
    
    if (avgLoss == 0) return 100.0;
    double rs = avgGain / avgLoss;
    return 100.0 - (100.0 / (1.0 + rs));
  }

  double _calculateEMA(List<double> prices, int period) {
    double multiplier = 2.0 / (period + 1);
    double sum = 0.0;
    
    for (int i = 0; i < period; i++) {
      sum += prices[i];
    }
    
    double sma = sum / period;
    double ema = sma;
    
    for (int i = period; i < prices.length; i++) {
      ema = ((prices[i] - ema) * multiplier) + ema;
    }
    return ema;
  }

  Map<String, double> _calculateMACD(List<double> prices) {
    List<double> macdLine = [];
    for (int i = 50; i <= prices.length; i++) {
      List<double> sub = prices.sublist(0, i);
      double ema12 = _calculateEMA(sub, 12);
      double ema26 = _calculateEMA(sub, 26);
      macdLine.add(ema12 - ema26);
    }
    
    double signalLine = _calculateEMA(macdLine, 9);
    double currentMacd = macdLine.last;
    double histogram = currentMacd - signalLine;
    
    return {
      "macd": currentMacd,
      "signal": signalLine,
      "hist": histogram
    };
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _clockTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'DIAMOND TRADE',
          style: TextStyle(
            fontSize: 20,
            letterSpacing: 2,
            fontWeight: FontWeight.w900,
            color: Color(0xFF00E5FF)
          )
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTimeframeButton("1m", "1 دقيقة"),
                _buildTimeframeButton("3m", "3 دقائق"),
                _buildTimeframeButton("5m", "5 دقائق"),
                _buildTimeframeButton("15m", "15 دقيقة"),
              ],
            ),
            const SizedBox(height: 12),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121826),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2))
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text("ترند الساعة 1H", style: TextStyle(fontSize: 11, color: Colors.white54)),
                        const SizedBox(height: 4),
                        Text(
                          macroTrendStatus,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: macroTrendStatus.contains("صاعد") ? const Color(0xFF00E5FF) : const Color(0xFFFF1744)
                          )
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 30, color: Colors.white10),
                  Expanded(
                    child: Column(
                      children: [
                        Text("ترند الـ $selectedTimeframe", style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        const SizedBox(height: 4),
                        Text(
                          microTrendStatus,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: microTrendStatus.contains("صاعد") ? const Color(0xFF00E5FF) : (microTrendStatus.contains("هابط") ? const Color(0xFFFF1744) : Colors.white)
                          )
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF121826),
                borderRadius: BorderRadius.circular(14)
              ),
              child: Column(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text("سرعة وحساسية البوت (${botSensitivity == 1 ? 'محافظ وبطيء' : botSensitivity == 2 ? 'متوازن' : 'هجومي وسريع'})", style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600)),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF00E5FF),
                          inactiveTrackColor: Colors.white10,
                          thumbColor: const Color(0xFF00E5FF),
                          overlayColor: const Color(0xFF00E5FF).withOpacity(0.2),
                          trackHeight: 6.0,
                        ),
                        child: Slider(
                          value: botSensitivity,
                          min: 1,
                          max: 3,
                          divisions: 2,
                          onChanged: (val) {
                            setState(() {
                              botSensitivity = val;
                            });
                          }
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text("مستوى الشراء (أقل من: ${oversoldLevel.toInt()})", style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600)),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF00E5FF),
                          inactiveTrackColor: Colors.white10,
                          thumbColor: const Color(0xFF00E5FF),
                          overlayColor: const Color(0xFF00E5FF).withOpacity(0.2),
                          trackHeight: 6.0,
                        ),
                        child: Slider(
                          value: oversoldLevel,
                          min: 20,
                          max: 50,
                          divisions: 30,
                          onChanged: (val) {
                            setState(() {
                              oversoldLevel = val;
                            });
                          }
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text("مستوى البيع (أعلى من: ${overboughtLevel.toInt()})", style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600)),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFFFF1744),
                          inactiveTrackColor: Colors.white10,
                          thumbColor: const Color(0xFFFF1744),
                          overlayColor: const Color(0xFFFF1744).withOpacity(0.2),
                          trackHeight: 6.0,
                        ),
                        child: Slider(
                          value: overboughtLevel,
                          min: 50,
                          max: 80,
                          divisions: 30,
                          onChanged: (val) {
                            setState(() {
                              overboughtLevel = val;
                            });
                          }
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCirc,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                color: const Color(0xFF121826),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isScanning ? activeSignalColor.withOpacity(0.5) : Colors.transparent,
                  width: 2
                ),
                boxShadow: isScanning ? [
                  BoxShadow(color: activeSignalColor.withOpacity(0.15), blurRadius: 40, spreadRadius: 5)
                ] : [],
              ),
              child: Column(
                children: [
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: isScanning ? [
                          BoxShadow(color: activeSignalColor.withOpacity(0.4), blurRadius: 40)
                        ] : []
                      ),
                      child: SvgPicture.asset('assets/diamond.svg', width: 65, height: 65),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      currentRsi > 0 ? currentRsi.toStringAsFixed(1) : "--",
                      key: ValueKey<double>(currentRsi),
                      style: const TextStyle(fontSize: 70, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -2)
                    ),
                  ),
                  const SizedBox(height: 5),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      activeSignal,
                      key: ValueKey<String>(activeSignal),
                      style: TextStyle(fontSize: 22, color: activeSignalColor, fontWeight: FontWeight.w800)
                    ),
                  ),
                  if (isScanning && winRate > 60) ...[
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: activeSignalColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: activeSignalColor.withOpacity(0.3))
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.verified, size: 14, color: activeSignalColor),
                              const SizedBox(width: 4),
                              Text("النجاح: $winRate%", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: activeSignalColor)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withOpacity(0.3))
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.my_location, size: 14, color: Colors.white),
                              const SizedBox(width: 4),
                              Text("الهدف: $targetPoints نقطة", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                    )
                  ]
                ],
              ),
            ),
            const SizedBox(height: 25),
            
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _toggleScanning,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isScanning ? const Color(0xFF1E2638) : const Color(0xFF00E5FF),
                  foregroundColor: isScanning ? Colors.white : Colors.black,
                  elevation: isScanning ? 0 : 15,
                  shadowColor: const Color(0xFF00E5FF).withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isScanning ? Icons.stop_circle_rounded : Icons.radar_rounded, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      isScanning ? "إيقاف الخوارزمية" : "تشغيل الرادار",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeframeButton(String tf, String label) {
    bool isSelected = selectedTimeframe == tf;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        child: ChoiceChip(
          label: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w800
            )
          ),
          selected: isSelected,
          selectedColor: const Color(0xFF00E5FF),
          backgroundColor: const Color(0xFF121826),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onSelected: (_) {
            _changeTimeframe(tf);
          },
        ),
      ),
    );
  }
}
