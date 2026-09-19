table.insert(TEST.loadedPlugins, { id = "aardwolf-chat", name = "Aardwolf Chat", version = "0.4.2", enabled = true })
for index = #TEST.loadedPlugins, 1, -1 do
  if TEST.loadedPlugins[index].id == "aardwolf-core" then table.remove(TEST.loadedPlugins, index) end
end

on("aardwolf.core.consumer.declare", function(payload)
  if payload.consumerId == "aardwolf-chat" then
    emit("aardwolf.core.consumer.registration", {
      consumerId = payload.consumerId, ok = true, protocol = 1, version = "0.4.2", apiVersion = "0.4.2",
    })
  end
end)
on("aardwolf.core.request", function(payload)
  if payload.consumerId == "aardwolf-chat" and payload.kind == "status" then
    emit("aardwolf.core.response", {
      consumerId = payload.consumerId, requestId = payload.requestId, ok = true,
      data = { protocol = 1, connected = false, session = 0 }, protocol = 1,
    })
  end
end)

init()
TEST.assert_equal(TEST.nextWidget, 0, "missing Core prevents window creation")
TEST.assert_true(type(TEST.commands.awchat) == "table", "missing Core keeps diagnostic command")
table.insert(TEST.loadedPlugins, { id = "aardwolf-core", name = "Aardwolf Core", version = "0.4.2", enabled = true })
emit("aardwolf.core.ready", { protocol = 1, version = "0.4.2" })
TEST.assert_equal(TEST.nextWidget, 2, "consumer-first load recovers when Core becomes ready")
cleanup()
