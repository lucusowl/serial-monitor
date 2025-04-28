import sys
import json
import threading
import traceback
from serial import Serial
from serial.tools import list_ports

__version__ = "v0.5.3"

def list_ports_cmd():
    ports = [
        {
            "DEVICE":p.device, # name to Serial
            "name":p.name,
            "description":p.description,
            "hwid":p.hwid,
            "vid":p.vid,
            "pid":p.pid,
            "serial":p.serial_number,
            "location":p.location,
            "manufacturer":p.manufacturer,
            "product":p.product,
            "interface":p.interface
        } for p in list_ports.comports()
    ]
    print(json.dumps({"EVENT":"PORT", "PORTS":ports}), flush=True)

def main():
    ser:Serial = None
    port_name = ''
    def stdin_loop():
        nonlocal ser
        nonlocal port_name
        reader_thread = None
        reader_stop_event = None
        for line in sys.stdin:
            # print(json.dumps({"EVENT":"ALERT","MESSAGE":line}), flush=True) # debug
            cmd = json.loads(line)
            try:
                if cmd['CMD'] == 'LIST':
                    list_ports_cmd()
                elif cmd['CMD'] == 'OPEN':
                    try:
                        if ('PORT' not in cmd) or (cmd['PORT'] == None) or (len(cmd['PORT']) == 0):
                            raise Exception("연결할 port를 지정해주세요.")
                        elif ('BAUD' not in cmd) or (cmd['BAUD'] == None) or (len(cmd['BAUD']) == 0):
                            raise Exception("baud 값을 지정해주세요.")
                        port_name = cmd['PORT']
                        ser = Serial(cmd['PORT'], cmd['BAUD'], timeout=1)
                        if (ser is None) or (not ser.is_open):
                            raise Exception("지정한 port를 연결할 수 없습니다. 다시 지정해주세요.")
                        reader_stop_event = threading.Event()
                        reader_thread = threading.Thread(target=reader, args=(reader_stop_event,), daemon=True)
                        reader_thread.start()
                        print(json.dumps({"EVENT":"OPENED", "PORT":port_name}), flush=True)
                    except Exception as e:
                        print(json.dumps({"EVENT":"ERROR", "MESSAGE":f"Port ({port_name}) 연결 실패\n{e}"}), flush=True)
                elif cmd['CMD'] == 'CLOSE':
                    try:
                        reader_stop_event.set()
                        ser.cancel_read()
                        reader_thread.join()
                        ser.close()
                        print(json.dumps({"EVENT":"CLOSED", "PORT":port_name}), flush=True)
                        port_name = ''
                    except Exception as e:
                        print(json.dumps({"EVENT":"ERROR", "MESSAGE":f"Port ({port_name}) 연결 해제 실패\n{e}"}), flush=True)
                elif cmd['CMD'] == 'WRITE':
                    ser.write(bytes.fromhex(cmd['DATA']))
                else:
                    print(json.dumps({"EVENT":"ALERT","MESSAGE":"Invalid Protocol Detected."}), flush=True)
            except Exception as e:
                print(f"[STDIN]{e}\n{traceback.format_exc()}", flush=True, file=sys.stderr)

    def reader(stop_event:threading.Event):
        while ser and ser.is_open:
            if stop_event.is_set():
                break
            try:
                data = ser.read(ser.in_waiting or 1)
                if data:
                    print(json.dumps({"EVENT":"DATA","DATA":data.hex()}), flush=True)
            except Exception as e:
                print(f"[READER]{e}\n{traceback.format_exc()}", flush=True, file=sys.stderr)
        print(json.dumps({"EVENT":"ALERT","MESSAGE":f"Port ({port_name}) 읽기 종료"}), flush=True)

    stdin_thread = threading.Thread(target=stdin_loop, daemon=True)
    stdin_thread.start()
    print(json.dumps({"EVENT":"INIT","VERSION":__version__}), flush=True)
    stdin_thread.join()

if "__main__" == __name__:
    main()