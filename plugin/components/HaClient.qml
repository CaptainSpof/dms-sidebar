import QtQuick
import QtWebSockets

// Home Assistant WebSocket client. Keeps `states` (entity_id -> state object)
// live and resolves each entity's area. Reactivity: `states`, `entityArea` and
// `areas` are replaced, never mutated, so bindings re-evaluate.
Item {
    id: root

    property string url: ""
    property string token: ""
    property bool active: false

    // "idle" | "connecting" | "authenticating" | "ready" | "error"
    property string phase: "idle"
    property string errorText: ""
    property var states: ({})
    property var areas: ({})        // area_id -> name
    property var entityArea: ({})   // entity_id -> area_id
    property var hidden: ({})       // entity_id -> true (hidden or disabled in the registry)

    readonly property bool ready: phase === "ready"
    readonly property string wsUrl: url ? url.replace(/\/+$/, "").replace(/^http/, "ws") + "/api/websocket" : ""

    property int _nextId: 1
    property var _pending: ({})     // msg id -> handler
    property var _batch: ({})
    property var _entities: []
    property var _devices: []

    function callService(domain, service, data, entityId) {
        _send({
            type: "call_service",
            domain: domain,
            service: service,
            service_data: data || {},
            target: entityId ? {entity_id: entityId} : undefined
        });
    }

    function stateOf(entityId) {
        return states[entityId];
    }

    function areaNameOf(entityId) {
        return areas[entityArea[entityId]] || "";
    }


    function _send(msg, handler) {
        const id = _nextId++;
        msg.id = id;
        if (handler)
            _pending[id] = handler;
        socket.sendTextMessage(JSON.stringify(msg));
        return id;
    }

    function _fail(text) {
        errorText = text;
        phase = "error";
        socket.active = false;
        retry.restart();
    }

    function _start() {
        _pending = ({});
        _nextId = 1;
        errorText = "";
        if (!wsUrl || !token) {
            phase = "idle";
            return;
        }
        phase = "connecting";
        socket.active = true;
    }

    function _stop() {
        retry.stop();
        socket.active = false;
        phase = "idle";
    }

    function _onReady() {
        _send({type: "get_states"}, m => {
            const next = {};
            (m.result || []).forEach(s => next[s.entity_id] = s);
            states = next;
        });
        _send({type: "subscribe_events", event_type: "state_changed"});
        _send({type: "config/area_registry/list"}, m => {
            const next = {};
            (m.result || []).forEach(a => next[a.area_id] = a.name);
            areas = next;
        });
        _send({type: "config/device_registry/list"}, m => {
            _devices = m.result || [];
            _resolveAreas();
        });
        _send({type: "config/entity_registry/list"}, m => {
            _entities = m.result || [];
            _resolveAreas();
        });
    }

    function _resolveAreas() {
        const byDevice = {};
        _devices.forEach(d => byDevice[d.id] = d.area_id);
        const hiddenNext = {};
        const next = {};
        _entities.forEach(e => {
            if (e.hidden_by || e.disabled_by)
                hiddenNext[e.entity_id] = true;
            const a = e.area_id || (e.device_id ? byDevice[e.device_id] : null);
            if (a)
                next[e.entity_id] = a;
        });
        entityArea = next;
        hidden = hiddenNext;
    }

    function _onMessage(text) {
        const m = JSON.parse(text);
        switch (m.type) {
        case "auth_required":
            phase = "authenticating";
            socket.sendTextMessage(JSON.stringify({type: "auth", access_token: token}));
            break;
        case "auth_ok":
            phase = "ready";
            _onReady();
            break;
        case "auth_invalid":
            _fail("Token refusé : " + (m.message || "auth_invalid"));
            break;
        case "result":
            const h = _pending[m.id];
            if (h) {
                delete _pending[m.id];
                if (m.success)
                    h(m);
            }
            break;
        case "event":
            const d = m.event && m.event.data;
            if (d && d.entity_id) {
                if (d.new_state)
                    _batch[d.entity_id] = d.new_state;
                else
                    _batch[d.entity_id] = null;
                flush.restart();
            }
            break;
        }
    }

    // Coalesce bursts of state_changed events into one `states` replacement.
    Timer {
        id: flush
        interval: 60
        onTriggered: {
            const next = Object.assign({}, root.states);
            for (const id in root._batch) {
                if (root._batch[id] === null)
                    delete next[id];
                else
                    next[id] = root._batch[id];
            }
            root._batch = ({});
            root.states = next;
        }
    }

    Timer {
        id: retry
        interval: 5000
        onTriggered: root._start()
    }

    WebSocket {
        id: socket
        url: root.wsUrl
        active: false
        onTextMessageReceived: message => root._onMessage(message)
        onStatusChanged: status => {
            if (status === WebSocket.Error)
                root._fail(socket.errorString);
            else if (status === WebSocket.Closed && root.phase === "ready") {
                root.phase = "idle";
                retry.restart();
            }
        }
    }

    onActiveChanged: active ? _start() : _stop()
    onWsUrlChanged: if (active) _start()
    onTokenChanged: if (active) _start()
}
