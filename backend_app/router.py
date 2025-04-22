import sys
import json
import threading
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

    def stdin_loop():
        nonlocal ser
        for line in sys.stdin:
            cmd = json.loads(line)
            if cmd['CMD'] == 'LIST':
                list_ports_cmd()
            elif cmd['CMD'] == 'OPEN':
                ser = Serial(cmd['PORT'], cmd['BAUD'], timeout=1)
                print(json.dumps({"EVENT":"OPENED", "PORT":cmd['PORT']}), flush=True)
                threading.Thread(target=reader, daemon=True).start()
            elif cmd['CMD'] == 'CLOSE':
                ser.close()
                print(json.dumps({"EVENT":"CLOSED"}), flush=True)
            elif cmd['CMD'] == 'WRITE':
                # ser.write(bytes.fromhex(cmd['DATA']))
                ser.write(cmd['DATA'].encode('utf-8'))
            else:
                print(json.dumps({"EVENT":"ALERT","MESSAGE":"Invalid Protocol"}), flush=True)

    def reader():
        while ser and ser.is_open:
            data = ser.read(ser.in_waiting or 1)
            if data:
                print(json.dumps({"EVENT":"DATA","DATA":data.hex()}))

    stdin_thread = threading.Thread(target=stdin_loop, daemon=True)
    stdin_thread.start()
    stdin_thread.join()

if "__main__" == __name__:
    main()