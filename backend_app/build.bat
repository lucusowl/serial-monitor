@ECHO off
SETLOCAL EnableDelayedExpansion

SET "SRC_NAME=router.py"
SET "EXE_NAME=router.exe"
SET "VENV_PATH=..\.venv"
SET "DST_PATH=..\flutter_app\bin"

@REM pyinstaller로 배포파일 생성
ECHO Generate executable file.
CALL %VENV_PATH%\Scripts\activate.bat
pyinstaller --onefile --icon=NONE --name %EXE_NAME% %SRC_NAME%

@REM 배포파일 flutter_app으로 이동
@REM 같은 이름의 파일이 있으면 백업
IF EXIST "%DST_PATH%\%EXE_NAME%" (
    ECHO Backup existing executable.
    SET "DTT=%time: =0%"
    SET "DTD=%date%"
    SET "DT=!DTD:~0,4!!DTD:~5,2!!DTD:~8,2!-!DTT:~0,2!!DTT:~3,2!!DTT:~6,2!"
    REN "%DST_PATH%\%EXE_NAME%" "%EXE_NAME:.exe=.backup-%!DT!.exe"
)
ECHO copy to flutter_app.
COPY /Y dist\%EXE_NAME% %DST_PATH%\%EXE_NAME%

@REM 생성된 임시 파일 및 디렉토리 정리
@REM rmdir /S /Q build
@REM rmdir /S /Q dist
@REM del /Q "%EXE_NAME:.exe=.spec%"

ECHO Build and Move Done.
PAUSE