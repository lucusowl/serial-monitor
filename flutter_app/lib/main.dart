import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class _PortEntry {
  final String device;
  final String? name;
  final String? description;
  final String? hwid;
  final int? vid;
  final int? pid;
  final String? serial;
  final String? location;
  final String? manufacturer;
  final String? product;
  final String? interface;

  _PortEntry({
    required this.device,
    this.name,
    this.description,
    this.hwid,
    this.vid,
    this.pid,
    this.serial,
    this.location,
    this.manufacturer,
    this.product,
    this.interface,
  });
}

class _LogEntry {
  final StringBuffer text;
  final bool isError;
  final bool isFromPort;
  final bool isFromClient;
  final DateTime startTimestamp;
  DateTime endTimestamp;

  _LogEntry({
    required this.text,
    required this.isError,
    required this.isFromPort,
    required this.isFromClient,
    required this.startTimestamp,
    required this.endTimestamp,
  });
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
  final List<_PortEntry> portEntries = [];
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
        .listen(
          (line) => _handleError(errorMessage: line, isFromClient: false),
          onError: (error) => _handleError(errorMessage: error),
        );
    stdoutSub = pythonProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _handleOutput(text: line),
          onError: (error) => _handleError(errorMessage: error),
        );
  }

  Future<void> routerExit() async {
    await stdoutSub?.cancel();
    await stderrSub?.cancel();
    pythonProcess?.kill();
  }

  void portScan() async {
    String messageString = jsonEncode(const {"CMD": "LIST"});
    pythonProcess?.stdin.writeln(messageString);
    _handleOutput(text: messageString, isFromClient: true);
  }

  void portConnect() async {
    if (selectedPort == null || (selectedBaud == 'custom' && customBaudController.text.isEmpty)) {
      // TODO: 부족한 입력 처리(포커스 이동, 등)
      return;
    }

    final baud = (selectedBaud == 'custom') ? customBaudController.text : selectedBaud;
    String messageString = jsonEncode({"CMD":"OPEN","PORT":selectedPort!,"BAUD":baud});
    pythonProcess?.stdin.writeln(messageString);
    _handleOutput(text: messageString, isFromClient: true);
  }

  void portDisconnect() {
    String messageString = jsonEncode({"CMD": "CLOSE", "PORT":selectedPort!});
    pythonProcess?.stdin.writeln(messageString);
    _handleOutput(text: messageString, isFromClient: true);
  }

  void sendData() {
    if (!isConnected) return;
    String data = inputController.text;
    switch (selectedEnding) {
      case 'New Line':        data += '\n'; break;
      case 'Carriage Return': data += '\r'; break;
      case 'Both CR & NL':    data += '\r\n'; break;
    }
    String messageString = jsonEncode({"CMD": "WRITE", "DATA": data});
    pythonProcess?.stdin.writeln(messageString);
    _handleOutput(text: messageString, isFromClient: true);
    inputController.clear();
  }

  /// 인자 유효성  
  /// 프로토콜 구분  
  /// 프로토콜 메세지 설정  
  /// 구분된 프로토콜 각 후처리 설정  
  void _handleOutput({
    required String text,
    bool isFromClient = false,
  }) {
    late final String logMessage;
    bool isFromPort = false; // only EVENT.DATA -> true
    final Map<String,dynamic> messageObject = jsonDecode(text);

    if (messageObject.containsKey("EVENT")) { // router/server(only DATA) -> client
      switch (messageObject["EVENT"]) {
        case "DATA":
          // 후처리 :: 문자 변환
          // messageObject["DATA"] :: hex-Stirng -> utf8(기본)
          logMessage = messageObject["DATA"];
          isFromPort = true;
          break;
        case "INIT": logMessage = "Router 준비 완료"; break;
        case "OPENED":
          setState(() => isConnected = true);
          logMessage = "Port (${messageObject["PORT"] ?? "(No Port)"}) 연결 성공";
          break;
        case "CLOSED":
          setState(() => isConnected = false);
          logMessage = "Port (${messageObject["PORT"] ?? "(No Port)"}) 연결 해제 성공";
          break;
        case "PORT":
          // 후처리:: 목록 갱신
          portEntries.clear();
          for (Map<String,dynamic> portInfo in messageObject["PORTS"]){
            portEntries.add(_PortEntry(
              device: portInfo["DEVICE"],
              name: portInfo["name"],
              description: portInfo["description"],
              hwid: portInfo["hwid"],
              vid: portInfo["vid"],
              pid: portInfo["pid"],
              serial: portInfo["serial"],
              location: portInfo["location"],
              manufacturer: portInfo["manufacturer"],
              product: portInfo["product"],
              interface: portInfo["interface"],
            ));
          }
          logMessage = "연결 가능 Port 목록 갱신 성공";
          break;
        case "ALERT": logMessage = messageObject["MESSAGE"]; break;
        case "ERROR":
          _handleError(
            errorMessage: messageObject["MESSAGE"],
            // traceback: messageObject["TRACEBACK"],
            isFromClient: isFromClient,
          );
          break;
        default: 
          _handleError(
            errorMessage: "Invalid Protocol Detected. Type (${messageObject['EVENT']}) of EVENT is not exist",
            isFromClient: isFromClient
          );
          return;
      }
    } else if (messageObject.containsKey("CMD")) { // client -> router
      switch (messageObject["CMD"]) {
        case "WRITE": logMessage = messageObject["DATA"] ?? ""; break;
        case "OPEN": logMessage = "Port (${(messageObject["PORT"]) ?? "(No Port)"}, baud: ${messageObject["BAUD"] ?? "(No baud)"})에 연결 요청"; break;
        case "CLOSE": logMessage = "Port (${(messageObject["PORT"]) ?? "(No Port)"}) 연결 해제 요청"; break;
        case "LIST": logMessage = "연결 가능 Port 목록 요청"; break;
        default:
          _handleError(
            errorMessage: "Invalid Protocol Detected. Type (${messageObject['CMD']}) of CMD is not exist", 
            isFromClient: isFromClient
          );
          return;
      }
    } else {
      _handleError(
        errorMessage: "Invalid Protocol Detected. Require Type of Protocol.",
        isFromClient: isFromClient,
      );
      return;
    }
    _logger(
      message: logMessage,
      isFromPort: isFromPort,
      isFromClient: isFromClient,
    );
  }

  void _handleError({
    required String errorMessage,
    bool isFromClient = true,
    // dynamic stackTrace,
  }) {
    _logger(
      message: errorMessage,
      isError: true,
      isFromClient: isFromClient,
    );
  }

  void _logger({
    required String message,
    bool isError = false,
    bool isFromPort = false,
    bool isFromClient = true,
  }) {
    // 로깅 시간을 기준
    final DateTime now = DateTime.now();

    // if (이전 로그와 합쳐야 하는 경우 == DATA 내용이 아직 구분자로 끝나지 않은 경우) {
    //   setState(() {
    //     log.last.text.write(text);
    //     log.last.timestamp = now;
    //   });
    // }
    setState(() {
      log.add(_LogEntry(
        text: StringBuffer(message),
        isError: isError,
        isFromPort: isFromPort,
        isFromClient: isFromClient,
        startTimestamp: now,
        endTimestamp: now,
      ));
    });
    // outputLog move to last line
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

  Widget buildToolbar() => Row(
    spacing: 16.0,
    children: [
      ElevatedButton(onPressed: portScan, child: const Text('스캔')),
      DropdownButton<String>(
        hint: const Text('Select Port'),
        value: selectedPort,
        onChanged: (val) => setState(() => selectedPort = val),
        items: portEntries.map((e) => DropdownMenuItem(value: e.device, child: Row(children: [Icon(Icons.usb), Text(e.device)]))).toList(),
        // TODO: 인식된 디바이스 정보 표기, e.g. 'COM6 (Arduino Uno)'
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
    child: SelectionArea(
      child: Container(
        padding: const EdgeInsets.all(8.0),
        color: Colors.black,
        child: ListView.builder(
          controller: scrollController,
          itemCount: log.length,
          itemBuilder: (context, index) {
            final entry = log[index];
            return Text(
              '${showTimestamp ? '[${entry.endTimestamp.toIso8601String()}]' : ''}${entry.text}\n',
              style: TextStyle(height: 0.7, color: entry.isError ? Colors.red : entry.isFromClient ? Colors.green : Colors.white),
            );
          },
        ),
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