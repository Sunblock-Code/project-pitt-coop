extends Node

var session: Node
var last_received: Dictionary = {}
var timer = 0.0
var longest_frame = 0.0

func configure(id: int):
	var peer = session.net.get_peer(id)
	if peer:
		peer.set_timeout(32, 30000, 90000)
		peer.ping_interval(500)
	last_received[id] = Time.get_ticks_msec()
	record("connected", id)

func _process(delta):
	longest_frame = maxf(longest_frame, delta)
	timer += delta
	if timer < 15.0 or session.net == null: return
	timer = 0.0
	if session.role == "host":
		for id in session.peers: record("health", id)
	elif session.role in ["guest", "waiting", "loading"]: record("health", 1)
	longest_frame = 0.0

func record(event: String, id: int):
	var row = {"time": Time.get_datetime_string_from_system(), "event": event, "role": session.role, "peer": id, "receive_gap_ms": Time.get_ticks_msec() - last_received.get(id, Time.get_ticks_msec()), "longest_frame_ms": snappedf(longest_frame * 1000.0, 0.1)}
	if session.net and session.net.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and event != "peer_disconnected":
		var peer = session.net.get_peer(id)
		if peer:
			row.rtt_ms = peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
			row.loss = peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / ENetPacketPeer.PACKET_LOSS_SCALE
	var path = OS.get_executable_path().get_base_dir().path_join("../logs/connection.jsonl")
	var file = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(JSON.stringify(row))
		file.flush()
