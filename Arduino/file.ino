#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define SERVICE_UUID        "12345678-1234-1234-1234-1234567890ab"  // Custom service UUID
#define CHARACTERISTIC_UUID "abcd1234-ab12-cd34-ef56-1234567890ab"  // Custom characteristic UUID
#define BUZZER_PIN          13  // GPIO pin for the buzzer

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

// Server callback to handle connection events
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    deviceConnected = true;
    Serial.println("Client connected.");
  }
  
  void onDisconnect(BLEServer* pServer) override {
    deviceConnected = false;
    Serial.println("Client disconnected.");
    // Restart advertising so the client can reconnect.
    pServer->getAdvertising()->start();
  }
};

// Characteristic callback to handle write events
class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    // Use Arduino String (instead of std::string) to avoid conversion issues
    String rxValue = pCharacteristic->getValue();
    Serial.print("Received Value: ");
    Serial.println(rxValue);
    
    // If the received value is not empty
    if (rxValue.length() > 0) {
      // Check for the command to activate the buzzer
      if (rxValue == "BUZZER_ON") {
         Serial.println("Activating buzzer!");
         digitalWrite(BUZZER_PIN, HIGH);
         delay(3000);  // Keep buzzer on for 3 seconds
         digitalWrite(BUZZER_PIN, LOW);
         Serial.println("Buzzer deactivated.");
      }
    }
  }
};

void setup() {
  // Initialize serial communication for debugging
  Serial.begin(115200);
  
  // Setup the buzzer pin
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  // Initialize BLE and set the device name
  BLEDevice::init("ESP32_Tag");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  
  // Create the BLE service
  BLEService* pService = pServer->createService(SERVICE_UUID);
  
  // Create the characteristic and assign the write property and callback
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_WRITE
                    );
  pCharacteristic->setCallbacks(new CommandCallbacks());
  pCharacteristic->addDescriptor(new BLE2902());
  
  // Start the service
  pService->start();
  
  // Start advertising the service
  pServer->getAdvertising()->start();
  Serial.println("Waiting for a client connection to notify...");
}

void loop() {
  // Main loop does nothing – all work is done via BLE callbacks
  delay(1000);
}
