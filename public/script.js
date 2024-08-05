let stream = null;
let sensorData = {
  timestamp: 0,
  acceleration: { x: 0, y: 0, z: 0 },
  rotation: { alpha: 0, beta: 0, gamma: 0 }
};
let capturedData = [];

document.getElementById('startCameraButton').addEventListener('click', startCamera);
document.getElementById('stopCameraButton').addEventListener('click', stopCamera);
document.getElementById('accessSensorsButton').addEventListener('click', accessSensors);
document.getElementById('saveButton').addEventListener('click', saveData);

function startCamera() {
  navigator.mediaDevices.getUserMedia({ video: { facingMode: { exact: "environment" } } })
    .then(function(s) {
      stream = s;
      const video = document.getElementById('video');
      video.srcObject = stream;
    })
    .catch(function(err) {
      console.error("Error accessing the camera: ", err);
    });
}

function stopCamera() {
  if (stream) {
    stream.getTracks().forEach(track => track.stop());
    const video = document.getElementById('video');
    video.srcObject = null;
  }
}

function accessSensors() {
  if (typeof DeviceMotionEvent.requestPermission === 'function') {
    DeviceMotionEvent.requestPermission()
      .then(permissionState => {
        if (permissionState === 'granted') {
          window.addEventListener('devicemotion', handleDeviceMotion);
        }
      })
      .catch(console.error);
  } else {
    window.addEventListener('devicemotion', handleDeviceMotion);
  }

  if (typeof DeviceOrientationEvent.requestPermission === 'function') {
    DeviceOrientationEvent.requestPermission()
      .then(permissionState => {
        if (permissionState === 'granted') {
          window.addEventListener('deviceorientation', handleDeviceOrientation);
        }
      })
      .catch(console.error);
  } else {
    window.addEventListener('deviceorientation', handleDeviceOrientation);
  }
}

function handleDeviceMotion(event) {
  console.log("DeviceMotionEvent triggered");
  sensorData.timestamp = Date.now();
  sensorData.acceleration.x = event.accelerationIncludingGravity.x;
  sensorData.acceleration.y = event.accelerationIncludingGravity.y;
  sensorData.acceleration.z = event.accelerationIncludingGravity.z;
}

function handleDeviceOrientation(event) {
  console.log("DeviceOrientationEvent triggered");
  sensorData.rotation.alpha = event.alpha;
  sensorData.rotation.beta = event.beta;
  sensorData.rotation.gamma = event.gamma;
}

function processFrame() {
  const video = document.getElementById('video');
  if (!video.srcObject) return; // Exit if the camera is not started
  const canvas = document.createElement('canvas');
  const context = canvas.getContext('2d');
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  context.drawImage(video, 0, 0, canvas.width, canvas.height);

  const frameData = {
    timestamp: sensorData.timestamp,
    acceleration: sensorData.acceleration,
    rotation: sensorData.rotation,
    image: canvas.toDataURL() // Get the image data in base64 format
  };

  console.log(frameData);
  capturedData.push(frameData);
}

setInterval(processFrame, 1000 / 30); // Process frame at 30 FPS

function saveData() {
  const blob = new Blob([JSON.stringify(capturedData, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `captured_data_${Date.now()}.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
