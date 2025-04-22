import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class _LogEntry {
  final String text;
  final bool isError;
  final bool isSent;
  final DateTime timestamp;

  _LogEntry({required this.text, required this.isError, required this.isSent, required this.timestamp});
}

void main() => runApp(const SerialMonitorApp());

class SerialMonitorApp extends StatelessWidget {
  const SerialMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Serial Monitor',
      home: const SerialMonitorScreen(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
    );
  }
}

class SerialMonitorScreen extends StatefulWidget {
  const SerialMonitorScreen({super.key});

  @override
  State<SerialMonitorScreen> createState() => _SerialMonitorScreenState();
}

class _SerialMonitorScreenState extends State<SerialMonitorScreen> {
  final List<String> baudRates = [
    'custom', '50', '150', '200', '300', '600', '1200', '1800', '2400', '4800',
    '9600', '19200', '38400', '57600', '115200'
  ];
  final List<String> lineEndings = [
    'No Line Ending', 'New Line', 'Carriage Return', 'Both CR & NL'
  ];

  String? selectedPort;
  String selectedBaud = '9600';
  String? customBaud;
  String selectedEnding = 'New Line';

  bool isConnected = false;
  bool autoScroll = true;
  bool showTimestamp = false;

  final TextEditingController inputController = TextEditingController();
  final TextEditingController customBaudController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  final List<_LogEntry> log = [];

  late Process? pythonProcess;
  StreamSubscription<String>? stdoutSub;
  StreamSubscription<String>? stderrSub;

  @override
  void initState() {
    super.initState();
    routerStart();
  }

  @override
  void dispose() {
    inputController.dispose();
    scrollController.dispose();
    customBaudController.dispose();
    routerExit();
    super.dispose();
  }

  Future<void> routerStart() async {
    pythonProcess = await Process.start('bin/router.exe', []);
    stderrSub = pythonProcess!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _handleOutput(line, true, false));
    stdoutSub = pythonProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _handleOutput(line, false, false));
  }

  Future<void> routerExit() async {
    stdoutSub?.cancel();
    stderrSub?.cancel();
    pythonProcess?.kill();
  }

  void portScan() async {
    pythonProcess?.stdin.writeln(jsonEncode({"CMD":"LIST"}));
  }

  void portConnect() async {
    if (selectedPort == null || (selectedBaud == 'custom' && customBaudController.text.isEmpty)) {
      // TODO: 부족한 입력 처리(포커스 이동, 등)
      return;
    }

    final baud = (selectedBaud == 'custom') ? customBaudController.text : selectedBaud;
    pythonProcess?.stdin.writeln(jsonEncode({"CMD":"OPEN","PORT":selectedPort,"BAUD":baud}));
    // TODO: 연결 요청 로그
    setState(() => isConnected = true);
  }

  void portDisconnect() {
    pythonProcess?.stdin.writeln(jsonEncode({"CMD": "CLOSE"}));
    // TODO: 연결 해제 요청 로그
    setState(() => isConnected = false);
  }

  void _handleOutput(String text, bool isError, bool isSent) {
    final now = DateTime.now();
    setState(() {
      log.add(_LogEntry(
        text: text,
        isError: isError,
        isSent: isSent,
        timestamp: now,
      ));
    });
    if (autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void sendData() {
    if (!isConnected) return;
    String data = inputController.text;
    switch (selectedEnding) {
      case 'New Line':        data += '\n'; break;
      case 'Carriage Return': data += '\r'; break;
      case 'Both CR & NL':    data += '\r\n'; break;
    }
    pythonProcess?.stdin.writeln(jsonEncode({"CMD": "WRITE", "DATA": data}));
    _handleOutput(data, false, true);
    inputController.clear();
  }

  Widget buildToolbar() => Row(
    spacing: 16.0,
    children: [
      ElevatedButton(onPressed: portScan, child: const Text('스캔')),
      DropdownButton<String>(
        hint: const Text('Select Port'),
        value: selectedPort,
        onChanged: (val) => setState(() => selectedPort = val),
        items: [
          // TODO: 실전 구현시 실제 포트 목록 연동 필요
          // DropdownMenuItem(value: 'COM6', child: Row(children: const [Icon(Icons.usb), Text('COM6 (Arduino Uno)')])),
          // DropdownMenuItem(value: 'COM7', child: Row(children: const [Icon(Icons.usb), Text('COM7 (Unknown)')])),
        ],
      ),
      DropdownButton<String>(
        value: selectedBaud,
        onChanged: (val) => setState(() => selectedBaud = val!),
        items: baudRates.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      ),
      if (selectedBaud == 'custom')
        SizedBox(width: 80, child: TextField(controller: customBaudController, keyboardType: TextInputType.number)),
      (isConnected)
        ? ElevatedButton(onPressed: portDisconnect, child: const Text('해제'))
        : ElevatedButton(onPressed: portConnect, child: const Text('연결')),
    ],
  );

  Widget buildTopControls() => Row(
    spacing: 8.0,
    children: [
      IconButton(
        icon: Icon(autoScroll ? Icons.check_box : Icons.check_box_outline_blank),
        onPressed: () => setState(() => autoScroll = !autoScroll),
        tooltip: '자동스크롤'
      ),
      IconButton(
        icon: Icon(showTimestamp ? Icons.schedule : Icons.schedule_outlined),
        onPressed: () => setState(() => showTimestamp = !showTimestamp),
        tooltip: '타임스탬프 표시'
      ),
      IconButton(
        icon: const Icon(Icons.delete),
        onPressed: () => setState(() => log.clear()),
        tooltip: '모든 출력 지우기'
      )
    ],
  );

  Widget buildOutputLog() => Expanded(
    child: Container(
      padding: const EdgeInsets.all(8.0),
      color: Colors.black,
      child: ListView.builder(
        controller: scrollController,
        itemCount: log.length,
        itemBuilder: (context, index) {
          final entry = log[index];
          return Text(
            '${showTimestamp ? '[${entry.timestamp.toIso8601String()}]' : ''}${entry.text}',
            style: TextStyle(color: entry.isError ? Colors.red : entry.isSent ? Colors.green : Colors.white),
          );
        },
      ),
    ),
  );

  Widget buildBottomInput() => Row(
    spacing: 16.0,
    children: [
      ElevatedButton(onPressed: sendData, child: const Text('전송')),
      Expanded(
        child: TextField(
          controller: inputController,
          enabled: isConnected,
          decoration: InputDecoration(
            hintText: isConnected ? '데이터 입력...' : 'Not connected. Select a port to connect'
          ),
          onSubmitted: (_) => sendData(),
        ),
      ),
      DropdownButton<String>(
        value: selectedEnding,
        onChanged: (val) => setState(() => selectedEnding = val!),
        items: lineEndings.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Serial Monitor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          spacing: 0.0,
          children: [
            buildToolbar(),
            buildTopControls(),
            buildOutputLog(),
            buildBottomInput(),
          ],
        ),
      ),
    );
  }
}