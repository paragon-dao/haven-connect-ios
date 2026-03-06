import Foundation

/// JavaScript polyfill that implements the Web Bluetooth API.
///
/// This gets injected into every web page at document start.
/// When a page calls navigator.bluetooth.requestDevice(), the polyfill
/// routes it through window.webkit.messageHandlers.havenBLE to the
/// native BLEManager via CoreBluetooth.
///
/// The web page doesn't know it's running in Haven Connect vs Chrome.
/// The same Web Bluetooth code works in both.
enum WebBluetoothPolyfill {
    static let javascript = """
    (function() {
        'use strict';

        // Don't inject if Web Bluetooth is already natively supported
        if (navigator.bluetooth) return;

        const pendingRequests = new Map();
        let requestId = 0;
        const devices = {};
        const gattServers = {};
        const notifyCallbacks = {};

        // Internal bridge object
        window.__havenBLE = {
            onDeviceDiscovered: function(device) {
                if (typeof device.id !== 'string') return;
                devices[device.id] = device;
                // Resolve the oldest pending requestDevice call
                for (const [id, pending] of pendingRequests) {
                    if (pending.type === 'requestDevice') {
                        pendingRequests.delete(id);
                        pending.resolve(createBluetoothDevice(device));
                        return;
                    }
                }
            },
            onConnected: function(deviceId) {
                if (typeof deviceId !== 'string') return;
                for (const [id, pending] of pendingRequests) {
                    if (pending.type === 'connect' && pending.deviceId === deviceId) {
                        pendingRequests.delete(id);
                        const server = createGATTServer(deviceId);
                        gattServers[deviceId] = server;
                        pending.resolve(server);
                        return;
                    }
                }
            },
            onDisconnected: function(deviceId) {
                if (typeof deviceId !== 'string') return;
                const server = gattServers[deviceId];
                if (server) server.connected = false;
                const device = devices[deviceId];
                if (device && device._eventTarget) {
                    device._eventTarget.dispatchEvent(new Event('gattserverdisconnected'));
                }
            },
            onCharacteristicValueChanged: function(deviceId, charUUID, value) {
                if (typeof charUUID !== 'string') return;
                var key = charUUID.toLowerCase();
                // Resolve any pending read for this device + characteristic
                for (const [id, pending] of pendingRequests) {
                    if (pending.type === 'read' && pending.charUUID.toLowerCase() === key && pending.deviceId === deviceId) {
                        pendingRequests.delete(id);
                        pending.resolve(new DataView(value.buffer));
                        break;
                    }
                }
                // Fire notification callbacks
                var callbackKey = deviceId + ':' + key;
                if (notifyCallbacks[callbackKey]) {
                    var event = new Event('characteristicvaluechanged');
                    event.target = { value: new DataView(value.buffer) };
                    notifyCallbacks[callbackKey].forEach(function(cb) { cb(event); });
                }
            },
            onError: function(error) {
                if (typeof error !== 'string') return;
                // Reject the oldest pending request
                for (const [id, pending] of pendingRequests) {
                    pendingRequests.delete(id);
                    pending.reject(new DOMException(error, 'NetworkError'));
                    return;
                }
                console.error('[Haven Connect] BLE error with no pending request:', error);
            }
        };

        function sendToNative(action, params) {
            try {
                window.webkit.messageHandlers.havenBLE.postMessage(
                    Object.assign({ action: action }, params || {})
                );
            } catch (e) {
                console.error('[Haven Connect] Native bridge unavailable:', e);
            }
        }

        function createBluetoothDevice(info) {
            var eventTarget = new EventTarget();
            var device = {
                id: info.id,
                name: info.name,
                gatt: {
                    connected: false,
                    connect: function() {
                        return new Promise(function(resolve, reject) {
                            var id = ++requestId;
                            pendingRequests.set(id, { id: id, type: 'connect', deviceId: info.id, resolve: resolve, reject: reject });
                            sendToNative('connect', { deviceId: info.id });
                        });
                    },
                    disconnect: function() {
                        sendToNative('disconnect', { deviceId: info.id });
                    }
                },
                addEventListener: eventTarget.addEventListener.bind(eventTarget),
                removeEventListener: eventTarget.removeEventListener.bind(eventTarget),
                _eventTarget: eventTarget
            };
            devices[info.id] = device;
            return device;
        }

        function createGATTServer(deviceId) {
            return {
                connected: true,
                device: devices[deviceId],
                disconnect: function() {
                    this.connected = false;
                    sendToNative('disconnect', { deviceId: deviceId });
                },
                getPrimaryService: function(serviceUUID) {
                    return Promise.resolve(createService(deviceId, serviceUUID));
                },
                getPrimaryServices: function() {
                    return Promise.resolve([]);
                }
            };
        }

        function createService(deviceId, serviceUUID) {
            return {
                uuid: serviceUUID,
                device: devices[deviceId],
                getCharacteristic: function(charUUID) {
                    return Promise.resolve(createCharacteristic(deviceId, serviceUUID, charUUID));
                },
                getCharacteristics: function() {
                    return Promise.resolve([]);
                }
            };
        }

        function createCharacteristic(deviceId, serviceUUID, charUUID) {
            var key = charUUID.toLowerCase();
            var callbackKey = deviceId + ':' + key;
            var char = {
                uuid: charUUID,
                service: { uuid: serviceUUID },
                value: null,
                readValue: function() {
                    return new Promise(function(resolve, reject) {
                        var id = ++requestId;
                        pendingRequests.set(id, { id: id, type: 'read', deviceId: deviceId, charUUID: charUUID, resolve: resolve, reject: reject });
                        sendToNative('readCharacteristic', {
                            deviceId: deviceId,
                            serviceUUID: serviceUUID,
                            characteristicUUID: charUUID
                        });
                    });
                },
                writeValue: function(value) {
                    var bytes = Array.from(new Uint8Array(
                        value instanceof ArrayBuffer ? value : value.buffer
                    ));
                    sendToNative('writeCharacteristic', {
                        deviceId: deviceId,
                        serviceUUID: serviceUUID,
                        characteristicUUID: charUUID,
                        value: bytes
                    });
                    return Promise.resolve();
                },
                writeValueWithResponse: function(value) {
                    return this.writeValue(value);
                },
                writeValueWithoutResponse: function(value) {
                    return this.writeValue(value);
                },
                startNotifications: function() {
                    if (!notifyCallbacks[callbackKey]) notifyCallbacks[callbackKey] = [];
                    sendToNative('startNotifications', {
                        deviceId: deviceId,
                        serviceUUID: serviceUUID,
                        characteristicUUID: charUUID
                    });
                    return Promise.resolve(char);
                },
                stopNotifications: function() {
                    delete notifyCallbacks[callbackKey];
                    sendToNative('stopNotifications', {
                        deviceId: deviceId,
                        serviceUUID: serviceUUID,
                        characteristicUUID: charUUID
                    });
                    return Promise.resolve(char);
                },
                addEventListener: function(event, callback) {
                    if (event === 'characteristicvaluechanged') {
                        if (!notifyCallbacks[callbackKey]) notifyCallbacks[callbackKey] = [];
                        notifyCallbacks[callbackKey].push(callback);
                    }
                },
                removeEventListener: function(event, callback) {
                    if (event === 'characteristicvaluechanged' && notifyCallbacks[callbackKey]) {
                        notifyCallbacks[callbackKey] = notifyCallbacks[callbackKey].filter(function(cb) { return cb !== callback; });
                    }
                }
            };
            return char;
        }

        // Install the polyfill
        navigator.bluetooth = {
            requestDevice: function(options) {
                return new Promise(function(resolve, reject) {
                    var id = ++requestId;
                    pendingRequests.set(id, { id: id, type: 'requestDevice', resolve: resolve, reject: reject });
                    sendToNative('requestDevice', {
                        filters: options && options.filters ? options.filters : null
                    });
                });
            },
            getAvailability: function() {
                return Promise.resolve(true);
            },
            _polyfill: 'haven-connect'
        };

        console.log('[Haven Connect] Web Bluetooth polyfill loaded');
    })();
    """;
}
