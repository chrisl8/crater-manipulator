extends TileMap

var MapGenerated: bool = false

#No longer using arrays, read/write requires an indexing system which negates the performance benefit of using array index overlap as link. Reading Positions and IDs separately may be faster if staggered separately but can be added later and merged into local dictionaries.

#Last change from server, considered highest authority on accuracy
var SyncedData: Dictionary = {}
#Current map state, presumably faster than reading tilemap again
var CurrentData: Dictionary = {}
#Local modifications buffered until next sync cycle
var ChangedData: Dictionary = {}

#NOTE : Godot passes all dictionaries by reference, remember that.

const ChunkSize = 200

var IsServer = false

var ServerDataChanged = false


#Initialization
func _ready() -> void:
	IsServer = Globals.is_server

	if IsServer:
		GenerateMap()
		Globals.initial_map_load_finished = true
	else:
		RequestBlockState.rpc_id(1)

	Globals.WorldMap = self


#Procedural world generation
func GenerateMap():
	var Diameter = 400
	var CurrentRadius = Diameter / 2
	var Radius = Diameter / 2

	var TopCenter = -10
	var BottomCenter = -130
	var TopEdge = 5
	var BottomEdge = -10

	while CurrentRadius >= 0:
		var RadialMultiplier = 1.0 - cos(3.14159265 / Radius * CurrentRadius / 2.0)
		var TopHeight = roundi(
			(
				float(TopCenter)
				+ (
					(float(TopEdge) - float(TopCenter))
					/ float(Radius)
					* float(CurrentRadius)
					* float(RadialMultiplier)
				)
			)
		)
		var BottomHeight = roundi(
			(
				float(BottomCenter)
				+ (
					(float(BottomEdge) - float(BottomCenter))
					/ float(Radius)
					* float(CurrentRadius)
					* float(RadialMultiplier)
				)
			)
		)

		var BottomHeightA = BottomHeight + randi_range(-2, 2)
		var BottomHeightB = BottomHeight + randi_range(-2, 2)

		for Level in range(BottomHeightA, TopHeight, 1):
			if randf() > 0.98:
				CurrentData[Vector2i(CurrentRadius, -Level)] = GetRandomOreTile()
			else:
				CurrentData[Vector2i(CurrentRadius, -Level)] = GetRandomStoneTile()

		for Level in range(BottomHeightB, TopHeight, 1):
			if randf() > 0.98:
				CurrentData[Vector2i(-CurrentRadius, -Level)] = GetRandomOreTile()
			else:
				CurrentData[Vector2i(-CurrentRadius, -Level)] = GetRandomStoneTile()

		CurrentRadius -= 1.0

	SetAllCellData(CurrentData, 0)
	SyncedData = CurrentData
	MapGenerated = true


#Gets a random valid stone tile ID from the atlas
func GetRandomStoneTile():
	return Vector2i(randi_range(0, 9), 0)


func GetRandomOreTile():
	return Vector2i(randi_range(0, 9), 1)


var CurrentCycleTime: float = 0.0
const SendFrequency = 0.1


func _process(delta: float) -> void:
	CurrentCycleTime += delta
	if CurrentCycleTime > SendFrequency:
		if !IsServer:
			PushChangedData()
		else:
			ServerSendBufferedChanges()
		CurrentCycleTime = 0.0

	if IsServer and MapGenerated:
		var Count = len(PlayersToSendInitialState) - 1
		if Count > -1:
			ProcessChunkedInitialStateData()

		if(len(StoredPlayerInventoryDrops)):
			for Key in StoredPlayerInventoryDrops.keys():
				Globals.Players[Key].AddInventoryData.rpc(StoredPlayerInventoryDrops[Key])
			StoredPlayerInventoryDrops.clear()

	if IsServer and ServerDataChanged:
		ServerDataChanged = false
		SetAllCellData(SyncedData, 0)


#Check for any buffered change data on the server (data received from clients and waiting to be sent), then chunk it and send it out to clients
func ServerSendBufferedChanges():
	if len(ServerBufferedChanges.keys()) > 0:
		var Count = ChunkSize
		var ChunkedData = {}
		while Count > 0 and len(ServerBufferedChanges.keys()) > 0:
			ChunkedData[ServerBufferedChanges.keys()[0]] = ServerBufferedChanges[
				ServerBufferedChanges.keys()[0]
			]
			ServerBufferedChanges.erase(ServerBufferedChanges.keys()[0])
			Count -= 1
		ServerSendChangedData.rpc(ChunkedData)


