import
  std/tables,
  chronos, chronicles, metrics, stew/results,
  libp2p/protocols/pubsub/rpc/[messages, protobuf],
  libp2p/protocols/protocol,
  libp2p/protobuf/minprotobuf,
  libp2p/stream/connection,
  ./message_notifier

const
  WakuStoreCodec* = "/vac/waku/store/2.0.0-alpha4"

type
  HistoryQuery* = object
    uuid*: string
    topics*: seq[string]

  HistoryResponse* = object
    uuid*: string
    messages*: seq[Message]

  WakuStore* = ref object of LPProtocol
    messages*: seq[Message]

proc init*(T: type HistoryQuery, buffer: seq[byte]): ProtoResult[T] =
  var msg = HistoryQuery()
  let pb = initProtoBuffer(buffer)

  var topics: seq[string]

  discard ? pb.getField(1, msg.uuid)
  discard ? pb.getRepeatedField(2, topics)

  msg.topics = topics
  ok(msg)

proc init*(T: type HistoryResponse, buffer: seq[byte]): ProtoResult[T] =
  var msg = HistoryResponse()
  let pb = initProtoBuffer(buffer)

  var messages: seq[seq[byte]]

  discard ? pb.getField(1, msg.uuid)
  discard ? pb.getRepeatedField(2, messages)

  for buf in messages:
    msg.messages.add(? protobuf.decodeMessage(initProtoBuffer(buf)))

  ok(msg)

proc encode*(query: HistoryQuery): ProtoBuffer =
  result = initProtoBuffer()

  result.write(1, query.uuid)

  for topic in query.topics:
    result.write(2, topic)

proc encode*(response: HistoryResponse): ProtoBuffer =
  result = initProtoBuffer()

  result.write(1, response.uuid)

  for msg in response.messages:
    result.write(2, msg.encodeMessage())

proc query(w: WakuStore, query: HistoryQuery): HistoryResponse =
  result = HistoryResponse(uuid: query.uuid, messages: newSeq[Message]())
  for msg in w.messages:
    for topic in query.topics:
      if topic in msg.topicIDs:
        result.messages.insert(msg)
        break

proc init*(T: type WakuStore): T =
  var ws = WakuStore()
  
  proc handle(conn: Connection, proto: string) {.async, gcsafe, closure.} =
    var message = await conn.readLp(64*1024)
    var rpc = HistoryQuery.init(message)
    if rpc.isErr:
      return

    info "received query"

    let res = ws.query(rpc.value)

    await conn.writeLp(res.encode().buffer)

  ws.handler = handle
  ws.codec = WakuStoreCodec
  result = ws

proc subscription*(proto: WakuStore): MessageNotificationSubscription =
  ## The filter function returns the pubsub filter for the node.
  ## This is used to pipe messages into the storage, therefore
  ## the filter should be used by the component that receives
  ## new messages.
  proc handle(msg: Message) =
    proto.messages.add(msg)

  MessageNotificationSubscription.init(@[], handle)