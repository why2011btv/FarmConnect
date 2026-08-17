import time
import random
import requests

BACKEND_URL = "https://farmconnect-production-500d.up.railway.app/v1/sensors/ingest"

# Per-node credentials, printed by `npm run provision` when this node's farm was set up.
# Each node has its own key: a key recovered from this device cannot write readings for any other
# node, and cannot register a device that was not provisioned in advance.
DEVICE_ID = "<deviceId from provisioning output>"
DEVICE_KEY = "<x-device-key from provisioning output>"

DEVICE_NAME = "PB Node A1"
FARM_NAME = "Smith Vineyard"
LOCATION_LABEL = "Block 1"


def read_sensors():
    # Replace this block with real sensor reads
    return {
        "soil_moisture": round(random.uniform(20, 60), 1),
        "temperature": round(random.uniform(18, 32), 1),
        "humidity": round(random.uniform(35, 80), 1),
    }


while True:
    values = read_sensors()
    payload = {
        "deviceId": DEVICE_ID,
        "deviceName": DEVICE_NAME,
        "farmName": FARM_NAME,
        "locationLabel": LOCATION_LABEL,
        "status": "online",
        "readings": [
            {"sensorType": "soil_moisture", "value": values["soil_moisture"], "unit": "%"},
            {"sensorType": "temperature", "value": values["temperature"], "unit": "C"},
            {"sensorType": "humidity", "value": values["humidity"], "unit": "%"},
        ],
    }

    try:
        r = requests.post(
            BACKEND_URL,
            json=payload,
            headers={"x-device-key": DEVICE_KEY},
            timeout=10,
        )
        print(r.status_code, r.text)
    except Exception as e:
        print("send failed:", e)

    time.sleep(60)  # send every 60 seconds
