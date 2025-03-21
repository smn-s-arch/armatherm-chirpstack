// Decode uplink function.
//
// Input is an object with the following fields:
// - bytes = Byte array containing the uplink payload, e.g. [255, 230, 255, 0]
// - fPort = Uplink fPort.
// - variables = Object containing the configured device variables.
//
// Output must be an object with the following fields:
// - data = Object representing the decoded payload.
//function decodeUplink(input) {
//  var sbit = 1;
//  return {
//    data: {
//      func: input.bytes[0],
//      measurand: input.bytes[1] * 256 + input.bytes[2],
//      //measurand_2: input.bytes[3] * 256 + input.bytes[4],
//      alarm_status: ((input.bytes[4] & (sbit << 7)) !== 0) ? 1 : 0,
//      alarm_dir: ((input.bytes[4] & sbit) !== 0) ? 1 : 0
//    }
//  };
//}

//////////Decode funcion new////////////////

function decodeUplink(input) {
  // Byte 0: Message type (could be further decoded if needed)
  var messageType = input.bytes[0];
  
  // Bytes 1+2: Measured data (big-endian)
  var measurand = input.bytes[1] * 256 + input.bytes[2];
  
  // Byte 3: Battery voltage (0-100)
  var batteryVoltage = input.bytes[3];
  
  // Byte 4: Alarm byte
  // Bit 7 (0x80) indicates alarm triggered (1) or cleared (0)
  // Bit 0 (0x01) indicates alarm direction (1 for rising, 0 for falling)
  var alarmByte = input.bytes[4];
  var alarm_status = (alarmByte & 0x80) ? 1 : 0;
  var alarm_direction = (alarmByte & 0x01) ? 1 : 0;
  
  return {
    data: {
      func: messageType,
      measurand: measurand,
      batteryVoltage: batteryVoltage,
      alarm_status: alarm_status,
      alarm_direction: alarm_direction
    }
  };
}


// Encode downlink function.
//
// Input is an object with the following fields:
// - data = Object representing the payload that must be encoded.
// - variables = Object containing the configured device variables.
//
// Output must be an object with the following fields:
// - bytes = Byte array containing the downlink payload.
function encodeDownlink(input) {
  var encodedBytes = [];
  if (input.data.func == 1) {
    encodedBytes[0] = 1; 
    encodedBytes[1] = Math.floor(input.data.wait / 256);
    encodedBytes[2] = input.data.wait % 256;
    encodedBytes[3] = Math.floor(input.data.measurements / 256);
    encodedBytes[4] = input.data.measurements % 256;
  } else if (input.data.func == 2) {
    encodedBytes[0] = 2;
    encodedBytes[1] = Math.floor((input.data.threshold + 1000) / 256);
    encodedBytes[2] = (input.data.threshold + 1000) % 256;
    encodedBytes[3] = Math.floor(input.data.deadband / 256);
    encodedBytes[4] = input.data.deadband % 256;
    encodedBytes[5] = 0;
    encodedBytes[5] += input.data.alarm_dir ? 1 : 0;
    encodedBytes[5] += input.data.alarm_thr ? 2 : 0;
    encodedBytes[5] += input.data.alarm_active ? 128 : 0;
  } else if (input.data.func == 128) {
    encodedBytes[0] = 128;
  }

  return {
    bytes: encodedBytes
  };
}