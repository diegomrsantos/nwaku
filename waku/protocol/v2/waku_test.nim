import unittest
import sequtils, tables, options, sets, strutils
import chronos, chronicles

import waku_protocol
import utils
import standard_setup

# TODO: Move to test folder

# XXX: Testing in-line
proc waitSub(sender, receiver: auto; key: string) {.async, gcsafe.} =
  # turn things deterministic
  # this is for testing purposes only
  var ceil = 15
  let wsub = cast[WakuSub](sender.pubSub.get())
  while not wsub.floodsub.hasKey(key) or
        not wsub.floodsub[key].contains(receiver.peerInfo.id):
    await sleepAsync(100.millis)
    dec ceil
    doAssert(ceil > 0, "waitSub timeout!")

proc test(): Future[bool] {.async.} =
  var completionFut = newFuture[bool]()
  proc handler(topic: string, data: seq[byte]) {.async, gcsafe.} =
    echo "HIT HANDLER", topic
    check topic == "foobar"
    completionFut.complete(true)

  # XXX: Right, same issue as before! Switch interface is here
  # Though this is newStandardSwitch
  # HERE ATM: We need to take this and...do something
  # PubSub newPubSub(FloodSub, peerInfo, triggerSelf)
  # Goal: Init WakuSub that inherits from FloodSub and then print text field
  # Should be fine if we take standard switch code and create from here, I think

  # How is this done elsewhere? Tests.

  let
    nodes = generateNodes(2)
    nodesFut = await allFinished(
      nodes[0].start(),
      nodes[1].start()
    )

  # TODO: We never init this
  # Meaning?
  # Where did I even get this from? waitSub
  #let wsub = cast[WakuSub](nodes[0].pubSub.get())
  #echo "wsub test", $repr(wsub)
  # illegal storage access
  #echo "wsub field test", wsub.text

  await subscribeNodes(nodes)

  await nodes[1].subscribe("foobar", handler)
  await waitSub(nodes[0], nodes[1], "foobar")

  await nodes[0].publish("foobar", cast[seq[byte]]("Hello!"))

  echo "ok"
  result = await completionFut.wait(5.seconds)

#  await allFuturesThrowing(
#    nodes[0].stop(),
#    nodes[1].stop()
#  )
#
#  for fut in nodesFut:
#    let res = fut.read()
#    await allFuturesThrowing(res)

echo "Starting"
var res = waitFor test()
echo "Done with res: ", $res