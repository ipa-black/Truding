import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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
        scaffoldBackgroundColor: const Color(0xFF10141E),
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

class _ScalpingDashboardState extends State<ScalpingDashboard> {
  String selectedTimeframe = "1m";
  double oversoldLevel = 35.0;
  double overboughtLevel = 65.0;
  double currentRsi = 50.0;
  
  String activeSignal = "جاري تهيئة الرادار...";
  Color activeSignalColor = Colors.white70;
  int confidence = 0;

  bool isScanning = false;
  bool isConnected = false;
  Timer? _scanTimer;
  Timer? _clockTimer;

  bool isAsiaActive = false;
  bool isLondonActive = false;
  bool isNyActive = false;

  @override
  void initState() {
    super.initState();
    _startClock();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      // التوقيت مبرمج افتراضياً على توقيت GMT+3
      final timeDouble = now.hour + (now.minute / 60.0);
      setState(() {
        isAsiaActive = (timeDouble >= 2.0 && timeDouble < 11.0);
        isLondonActive = (timeDouble >= 10.0 && timeDouble < 19.0);
        isNyActive = (timeDouble >= 15.5 || timeDouble < 1.0);
      });
    });
  }

  void _changeTimeframe(String tf) {
    setState(() {
      selectedTimeframe = tf;
      if (tf == "1m") {
        oversoldLevel = 35.0; overboughtLevel = 65.0;
      } else if (tf == "3m") {
        oversoldLevel = 32.0; overboughtLevel = 68.0;
      } else if (tf == "5m") {
        oversoldLevel = 30.0; overboughtLevel = 70.0;
      }
      if (isScanning) _fetchMarketData();
    });
  }

  void _toggleScanning() {
    setState(() {
      isScanning = !isScanning;
    });

    if (isScanning) {
      _fetchMarketData();
      _scanTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        _fetchMarketData();
      });
    } else {
      _scanTimer?.cancel();
      setState(() {
        isConnected = false;
        activeSignal = "تم إيقاف الرادار";
        activeSignalColor = Colors.white54;
        confidence = 0;
      });
    }
  }

  Future<void> _fetchMarketData() async {
    String apiUrl = 'https://api.binance.com/api/v3/klines?symbol=PAXGUSDT&interval=$selectedTimeframe&limit=21';
    try {
      final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        List<dynamic> klines = jsonDecode(response.body);
        List<double> closePrices = [];
        for (var kline in klines) {
          closePrices.add(double.parse(kline[4].toString()));
        }

        double calculatedRsi = _calculateRSI(closePrices, 20);

        setState(() {
          isConnected = true;
          currentRsi = calculatedRsi;
          
          if (calculatedRsi <= oversoldLevel) {
            activeSignal = "شراء 🟢";
            activeSignalColor = const Color(0xFF00E676);
            confidence = 100;
          } else if (calculatedRsi >= overboughtLevel) {
            activeSignal = "بيع 🔴";
            activeSignalColor = const Color(0xFFFF5252);
            confidence = 100;
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
    if (closes.length <= period) return 50.0;
    double gain = 0.0;
    double loss = 0.0;

    for (int i = 1; i <= period; i++) {
      double change = closes[i] - closes[i - 1];
      if (change > 0) gain += change;
      else loss -= change;
    }
    
    double avgGain = gain / period;
    double avgLoss = loss / period;

    for (int i = period + 1; i < closes.length; i++) {
      double change = closes[i] - closes[i - 1];
      double currentGain = change > 0 ? change : 0.0;
      double currentLoss = change < 0 ? -change : 0.0;
      avgGain = ((avgGain * (period - 1)) + currentGain) / period;
      avgLoss = ((avgLoss * (period - 1)) + currentLoss) / period;
    }

    if (avgLoss == 0) return 100.0;
    double rs = avgGain / avgLoss;
    return 100.0 - (100.0 / (1.0 + rs));
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Diamond Trade', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00E676))),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            // استخدام أيقونة الألماسة SVG
            child: SvgPicture.asset('assets/diamond.svg', width: 26, height: 26),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTfButton("1m", "1 دقيقة"),
                _buildTfButton("3m", "3 دقائق"),
                _buildTfButton("5m", "5 دقائق"),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(color: const Color(0xFF181C26), borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSessionItem("آسيا", "09:00 - 00:00", isAsiaActive),
                  _buildSessionItem("لندن", "19:00 - 10:00", isLondonActive),
                  _buildSessionItem("نيويورك", "00:30 - 15:30", isNyActive),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, size: 10, color: isConnected ? const Color(0xFF00E676) : Colors.red),
                const SizedBox(width: 6),
                Text(isConnected ? "الخوادم متصلة (البيانات حية)" : "جاري فحص الاتصال...", style: TextStyle(color: isConnected ? const Color(0xFF00E676) : Colors.red, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF181C26), borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  _buildSliderDisplay("التشبع البيعي (نقطة الشراء)", oversoldLevel, const Color(0xFF00E676)),
                  const SizedBox(height: 16),
                  _buildSliderDisplay("التشبع الشرائي (نقطة البيع)", overboughtLevel, const Color(0xFFFF5252)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatBox("الثقة", "$confidence%", Icons.security),
                const SizedBox(width: 8),
                _buildStatBox("الشموع", "20", Icons.candlestick_chart),
                const SizedBox(width: 8),
                _buildStatBox("الحالة", isScanning ? "نشط" : "متوقف", Icons.speed, valueColor: isScanning ? const Color(0xFF00E676) : Colors.white54),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                color: const Color(0xFF181C26),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isScanning ? activeSignalColor.withOpacity(0.5) : Colors.transparent, width: 2),
              ),
              child: Column(
                children: [
                  SvgPicture.asset('assets/diamond.svg', width: 40, height: 40),
                  const SizedBox(height: 15),
                  Text(
                    currentRsi > 0 ? currentRsi.toStringAsFixed(1) : "--",
                    style: const TextStyle(fontSize: 55, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activeSignal, 
                    style: TextStyle(fontSize: 26, color: activeSignalColor, fontWeight: FontWeight.bold)
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _toggleScanning,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isScanning ? const Color(0xFF3A3F4A) : const Color(0xFF00E676),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(isScanning ? Icons.pause_circle_filled : Icons.play_circle_fill, color: isScanning ? Colors.white : Colors.black, size: 28),
                label: Text(
                  isScanning ? "إيقاف الرادار" : "بدء المسح السريع",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isScanning ? Colors.white : Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTfButton(String tf, String label) {
    bool isSelected = selectedTimeframe == tf;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
        selected: isSelected,
        selectedColor: const Color(0xFF00E676),
        backgroundColor: const Color(0xFF181C26),
        onSelected: (_) => _changeTimeframe(tf),
      ),
    );
  }

  Widget _buildSessionItem(String name, String time, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF332A15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isActive ? const Color(0xFFFFB300) : Colors.transparent),
      ),
      child: Column(
        children: [
          Text(name, style: TextStyle(fontSize: 12, color: isActive ? const Color(0xFFFFB300) : Colors.white60, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(time, style: TextStyle(fontSize: 10, color: isActive ? const Color(0xFFFFB300) : Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildSliderDisplay(String label, double value, Color activeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70)),
            Text("${value.toInt()}", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: activeColor)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: value / 100,
          backgroundColor: Colors.white10,
          valueColor: AlwaysStoppedAnimation<Color>(activeColor),
          minHeight: 5,
        ),
      ],
    );
  }

  Widget _buildStatBox(String title, String value, IconData icon, {Color valueColor = Colors.white}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFF181C26), borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Icon(icon, color: Colors.white54, size: 20),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: valueColor)),
          ],
        ),
      ),
    );
  }
}
