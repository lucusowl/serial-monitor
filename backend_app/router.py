import sys
import json
import threading
import traceback
from serial import Serial
from serial.tools import list_ports

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
    reader_thread = None

    def stdin_loop():
        nonlocal ser
        nonlocal reader_thread
        port_name = ''
        for line in sys.stdin:
            cmd = json.loads(line)
            try:
                if cmd['CMD'] == 'LIST':
                    list_ports_cmd()
                elif cmd['CMD'] == 'OPEN':
                    ser = Serial(cmd['PORT'], cmd['BAUD'], timeout=1)
                    reader_thread = threading.Thread(target=reader, daemon=True)
                    reader_thread.start()
                    port_name = cmd['PORT']
                    print(json.dumps({"EVENT":"OPENED", "PORT":port_name}), flush=True)
                elif cmd['CMD'] == 'CLOSE':
                    # reader 종료
                    ser.cancel_read()
                    ser.close()
                    print(json.dumps({"EVENT":"CLOSED", "PORT":port_name}), flush=True)
                elif cmd['CMD'] == 'WRITE':
                    # ser.write(bytes.fromhex(cmd['DATA']))
                    ser.write(cmd['DATA'].encode('utf-8'))
                else:
                    print(json.dumps({"EVENT":"ALERT","MESSAGE":"Invalid Protocol Detected."}), flush=True)
            except Exception as e:
                print(f"{e}\n{traceback.format_exc()}", flush=True, file=sys.stderr)

    def reader():
        while ser and ser.is_open:
            try:
                data = ser.read(ser.in_waiting or 1)
                if data:
                    print(json.dumps({"EVENT":"DATA","DATA":data.hex()}), flush=True)
            except Exception as e:
                print(f"{e}\n{traceback.format_exc()}", flush=True, file=sys.stderr)

    stdin_thread = threading.Thread(target=stdin_loop, daemon=True)
    stdin_thread.start()
    print(json.dumps({"EVENT":"INIT"}), flush=True)
    stdin_thread.join()

if "__main__" == __name__:
    main()