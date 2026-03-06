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

        var REQUEST_TIMEOUT_MS = 30000;
        var pendingRequests = new Map();
        var requestId = 0;
        var devices = {};
        var gattServers = {};
        var notifyCallbacks = {};
        var servicesReady = {};

        function timeoutRequest(id, label) {
            return setTimeout(function() {
                var pending = pendingRequests.get(id);
                if (pending) {
                    pendingRequests.delete(id);
                    pending.reject(new DOMException(
                        label + ' timed out after ' + REQUEST_TIMEOUT_MS + 'ms',
                        'TimeoutError'
                    ));
                }
            }, REQUEST_TIMEOUT_MS);
        }

        function addPending(type, extra) {
            return new Promise(function(resolve, reject) {
                var id = ++requestId;
                var entry = Object.assign({ id: id, type: type, resolve: resolve, reject: reject }, extra || {});
                pendingRequests.set(id, entry);
                entry._timer = timeoutRequest(id, type);
                return id;
            });
        }

        function resolvePending(predicate) {
            for (var entry of pendingRequests) {
                var id = entry[0], pending = entry[1];
                if (predicate(pending)) {
                    clearTimeout(pending._timer);
                    pendingRequests.delete(id);
                    return pending;
                }
            }
            return null;
        }

        // Internal bridge object
        window.__havenBLE = {
            onDeviceDiscovered: function(device) {
                if (typeof device.id !== 'string') return;
                devices[device.id] = device;
                var pending = resolvePending(function(p) { return p.type === 'requestDevice'; });
                if (pending) pending.resolve(createBluetoothDevice(device));
            },
            onConnected: function(deviceId) {
                if (typeof deviceId !== 'string') return;
                var pending = resolvePending(function(p) {
                    return p.type === 'connect' && p.deviceId === deviceId;
                });
                if (pending) {
                    var server = createGATTServer(deviceId);
                    gattServers[deviceId] = server;
                    pending.resolve(server);
                }
            },
            onDisconnected: function(deviceId) {
                if (typeof deviceId !== 'string') return;
                servicesReady[deviceId] = false;
                var server = gattServers[deviceId];
                if (server) server.connected = false;
                var device = devices[deviceId];
                if (device && device._eventTarget) {
                    device._eventTarget.dispatchEvent(new Event('gattserverdisconnected'));
                }
                // Reject any pending requests for this device
                for (var entry of pendingRequests) {
                    var id = entry[0], pending = entry[1];
                    if (pending.deviceId === deviceId) {
                        clearTimeout(pending._timer);
                        pendingRequests.delete(id);
                        pending.reject(new DOMException('Device disconnected', 'NetworkError'));
                    }
                }
            },
            onServicesReady: function(deviceId) {
                if (typeof deviceId !== 'string') return;
                servicesReady[deviceId] = true;
                // Resolve any pending getPrimaryService calls
                for (var entry of pendingRequests) {
                    var id = entry[0], pending = entry[1];
                    if (pending.type === 'getPrimaryService' && pending.deviceId === deviceId) {
                        clearTimeout(pending._timer);
                        pendingRequests.delete(id);
                        pending.resolve(createService(deviceId, pending.serviceUUID));
                    }
                }
            },
            onCharacteristicValueChanged: function(deviceId, charUUID, value) {
                if (typeof charUUID !== 'string') return;
                var key = charUUID.toLowerCase();
                // Resolve any pending read for this device + characteristic
                var pending = resolvePending(function(p) {
                    return p.type === 'read' && p.charUUID.toLowerCase() === key && p.deviceId === deviceId;
                });
                if (pending) {
                    pending.resolve(new DataView(value.buffer));
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
                // Try to match error to the right pending request type
                var pending = null;
                if (error.indexOf('connect') !== -1 || error.indexOf('Connection') !== -1) {
                    pending = resolvePending(function(p) { return p.type === 'connect'; });
                }
                if (!pending && error.indexOf('Characteristic') !== -1) {
                    pending = resolvePending(function(p) { return p.type === 'read' || p.type === 'write'; });
                }
                // Fallback: reject the oldest pending request
                if (!pending) {
                    pending = resolvePending(function() { return true; });
                }
                if (pending) {
                    pending.reject(new DOMException(error, 'NetworkError'));
                } else {
                    console.error('[Haven Connect] BLE error with no pending request:', error);
                }
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
                            var entry = { id: id, type: 'connect', deviceId: info.id, resolve: resolve, reject: reject };
                            pendingRequests.set(id, entry);
                            entry._timer = timeoutRequest(id, 'connect');
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
                    // Wait for service discovery to complete before resolving
                    if (servicesReady[deviceId]) {
                        return Promise.resolve(createService(deviceId, serviceUUID));
                    }
                    return new Promise(function(resolve, reject) {
                        var id = ++requestId;
                        var entry = {
                            id: id, type: 'getPrimaryService', deviceId: deviceId,
                            serviceUUID: serviceUUID, resolve: resolve, reject: reject
                        };
                        pendingRequests.set(id, entry);
                        entry._timer = timeoutRequest(id, 'getPrimaryService');
                    });
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
                        var entry = {
                            id: id, type: 'read', deviceId: deviceId,
                            charUUID: charUUID, resolve: resolve, reject: reject
                        };
                        pendingRequests.set(id, entry);
                        entry._timer = timeoutRequest(id, 'readValue');
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
                    var entry = { id: id, type: 'requestDevice', resolve: resolve, reject: reject };
                    pendingRequests.set(id, entry);
                    entry._timer = timeoutRequest(id, 'requestDevice');
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