#Set the tile map to the given values at given cells. Clears the tile map before doing so. Meant for complete map refreshes, not for incremental changes
func SetAllCellData(Data: Dictionary, Layer: int) -> void:
	clear_layer(Layer)
	for Key: Vector2i in Data.keys():
		set_cell(Layer, Key, 0, Data[Key])


#Get the positions of every cell in the tile map
func GetCellPositions(Layer: int) -> Array[Vector2i]:
	var Positions: Array[Vector2i] = get_used_cells(Layer)
	return Positions


#Get the tile IDs of every cell in the tile map
func GetCellIDs(Layer):
	var IDs: Array[Vector2i]
	var Positions: Array[Vector2i] = get_used_cells(Layer)

	for Position in Positions:
		IDs.append(get_cell_atlas_coords(Layer, Position))
	return IDs


var PlayersToSendInitialState: Array[int] = []
var InitialStatesRemainingPos = []
var InitialStatesRemainingIDs = []

#Requests a world state sync from the server, this is an initial request only sent when a client first joins
@rpc("any_peer", "call_remote", "reliable")
func RequestBlockState() -> void:
	if IsServer:
		PlayersToSendInitialState.append(multiplayer.get_remote_sender_id())

		var Values = []
		for Key in SyncedData.keys():
			Values.append(SyncedData[Key])

		InitialStatesRemainingPos.append(SyncedData.keys())
		InitialStatesRemainingIDs.append(Values)


#Processes chunked initial states for each client that has requested a world state sync
#Currently sends out chunks to every client in parallel, but should probably send out data to one client at a time to avoid many simultaneous RPCs if multiple clients join at the same time
func ProcessChunkedInitialStateData():
	var Count = len(PlayersToSendInitialState) - 1
	if Count > -1:
		while Count >= 0:
			var SliceCount = clamp(ChunkSize, 0, len(InitialStatesRemainingPos[Count]))
			var SlicePositions = InitialStatesRemainingPos[Count].slice(0, SliceCount)
			var SliceIDs = InitialStatesRemainingIDs[Count].slice(0, SliceCount)
			while SliceCount > 0:
				InitialStatesRemainingPos[Count - 1].remove_at(0)
				InitialStatesRemainingIDs[Count - 1].remove_at(0)
				SliceCount -= 1

			(
				SendBlockState
				. rpc_id(
					PlayersToSendInitialState[Count],
					SlicePositions,
					SliceIDs,
					len(InitialStatesRemainingPos[Count]) == 0,
				)
			)

			if len(InitialStatesRemainingPos[Count]) == 0:
				InitialStatesRemainingPos.remove_at(Count)
				InitialStatesRemainingIDs.remove_at(Count)
				PlayersToSendInitialState.remove_at(Count)
			Count -= 1


'''
func ServerCompressAndSendBlockStates(Data, Finished):
	#Too much data, need to compress somehow
	var CompressedData: StreamPeerBuffer = StreamPeerBuffer.new()

	var Count: int = len(SyncedData.keys())
	CompressedData.put_u32(Count)

	while(Count-1>=0):
		CompressedData.put_32(SyncedData.keys()[Count-1].x)
		CompressedData.put_32(SyncedData.keys()[Count-1].y)

		CompressedData.put_32(SyncedData.values()[Count-1].x)
		CompressedData.put_32(SyncedData.values()[Count-1].y)
		Count-=1

	SendBlockState.rpc(CompressedData.data_array, Finished)
'''
#Send chunks of the world dat block to clients, used for initial world sync
@rpc("authority", "call_remote", "reliable")
func SendBlockState(Positions, IDs, Finished) -> void:
	if !Globals.initial_map_load_finished:
		#Compression system, removed for now because didn't give significant performance improvement
		'''
		var Positions = []
		var IDs = []

		var ExtractedData = StreamPeerBuffer.new()
		ExtractedData.data_array  = Data

		var Length = ExtractedData.get_u32()-1
		while(Length >= 0):
			Positions.append(Vector2i(ExtractedData.get_32(),ExtractedData.get_32()))
			IDs.append(Vector2i(ExtractedData.get_32(),ExtractedData.get_32()))
			Length-=1
		'''

		var Count = len(Positions) - 1
		while Count >= 0:
			SyncedData[Positions[Count]] = IDs[Count]
			CurrentData[Positions[Count]] = IDs[Count]
			Count -= 1

		if Finished:
			if len(BufferedChangesReceivedFromServer) > 0:
				for BufferedChange in BufferedChangesReceivedFromServer:
					for Key: Vector2i in BufferedChange.keys():
						SyncedData[Key] = BufferedChange[Key]
						CurrentData[Key] = BufferedChange[Key]
			BufferedChangesReceivedFromServer.clear()

		SetAllCellData(CurrentData, 0)

		Globals.initial_map_load_finished = Finished
		if Globals.initial_map_load_finished:
			Helpers.log_print("Finished loading map.")


