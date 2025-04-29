import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

const routerMinVersion = "v0.5.3";

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

  String info() {
    return 'device:$device\n'
    'name:$name\n'
    'description:$description\n'
    'hwid:$hwid\n'
    'vid:$vid(0x${vid?.toRadixString(16)})\n'
    'pid:$pid(0x${pid?.toRadixString(16)})\n'
    'serial:$serial\n'
    'location:$location\n'
    'manufacturer:$manufacturer\n'
    'product:$product\n'
    'interface:$interface';
  }
}

class _LogEntry {
  final List<int> content;
  final bool isError;
  final bool isFromPort;
  final bool isFromClient;
  final DateTime startTimestamp;
  DateTime endTimestamp;

  _LogEntry({
    required this.content,
    required this.isError,
    required this.isFromPort,
    required this.isFromClient,
    required this.startTimestamp,
    required this.endTimestamp,
  });
}

enum ProcessState {
  wait,
  enabled,
  disabled,
  disabledFromUnknown, // 예기지 못한 오류
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
  bool showDetail = false;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController customBaudController = TextEditingController();
  final TextEditingController inputController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  late final FocusNode _portFieldFocusNode = FocusNode();
  late final FocusNode _baudCustomFieldFocusNode = FocusNode();

  bool flagDataLineFeed = true;
  final List<_LogEntry> log = [];

