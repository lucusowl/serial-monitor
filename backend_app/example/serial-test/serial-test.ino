unsigned long prevMillis = 0;
int counter = 0;

void setup() {
  Serial.begin(9600);
  while (!Serial) {} // 시리얼 포트 연결 대기 (USB CDC인 보드에서만 필요)
  Serial.println("Port is available.");
}

void loop() {
  unsigned long currentMillis = millis();

  // 1초마다 counter 출력 후 +100
  if (currentMillis - prevMillis >= 1000) {
    prevMillis = currentMillis;
    Serial.println(counter);
    counter += 100;
  }

  // 시리얼 입력 처리
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim(); // 개행·공백 제거

    if (input == "ADD") {
      counter += 1;
      Serial.println("ADDED");
    }
    else if (input == "SUB") {
      counter -= 1;
      Serial.println("SUBED");
    }
    else {
      Serial.print("ECHO ");
      Serial.println(input);
    }
  }
}