# Serial Monitor
![GitHub Release](https://img.shields.io/github/v/release/lucusowl/serial-monitor)
![GitHub License](https://img.shields.io/github/license/lucusowl/serial-monitor)

**Serial Monitor**는 시리얼 장치를 탐색 및 연결하고 실시간으로 데이터를 송수신할 수 있도록 도와주는 간단한 터미널 도구입니다.  
시리얼 포트 선택, 전송속도 설정, 실시간 로그 확인, 등 직관적인 UI로 시리얼 통신 환경을 제공합니다.  
이 도구는 Flutter를 기반으로 제작되었습니다.  

## 설치 및 사용 Installation & Usage
[![Windows x64](https://img.shields.io/badge/Windows_x64-blue.svg)](https://github.com/lucusowl/serial-monitor/releases/download/v1.0.0/release-windows-x64-v1.0.0.zip)

실행파일을 환경에 맞게 [다운로드](https://github.com/lucusowl/serial-monitor/releases/latest/)하여 사용할 수 있습니다.  

## 기능 Feature

- **연결 포트 스캔 & 선택**: 연결된 포트들을 스캔하고 통신할 포트를 선택하여 데이터 송수신 환경을 제공합니다.

- **전송 속도(baud rate) 설정**: 데이터 전송 속도를 사용자가 원하는 값으로 설정할 수 있습니다. 기본값은 9600.

- **송수신 데이터 표시**: 송수신 되는 데이터 로그를 UTF8 형식(한글과 같은 유니코드 지원)으로 출력합니다.

- **송신 끝구분자 선택**: 송신 데이터의 맨 끝에 붙을 문자를 선택할 수 있습니다.
  - No Line Ending: 어떤 문자도 붙이지 않음
  - New Line: (기본값) '\n' 붙임
  - Carriage Return: '\r' 붙임
  - Both CR & NL: '\n\r' 붙임

- **자동스크롤**: 항상 최근에 표시된 내용이 보이도록 출력 화면을 자동으로 스크롤할 수 있습니다.

- **상세내용 표시**: 자세한 로그 생성 시각과 보낸 주체(Client, Router, Port)를 표시합니다.

- **모든 출력 지우기**: 출력 화면 속 모든 내용을 지웁니다.


## 라이선스 License

본 프로젝트는 [MIT License](LICENSE) 하에 배포됩니다.  
third-party 라이선스는 [NOTICE](NOTICE) 파일에도 요약·고지되어 있습니다.   