#Architecture plan:

#Players modify local data
#Push data to server, store buffered status
#Server receives push and overwrites local data
#Server pushes modifications to all clients
#Receiving client accepts changes
#Failed local state revision drops placed cells, drop items are not spawned until state change is confirmed

#Design Issues:
#Empty cells considered empty data, requires updating entire tile map for empty refresh (expensive?)
#Solution is to store remove tile changes as separate system


#Modify a cell from the client, checks for finished world load and buffers changes for server accordingly
func ModifyCell(Position: Vector2i, ID: Vector2i):
	if !Globals.initial_map_load_finished:
		#Not allowed to modify map until first state received
		#Because current map is not trustworthy, not cleared on start so player doesn't fall through world immediately.
		return
	if (Position in ChangedData.keys()):
		ChangedData[Position] = [ChangedData[Position][0], ID]
	elif (SyncedData.has(Position)):
		ChangedData[Position] = [SyncedData[Position], ID]
	else:
		ChangedData[Position] = [Vector2i(-1,-1), ID]


	SetCellData(Position, ID)


#Place air at a position : TEST TEMP
func MineCellAtPosition(Position: Vector2):
	ModifyCell(local_to_map(to_local(Position)), Vector2i(-1, -1))


#Place a standard piece of stone at a position : TEST TEMP
func PlaceCellAtPosition(Position: Vector2):
	ModifyCell(local_to_map(to_local(Position)), GetRandomStoneTile())


#Set the current data of a cell to a given value
func SetCellData(Position: Vector2i, ID: Vector2i) -> void:
	CurrentData[Position] = ID
	set_cell(0, Position, 0, ID)


#Push change data stored on the client to the server, if there is any
#Still need to add chunking to this process right here
func PushChangedData() -> void:
	if len(ChangedData.keys()) > 0:
		RPCSendChangedData.rpc(ChangedData)
		ChangedData.clear()


#Changes the server has received and accepted, and is waiting to send back to all clients later
var ServerBufferedChanges: Dictionary = {}

#Sends changes from the client to the server to be processed
@rpc("any_peer", "call_remote", "reliable")
func RPCSendChangedData(Data: Dictionary) -> void:
	if IsServer:
		var Player = multiplayer.get_remote_sender_id()
		for Key: Vector2i in Data.keys():
			if(not SyncedData.has(Key) or SyncedData[Key] == Data[Key][0]):
				ServerBufferedChanges[Key] = Data[Key][1]
				SyncedData[Key] = Data[Key][1]

				
				if(Data[Key][0].y > -1):
					if(Player not in StoredPlayerInventoryDrops.keys()):
						StoredPlayerInventoryDrops[Player] = {}
					if(Data[Key][0].y in StoredPlayerInventoryDrops[Player].keys()):
						StoredPlayerInventoryDrops[Player][Data[Key][0].y]+=1
					else:
						StoredPlayerInventoryDrops[Player][Data[Key][0].y] = 1

		ServerDataChanged = true

var StoredPlayerInventoryDrops = {}


var BufferedChangesReceivedFromServer: Array[Dictionary] = []

#Sends changes from the server to clients
@rpc("authority", "call_remote", "reliable")
func ServerSendChangedData(Data: Dictionary) -> void:
	if !Globals.initial_map_load_finished:
		#Store changes and process after the maps has been fully loaded
		BufferedChangesReceivedFromServer.append(Data)
		return
	if IsServer:
		return
	for Key: Vector2i in Data.keys():
		SyncedData[Key] = Data[Key]
		CurrentData[Key] = Data[Key]
		UpdateCellFromCurrent(Key)


#Updates a cells tile from current data
func UpdateCellFromCurrent(Position):
	set_cell(0, Position, 0, CurrentData[Position])