  ProcessState routerProcessState = ProcessState.wait;
  String routerDisabledMessage = "라우터 미동작\n초기 오버레이 메세지";
  Process? routerProcess;
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
    _portFieldFocusNode.dispose();
    _baudCustomFieldFocusNode.dispose();
    routerExit();
    super.dispose();
  }

  Future<void> routerStart() async {
    try {
      routerProcess = await Process.start('bin/router.exe', []);
      if (routerProcess != null) {
        routerDisabledMessage = "비정상적으로 오버레이가 열림";
        setState(() => routerProcessState = ProcessState.enabled);
      }
      stderrSub = routerProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _handleError(errorMessage: line, isFromClient: false),
            onError: (error, stackTrace) {
              if (error is FormatException) {
                _handleError(errorMessage: "비정상적인 형식의 값이 전달되었습니다. 통신 연결을 확인해주세요.");
              } else {
                _handleError(errorMessage: error.toString(), stackTrace: stackTrace);
              }
            },
          );
      stdoutSub = routerProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _handleOutput(messageObject: jsonDecode(line)),
            onError: (error, stackTrace) {
              if (error is FormatException) {
                _handleError(errorMessage: "비정상적인 형식의 값이 전달되었습니다. 통신 연결을 확인해주세요.");
              } else {
                _handleError(errorMessage: error.toString(), stackTrace: stackTrace);
              }
            },
          );
      // 앱 실행 도중 프로세스가 종료된 경우
      // 정상종료: exitCode = -1
      routerProcess!.exitCode.then((exitCode) {
        if (exitCode != -1) {_handleError(errorMessage: "비정상종료, ExitCode:$exitCode");}
      });

    } on ProcessException catch (error/*, stackTrace*/) {
      routerDisabledMessage = "라우터 연결 불가\n\n라우터 실행파일을 확인한 뒤\n아래 버튼을 누르거나 앱을 재실행바랍니다.";
      setState(() => routerProcessState = ProcessState.disabled);
      _handleError(errorMessage: "Process Error Code: ${error.errorCode}, Message: ${error.message}\n$error", /*stackTrace: stackTrace*/); // 임시 stackTrace 비가시화
      routerExit();
    } catch (error, stackTrace) {
      routerDisabledMessage = "라우터 동작 불가\n\n라우터 동작 중 예기지 못한 프로세스 또는 스트림 오류 발생\n\n앱을 종료하고 재시작바랍니다.";
      setState(() => routerProcessState = ProcessState.disabledFromUnknown);
      _handleError(errorMessage: error.toString(), stackTrace: stackTrace);
      routerExit();
    }
  }

  Future<void> routerExit() async {
    await stdoutSub?.cancel();
    await stderrSub?.cancel();
    if (routerProcess != null) {
      routerProcess!.kill();
      final exitCode = await routerProcess!.exitCode; // 프로세스 정상 종료까지 대기
      if (exitCode != -1) {_handleError(errorMessage: "비정상종료, ExitCode:$exitCode");}
    }
  }

  void portScan() async {
    Map<String,dynamic> messageObject = const {"CMD": "LIST"};
    routerProcess?.stdin.writeln(jsonEncode(messageObject));
    _handleOutput(messageObject: messageObject, isFromClient: true);
  }

  void portConnect() async {
    // 유효성 검사 => focus 이동
    if (_formKey.currentState!.validate()) {
      final baud = (selectedBaud == 'custom') ? customBaudController.text : selectedBaud;
      Map<String,dynamic> messageObject = {"CMD":"OPEN","PORT":selectedPort!,"BAUD":baud};
      routerProcess?.stdin.writeln(jsonEncode(messageObject));
      _handleOutput(messageObject: messageObject, isFromClient: true);
    } else {
      if (selectedPort == null) { // port 없음
        FocusScope.of(context).requestFocus(_portFieldFocusNode);
      } else if (selectedBaud == 'custom') { // baud custom 값이 불가
        FocusScope.of(context).requestFocus(_baudCustomFieldFocusNode);
      }
    }
  }

  void portDisconnect() {
    // 유효성 검사 => focus 이동
    if (_formKey.currentState!.validate()) {
      Map<String,dynamic> messageObject = {"CMD": "CLOSE", "PORT":selectedPort!};
      routerProcess?.stdin.writeln(jsonEncode(messageObject));
      _handleOutput(messageObject: messageObject, isFromClient: true);
    } else {
      if (selectedPort == null) { // port 없음
        FocusScope.of(context).requestFocus(_portFieldFocusNode);
        _handleError(errorMessage: "연결 해제할 Port가 지정되어 있지 않습니다. Port 목록을 갱신해주세요.");
      }
    }
  }

  void sendData() {
    if (!isConnected) return;
      final utf8Encoder = Utf8Encoder();
    String data = inputController.text;
    switch (selectedEnding) {
      case 'New Line':        data += '\n'; break;
      case 'Carriage Return': data += '\r'; break;
      case 'Both CR & NL':    data += '\r\n'; break;
    }
    // string -> Uint8List(utf8) -> hex-string
    final StringBuffer buffer = StringBuffer();
    for (var byte in utf8Encoder.convert(data)) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    Map<String,dynamic> messageObject = {"CMD": "WRITE", "DATA": buffer.toString()};
    routerProcess?.stdin.writeln(jsonEncode(messageObject)); // string -> hex-string
    _handleOutput(messageObject: {"CMD": "WRITE", "DATA": data}, isFromClient: true); // string -> string
    inputController.clear();
  }

  void _handleOutput({
    required Map<String,dynamic> messageObject,
    bool isFromClient = false,
  }) {
    late final String logMessage;
    bool isFromPort = false; // only EVENT.DATA -> true

    if (messageObject.containsKey("EVENT")) { // router/server(only DATA) -> client
      switch (messageObject["EVENT"]) {
        case "DATA":
          // 후처리 :: 문자 처리 -> _logger
          logMessage = messageObject["DATA"];
          isFromPort = true;
          break;
        case "INIT":
          if (routerMinVersion.compareTo(messageObject["VERSION"] ?? "") > 0) {
            routerDisabledMessage = "라우터 연결 불가\n\n라우터 실행파일을 확인한 뒤\n아래 버튼을 누르거나 앱을 재실행바랍니다.\n\n실행중인 라우터 버전:(${messageObject["VERSION"]}), 실행가능 최소 버전:($routerMinVersion)";
            setState(() => routerProcessState = ProcessState.disabled);
            _handleError(
              errorMessage: "라우터 버전 호환 불가. 실행중인 라우터 버전:(${messageObject["VERSION"]}), 실행가능 최소 버전:($routerMinVersion)",
              isFromClient: isFromClient
            );
            routerExit();
            return;
          } else {
            logMessage = "Router 준비 완료";
          }
          break;
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
          if (selectedPort != null) {
            bool flagPortInclude = false;
            for (_PortEntry port in portEntries) {
              if (port.device == selectedPort) {
                flagPortInclude = true;
                break;
              }
            }
            if (!flagPortInclude) {selectedPort = null;}
          }
          logMessage = "연결 가능 Port 목록 갱신";
          break;
        case "ALERT": logMessage = messageObject["MESSAGE"]; break;
        case "ERROR":
          _handleError(
            errorMessage: messageObject["MESSAGE"],
            stackTrace: messageObject["TRACEBACK"],
            isFromClient: isFromClient,
          );
          return;
        default:
          _handleError(
            errorMessage: "Invalid Protocol Detected. Type (${messageObject['EVENT']}) of EVENT is not exist",
            isFromClient: isFromClient
          );
          return;
      }
    } else if (messageObject.containsKey("CMD")) { // client -> router/server(only WRITE)
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
    StackTrace? stackTrace,
  }) {
    _logger(
      message: "$errorMessage${(stackTrace == null) ? '': '\n$stackTrace'}",
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

    // hex-Stirng -> utf8(기본)
    if (isFromPort) {
      final List<int> bytes = <int>[];
      for (var i=0; i < message.length; i+=2) {
        // hex-string -> List<int>
        final String byte = message.substring(i, i+2);
        try {
          bytes.add(int.parse(byte, radix:16));
        } on FormatException {
          // 에러 전달, hexstr 올바르지 않은 형식
          _handleError(
            errorMessage: "Invalid Hexadecimal String Detected.\n$message",
            isFromClient: isFromClient,
          );
          return;
        }
        if (bytes.last == 0x0A) {
          if (flagDataLineFeed) {
            setState(() {
              log.add(_LogEntry(
                content: bytes,
                isError: isError,
                isFromPort: isFromPort,
                isFromClient: isFromClient,
                startTimestamp: now,
                endTimestamp: now,
              ));
            });
          } else {
            // 이전 로그와 합치기
            setState(() {
              log.last.content.addAll(bytes);
              log.last.endTimestamp = now;
            });
          }
          bytes.clear();
          flagDataLineFeed = true;
        }
      }
      // 남은 문자 추가
      if (bytes.isNotEmpty) {
        if (flagDataLineFeed) {
          setState(() {
            log.add(_LogEntry(
              content: bytes,
              isError: isError,
              isFromPort: isFromPort,
              isFromClient: isFromClient,
              startTimestamp: now,
              endTimestamp: now,
            ));
          });
        } else {
          // 이전 로그와 합치기
          setState(() {
            log.last.content.addAll(bytes);
            log.last.endTimestamp = now;
          });
        }
        if (bytes.last == 0x0A) {
          flagDataLineFeed = true;
        } else {
          flagDataLineFeed = false; // 이 다음은 합쳐야 함
        }
      }
    } else {
      final utf8Encoder = Utf8Encoder();
      setState(() {
        log.add(_LogEntry(
          content: utf8Encoder.convert(message), // String -> List<int>
          isError: isError,
          isFromPort: isFromPort,
          isFromClient: isFromClient,
          startTimestamp: now,
          endTimestamp: now,
        ));
      });
      flagDataLineFeed = true; // 데이터 수신도중 다른 메세지를 받으면 자동 줄바꿈
    }

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

  String _logConvertOutput(List<int> buffer) {
    if (buffer.isEmpty) return '';
    final utf8Decoder = Utf8Decoder(allowMalformed: true);
    if (buffer.last == 0x0A) {
      return utf8Decoder.convert(buffer, 0, buffer.length-1);
    } else {
      return utf8Decoder.convert(buffer);
    }
  }

  Widget buildToolbar() => Form(
    key: _formKey,
    child: Row(
      spacing: 8.0,
      children: [
        ElevatedButton(onPressed: portScan, child: const Text('스캔')),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<String>(
            focusNode: _portFieldFocusNode,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            hint: const Text('Select Port'),
            value: selectedPort,
            onChanged: (isConnected) ? null : (val) => setState(() => selectedPort = val),
            validator: (value) => (value == null) ? 'Port 미선택' : null,
            items: portEntries.map((e) => DropdownMenuItem(
                value: e.device,
                child: Row(
                  spacing: 8.0,
                  children: [
                    Tooltip(
                      message: e.info(),
                      child: const Icon(Icons.usb)
                    ),
                    Text(e.device)
                  ]
                )
              )).toList(),
          ),
        ),
        SizedBox(
          width: 95,
          child: DropdownButtonFormField<String>(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            value: selectedBaud,
            onChanged: (isConnected) ? null : (val) => setState(() => selectedBaud = val!),
            items: baudRates.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          ),
        ),
        if (selectedBaud == 'custom')
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: customBaudController,
              focusNode: _baudCustomFieldFocusNode,
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'baud 미입력';
                } else if (int.tryParse(value) == null) {
                  return '비정수형 입력';
                } else {
                  return null;
                }
              },
            )
          ),
        (isConnected)
          ? ElevatedButton(onPressed: portDisconnect, child: const Text('해제'))
          : ElevatedButton(onPressed: portConnect, child: const Text('연결')),
      ],
    ),
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
        icon: Icon(showDetail ? Icons.schedule : Icons.schedule_outlined),
        onPressed: () => setState(() => showDetail = !showDetail),
        tooltip: '상세내용 표시'
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
            late final Color logColor;
            late final String logSubject;
            if (entry.isError) {
              logColor = Colors.red;
              if (entry.isFromClient) {logSubject = 'Client';}
              else {logSubject = 'Router';}
            } else if (entry.isFromPort) {
              logColor = Colors.white;
              logSubject = 'Port($selectedPort)';
            } else if (entry.isFromClient) {
              logColor = Colors.green;
              logSubject = 'Client';
            } else {
              logColor = Colors.yellow;
              logSubject = 'Router';
            }
            return Text(
              '${showDetail ? '[${entry.endTimestamp.toIso8601String()}][$logSubject]' : ''}${_logConvertOutput(entry.content)}',
              style: TextStyle(color: logColor),
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
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        value: selectedEnding,
        onChanged: (val) => setState(() => selectedEnding = val!),
        items: lineEndings.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    late Widget routerDisableOverlay;
    if (routerProcessState != ProcessState.enabled) {
      switch (routerProcessState) {
        case ProcessState.wait:
          routerDisableOverlay = const Center(child: CircularProgressIndicator());
          break;
        case ProcessState.disabled:
          routerDisableOverlay = Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 16.0,
              children: [
                Text(routerDisabledMessage),
                ElevatedButton(onPressed: routerStart, child: const Text("재실행")),
              ],
            ),
          );
          break;
        case ProcessState.disabledFromUnknown:
          routerDisableOverlay = Center(
            child: Text(routerDisabledMessage),
          );
          break;
        default:
          break;
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Serial Monitor')),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              spacing: 0.0,
              children: [
                buildToolbar(),
                const Divider(),
                buildTopControls(),
                buildOutputLog(),
                buildBottomInput(),
              ],
            ),
          ),
          // 라우터 연결 확인 오버레이
          if (routerProcessState != ProcessState.enabled) ...[
            Positioned.fill(child: Container(
              color: Colors.black54,
              child: routerDisableOverlay,
            ))
          ],
        ],
      ),
    );
  }
}